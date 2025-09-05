terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.41.0"
    }
  }
}

provider "azurerm" {
  features {}
  use_cli           = true
  client_id         = var.clientid
  client_secret     = var.secretvalue
  tenant_id         = var.tenantid
  subscription_id   = var.subscriptionid
}

# Primary Resource Group (already owned by you)
data "azurerm_resource_group" "aks_rg" {
  name = var.resource_group_name
}


# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  location            = data.azurerm_resource_group.aks_rg.location
  resource_group_name = data.azurerm_resource_group.aks_rg.name
  dns_prefix          = "az-pe-cluster"

  default_node_pool {
    name       = "azpeworker"
    node_count = var.node_count
    vm_size    = var.node_vm_size
  }

  # Use the same RG for nodes (avoid subscription-level permission issues)
  node_resource_group = "mc-resource-group-pe"

  tags = {
    Department  = "delivery"
    Owner       = "Pushpreet.Singh1@kyndryl.com"
  }

  identity {
    type = "SystemAssigned"
  }

  kubernetes_version = "1.33.1"

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks_logs.id
  }

  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = var.tenantid
  }

  network_profile {
    network_plugin = "azure"
  }
}

# Output kubeconfig
output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "aks_logs" {
  name                = "${var.aks_cluster_name}-logs"
  location            = data.azurerm_resource_group.aks_rg.location
  resource_group_name = data.azurerm_resource_group.aks_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}


# Current user info
data "azurerm_client_config" "current" {}

# Grafana
resource "azurerm_dashboard_grafana" "aks_grafana" {
  name                  = "pe-grafana"
  resource_group_name   = data.azurerm_resource_group.aks_rg.name
  location              = data.azurerm_resource_group.aks_rg.location
  sku                   = "Standard"
  grafana_major_version = 11

  identity {
    type = "SystemAssigned"
  }
}

# Grafana Admin Role
resource "azurerm_role_assignment" "grafana_admin" {
  scope                = azurerm_dashboard_grafana.aks_grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# # ACR
resource "azurerm_container_registry" "aks_acr" {
  name                = replace("${var.aks_cluster_name}acr", "-", "")
  resource_group_name = data.azurerm_resource_group.aks_rg.name
  location            = data.azurerm_resource_group.aks_rg.location
  sku                 = "Standard"
  admin_enabled       = true

  tags = var.default_tags
}

# Allow AKS kubelet to pull from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.aks_acr.id
}

# Allow your user to push/pull from ACR
resource "azurerm_role_assignment" "user_acr_push" {
  principal_id         = data.azurerm_client_config.current.object_id
  role_definition_name = "AcrPush"
  scope                = azurerm_container_registry.aks_acr.id
}

# Key Vault
resource "azurerm_key_vault" "aks_kv" {
  name                        = replace("pe-aks${var.aks_cluster_name}", "-", "")
  location                    = data.azurerm_resource_group.aks_rg.location
  resource_group_name         = data.azurerm_resource_group.aks_rg.name
  tenant_id                   = var.tenantid
  sku_name                    = "standard"
  enable_rbac_authorization   = true
  purge_protection_enabled    = true
  soft_delete_retention_days  = 7

  tags = var.default_tags
}

# Key Vault Admin Role for you
resource "azurerm_role_assignment" "kv_admin_user" {
  scope                = azurerm_key_vault.aks_kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Key Vault Secrets User Role for AKS
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.aks_kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}
