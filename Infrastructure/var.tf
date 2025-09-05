# Service Principal Name ( App Name): 	app-cp-pe-pattern-poc
# Application (client) ID :		de070d2e-ab18-41c5-bfa6-7cfb61136711
# Object ID :	c496efd8-d632-4e29-a9a9-ee891efccaac
# Directory (tenant) ID :		99d624b9-55f3-4984-bb9a-28d58385162d
# Secret Name : 	skt-app-cp-pe-pattern-poc
# Secret ID : 	d779d7cd-c0a3-4ed9-b33d-935e644e73db
# Secret Value : 	h.l8Q~npXw6iK42Bi1aQwzadnX.mdYERr~yYhcm4


variable "clientid" {
  description = "client id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "de070d2e-ab18-41c5-bfa6-7cfb61136711"
}

variable "tenantid" {
  description = "tenant id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "99d624b9-55f3-4984-bb9a-28d58385162d"
}

variable "secretvalue" {
  description = "secretvalue id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "h.l8Q~npXw6iK42Bi1aQwzadnX.mdYERr~yYhcm4"
}

variable "subscriptionid" {
  description = "secretvalue id azure"
  type        = string #map list of string
  #in string variable we can define only one single value
  default = "343c17eb-34b6-4481-92a2-a0a5a04bdd88"
}

variable "resource_group_name" {
  description = "Name of the existing Resource Group where AKS and resources will be created"
  type        = string
  default     = "rg-cp-pe-pattern-poc4"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
}

variable "aks_cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "az-pe-cluster-new"
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
