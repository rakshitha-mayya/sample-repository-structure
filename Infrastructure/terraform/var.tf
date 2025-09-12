variable "clientid" {
  description = "client id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "ee06da01-52ef-42c9-8665-03fd349d4fc9"
}
 
variable "tenantid" {
  description = "tenant id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "c3c8c18c-2d1f-4023-bb9c-11a8b40799f0"
}
 
variable "secretvalue" {
  description = "secretvalue id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "Vgx8Q~88RhqDiEUdTSuTqBoMprucBN-_jVwaRbRt"
}
 
variable "subscriptionid" {
  description = "secretvalue id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "1fe9d6c6-7bd9-49ef-9ee9-04c91c284767"
}

variable "resource_group_name" {
  description = "Name of the existing Resource Group where AKS and resources will be created"
  type        = string
  default     = "rg-cp-pe-pattern"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
}

variable "aks_cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "az-pe-cluster"
}

variable "node_count" {
  description = "Number of nodes in default pool"
  type        = number
  default     = 1
}

variable "node_vm_size" {
  description = "VM size for AKS worker nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

# Tags for governance and ownership
variable "default_tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default = {
    Environment = "POC"
    Department  = "delivery"
    Owner       = "Pushpreet.Singh1@kyndryl.com"
  }
}

variable "alb_name" {
  description = "Name of the public Azure Load Balancer"
  type        = string
  default     = "pe-alb"
}

variable "alb_frontend_name" {
  description = "Frontend IP configuration name"
  type        = string
  default     = "public-frontend"
}

variable "alb_backend_pool_name" {
  description = "Backend pool name"
  type        = string
  default     = "backendpool"
}

variable "alb_rule_protocol" {
  description = "LB rule protocol"
  type        = string
  default     = "Tcp"
  validation {
    condition     = contains(["Tcp", "Udp"], var.alb_rule_protocol)
    error_message = "alb_rule_protocol must be Tcp or Udp."
  }
}

variable "alb_rule_frontend_port" {
  description = "Frontend port"
  type        = number
  default     = 80
}

variable "alb_rule_backend_port" {
  description = "Backend port"
  type        = number
  default     = 80
}

variable "alb_probe_protocol" {
  description = "Health probe protocol"
  type        = string
  default     = "Tcp"
  validation {
    condition     = contains(["Tcp", "Http"], var.alb_probe_protocol)
    error_message = "alb_probe_protocol must be Tcp or Http."
  }
}

variable "alb_probe_port" {
  description = "Health probe port"
  type        = number
  default     = 80
}

variable "alb_probe_request_path" {
  description = "HTTP probe path (used when alb_probe_protocol = Http)"
  type        = string
  default     = "/"
}

variable "enable_alb_outbound_rule" {
  description = "Create an outbound SNAT rule on the public ALB"
  type        = bool
  default     = false
}
variable "argocd_namespace" {
  description = "Namespace to deploy ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Helm chart version for ArgoCD"
  type        = string
  default     = "5.40.0"
}
