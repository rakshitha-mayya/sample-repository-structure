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
resource "azurerm_resource_group" "aks_rg" {
  name = var.resource_group_name
  location = "East US"
}


# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
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
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}


# Current user info
data "azurerm_client_config" "current" {}

# Grafana
resource "azurerm_dashboard_grafana" "aks_grafana" {
  name                  = "pe-grafana"
  resource_group_name   = azurerm_resource_group.aks_rg.name
  location              = azurerm_resource_group.aks_rg.location
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
  resource_group_name = azurerm_resource_group.aks_rg.name
  location            = azurerm_resource_group.aks_rg.location
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
  location                    = azurerm_resource_group.aks_rg.location
  resource_group_name         = azurerm_resource_group.aks_rg.name
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

# Public IP for the Load Balancer
resource "azurerm_public_ip" "alb_pip" {
  name                = "${var.aks_cluster_name}-alb-pip"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  sku                 = "Standard"
  allocation_method   = "Static"

  tags = var.default_tags
}

# Azure Load Balancer (Public)
resource "azurerm_lb" "alb" {
  name                = var.alb_name
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = var.alb_frontend_name
    public_ip_address_id = azurerm_public_ip.alb_pip.id
  }

  tags = var.default_tags
}

# Backend Pool
resource "azurerm_lb_backend_address_pool" "alb_backend" {
  name            = var.alb_backend_pool_name
  loadbalancer_id = azurerm_lb.alb.id
}

# Health Probe (TCP or HTTP)
resource "azurerm_lb_probe" "alb_probe" {
  name                 = "${var.alb_name}-probe"
  loadbalancer_id      = azurerm_lb.alb.id
  protocol             = var.alb_probe_protocol            # "Tcp" or "Http"
  port                 = var.alb_probe_port
  request_path         = var.alb_probe_protocol == "Http" ? var.alb_probe_request_path : null
  interval_in_seconds  = 5
  number_of_probes     = 2
}

# Load Balancing Rule (e.g., 80->80)
resource "azurerm_lb_rule" "alb_rule" {
  name                           = "${var.alb_name}-rule"
  loadbalancer_id                = azurerm_lb.alb.id
  protocol                       = var.alb_rule_protocol     # "Tcp" or "Udp"
  frontend_port                  = var.alb_rule_frontend_port
  backend_port                   = var.alb_rule_backend_port
  frontend_ip_configuration_name = var.alb_frontend_name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.alb_backend.id]
  probe_id                       = azurerm_lb_probe.alb_probe.id
  idle_timeout_in_minutes        = 4
  disable_outbound_snat          = false
}
