terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.41.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
  backend "azurerm" {
    resource_group_name   = "rg-tfstate"
    storage_account_name  = "petffile"
    container_name        = "terraformtffile"
    key                   = "aks.terraform.tfstate"
    subscription_id       = "05276564-4a5f-40d6-b156-3ed5768e3bf3"
    tenant_id             = "8196ddea-f6c5-4044-8209-53ad1fdaebbf"
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
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "aks_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

/*# Output kubeconfig
output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}*/

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "aks_logs" {
  name                = "${var.aks_cluster_name}-logs"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}


# Current user info

# Grafana
resource "azurerm_dashboard_grafana" "aks_grafana" {
  name                  = "pe-grafana-new"
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
  name                = replace("${var.aks_cluster_name}acrpe", "-", "")
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
  name                        = replace("pe-aks-new${var.aks_cluster_name}", "-", "")
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

/*# Public IP for the Load Balancer
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

resource "time_sleep" "wait_for_rbac" {
  depends_on = [azurerm_role_assignment.aks_cluster_admin]
  create_duration = "60s" # wait 1 minute
}*/
# ----------------------------
# Kubernetes Provider
# ----------------------------
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_admin_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].cluster_ca_certificate)
}

# ----------------------------
# Namespace for ArgoCD
# ----------------------------
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

# ----------------------------
# Helm Provider
# ----------------------------
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_admin_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].cluster_ca_certificate)
  }
}

# ----------------------------
# Deploy ArgoCD via Helm
# ----------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  chart            = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false
  version          = var.argocd_chart_version

  values = [
    <<EOF
server:
  service:
    type: LoadBalancer
EOF
  ]

  depends_on = [
    kubernetes_namespace.argocd
  ]
}

output "aks_cluster_name" {
  description = "AKS Cluster Name"
  value       = azurerm_kubernetes_cluster.aks.name
}
output "kube_config" {
  description = "Kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}
output "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}
output "argocd_server_service" {
  description = "ArgoCD server LoadBalancer info"
  value       = helm_release.argocd.status
}
