# ===============================================================================
# Variables for Fully Private AKS with Azure Monitor Workspace (Prometheus)
# ===============================================================================

variable "prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "demo-aks"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus2"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Demo"
    Project     = "AKS-Basic-Example"
    Owner       = "DevOps-Team"
    Purpose     = "Learning"
  }
}

# ===============================================================================
# Network Configuration
# ===============================================================================

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "aks_subnet_address_prefix" {
  description = "Address prefix for the AKS subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "private_endpoint_subnet_address_prefix" {
  description = "Address prefix for the private endpoints subnet"
  type        = string
  default     = "10.1.2.0/24"
}

variable "vm_subnet_address_prefix" {
  description = "Address prefix for the VM subnet"
  type        = string
  default     = "10.1.3.0/24"
}

variable "bastion_subnet_address_prefix" {
  description = "Address prefix for the Azure Bastion subnet"
  type        = string
  default     = "10.1.4.0/26"
}

# ===============================================================================
# AKS Configuration
# ===============================================================================

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.31"
}

variable "aks_sku_tier" {
  description = "SKU tier for AKS (Free, Standard, Premium)"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.aks_sku_tier)
    error_message = "AKS SKU tier must be Free, Standard, or Premium. Note: Private clusters require Standard or Premium."
  }
}

variable "node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "node_min_count" {
  description = "Minimum number of nodes in the AKS cluster"
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum number of nodes in the AKS cluster"
  type        = number
  default     = 5
}

variable "node_os_disk_size_gb" {
  description = "OS disk size in GB for AKS nodes (minimum 128 GB recommended for ama-metrics)"
  type        = number
  default     = 128
}

variable "aks_service_cidr" {
  description = "CIDR for Kubernetes services"
  type        = string
  default     = "10.2.0.0/16"
}

variable "aks_dns_service_ip" {
  description = "IP address for Kubernetes DNS service"
  type        = string
  default     = "10.2.0.10"
}

# ===============================================================================
# Monitoring Configuration
# ===============================================================================

variable "log_analytics_sku" {
  description = "SKU for Log Analytics Workspace"
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_days" {
  description = "Retention period in days for Log Analytics"
  type        = number
  default     = 30
}

variable "ampls_ingestion_access_mode" {
  description = "Network access mode for AMPLS ingestion (Open or PrivateOnly)"
  type        = string
  default     = "PrivateOnly"
}

variable "ampls_query_access_mode" {
  description = "Network access mode for AMPLS queries (Open or PrivateOnly)"
  type        = string
  default     = "PrivateOnly"
}

# ===============================================================================
# VM Configuration
# ===============================================================================

variable "vm_admin_username" {
  description = "Admin username for the Windows VM"
  type        = string
  default     = "azureuser"
}

variable "vm_admin_password" {
  description = "Admin password for the Windows VM"
  type        = string
  default     = "P@ssw0rd1234!"
  sensitive   = true
}

variable "vm_size" {
  description = "Size of the Windows VM"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "vm_os_disk_size_gb" {
  description = "OS disk size in GB for the Windows VM"
  type        = number
  default     = 128
}

# ===============================================================================
# Bastion Configuration
# ===============================================================================

variable "bastion_sku" {
  description = "SKU for Azure Bastion (Basic or Standard)"
  type        = string
  default     = "Basic"
}

variable "enable_bastion" {
  description = "Enable Azure Bastion for secure VM access (costs ~$140/month)"
  type        = bool
  default     = true
}
