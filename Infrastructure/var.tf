variable "clientid" {
  description = "client id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "657f814b-9667-4e5a-a3d4-3f264ff38bb4"
}

variable "tenantid" {
  description = "tenant id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "8196ddea-f6c5-4044-8209-53ad1fdaebbf"
}

variable "secretvalue" {
  description = "secretvalue id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "7Rl8Q~EN-qc.DDOlXI6KrkJkpEhfGVa392YsGcwG"
}

variable "subscriptionid" {
  description = "secretvalue id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "05276564-4a5f-40d6-b156-3ed5768e3bf3"
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
