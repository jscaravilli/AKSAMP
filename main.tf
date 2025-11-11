# ===============================================================================
# Fully Private AKS with Azure Monitor Workspace (Prometheus)
# ===============================================================================

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "azurerm" {
  features {}
}

# ===============================================================================
# Resource Group
# ===============================================================================

resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}

# ===============================================================================
# Virtual Network
# ===============================================================================

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space

  tags = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "${var.prefix}-aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_address_prefix]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "${var.prefix}-pe-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_endpoint_subnet_address_prefix]
}

resource "azurerm_subnet" "vm" {
  name                 = "${var.prefix}-vm-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.vm_subnet_address_prefix]
}

# ===============================================================================
# Log Analytics Workspace
# ===============================================================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.prefix}-law"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days

  tags = var.tags
}

# ===============================================================================
# Azure Monitor Private Link Scope (AMPLS)
# ===============================================================================

resource "azurerm_monitor_private_link_scope" "main" {
  name                = "${var.prefix}-ampls"
  resource_group_name = azurerm_resource_group.main.name

  ingestion_access_mode = var.ampls_ingestion_access_mode
  query_access_mode     = var.ampls_query_access_mode

  tags = var.tags
}

resource "azurerm_monitor_private_link_scoped_service" "law" {
  name                = "${var.prefix}-ampls-law"
  resource_group_name = azurerm_resource_group.main.name
  scope_name          = azurerm_monitor_private_link_scope.main.name
  linked_resource_id  = azurerm_log_analytics_workspace.main.id
}

resource "azurerm_monitor_private_link_scoped_service" "dce" {
  name                = "${var.prefix}-ampls-dce"
  resource_group_name = azurerm_resource_group.main.name
  scope_name          = azurerm_monitor_private_link_scope.main.name
  linked_resource_id  = azurerm_monitor_data_collection_endpoint.prometheus.id
}

# ===============================================================================
# Azure Monitor Workspace
# ===============================================================================

resource "azurerm_monitor_workspace" "main" {
  name                          = "${var.prefix}-amw"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  public_network_access_enabled = false

  tags = var.tags
}

# ===============================================================================
# Data Collection Endpoint for Prometheus
# ===============================================================================

resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  name                = "${var.prefix}-prometheus-dce"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "Linux"
  tags                = var.tags
}

# ===============================================================================
# Data Collection Rule for Prometheus
# ===============================================================================

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                        = "${var.prefix}-prometheus-dcr"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus.id
  kind                        = "Linux"
  description                 = "DCR for Azure Monitor Metrics Profile (Managed Prometheus)"

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.main.id
      name               = "MonitoringAccount1"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "PrometheusDataSource"
    }
  }

  tags = azurerm_resource_group.main.tags
}

# ===============================================================================
# AKS Cluster
# ===============================================================================

resource "azurerm_kubernetes_cluster" "main" {
  name                    = "${var.prefix}-aks"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  dns_prefix              = "${var.prefix}-aks"
  kubernetes_version      = var.kubernetes_version
  sku_tier                = var.aks_sku_tier
  private_cluster_enabled = true

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    enable_auto_scaling         = true
    min_count                   = var.node_min_count
    max_count                   = var.node_max_count
    vnet_subnet_id              = azurerm_subnet.aks.id
    os_disk_size_gb             = var.node_os_disk_size_gb
    type                        = "VirtualMachineScaleSets"
    temporary_name_for_rotation = "systemtmp"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = var.aks_service_cidr
    dns_service_ip = var.aks_dns_service_ip
  }

  monitor_metrics {
    annotations_allowed = null
    labels_allowed      = null
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.main.id
    msi_auth_for_monitoring_enabled = true
  }

  tags = var.tags
}

# ===============================================================================
# Data Collection Rule Association - Links AKS to Prometheus
# ===============================================================================

# Association for the Data Collection Rule (defines WHAT to collect)
resource "azurerm_monitor_data_collection_rule_association" "prometheus_dcr" {
  name                    = "${var.prefix}-prometheus-dcra"
  target_resource_id      = azurerm_kubernetes_cluster.main.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus.id
  description             = "Association of data collection rule. Deleting this will break Prometheus data collection."
}

# Association for the Data Collection Endpoint (defines HOW to access config via private link)
# NOTE: The name MUST be "configurationAccessEndpoint" - this is a required convention
resource "azurerm_monitor_data_collection_rule_association" "prometheus_dce" {
  name                        = "configurationAccessEndpoint"
  target_resource_id          = azurerm_kubernetes_cluster.main.id
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus.id
  description                 = "Association of data collection endpoint for private link access."
}

# ===============================================================================
# Private DNS Zone for AKS
# ===============================================================================

resource "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = azurerm_resource_group.main.name

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  name                  = "${var.prefix}-aks-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = azurerm_virtual_network.main.id

  tags = azurerm_resource_group.main.tags
}

# ===============================================================================
# Private Endpoint for AMPLS
# ===============================================================================

resource "azurerm_private_endpoint" "ampls" {
  name                = "${var.prefix}-ampls-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.prefix}-ampls-psc"
    private_connection_resource_id = azurerm_monitor_private_link_scope.main.id
    is_manual_connection           = false
    subresource_names              = ["azuremonitor"]
  }

  private_dns_zone_group {
    name                 = "ampls-dns-zone-group"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.monitor.id,
      azurerm_private_dns_zone.oms.id,
      azurerm_private_dns_zone.ods.id,
      azurerm_private_dns_zone.agentsvc.id,
      azurerm_private_dns_zone.blob.id
    ]
  }

  # Wait for Bastion (if enabled) to complete to avoid network operation conflicts
  depends_on = [azurerm_bastion_host.main]

  tags = var.tags
}

# ===============================================================================
# Wait between private endpoints to avoid Azure API issues
# ===============================================================================

resource "time_sleep" "wait_between_endpoints" {
  depends_on = [azurerm_private_endpoint.ampls]

  create_duration = "30s"
}

# ===============================================================================
# Private Endpoint for Azure Monitor Workspace (Prometheus)
# ===============================================================================

resource "azurerm_private_endpoint" "amw" {
  name                = "${var.prefix}-amw-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.prefix}-amw-psc"
    private_connection_resource_id = azurerm_monitor_workspace.main.id
    is_manual_connection           = false
    subresource_names              = ["prometheusMetrics"]
  }

  private_dns_zone_group {
    name                 = "amw-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.prometheus.id]
  }

  # Serialize private endpoint creation with delay to avoid Azure network conflicts
  depends_on = [time_sleep.wait_between_endpoints]

  tags = azurerm_resource_group.main.tags
}

# ===============================================================================
# Private DNS Zones for Azure Monitor
# ===============================================================================

resource "azurerm_private_dns_zone" "monitor" {
  name                = "privatelink.monitor.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_private_dns_zone" "oms" {
  name                = "privatelink.oms.opinsights.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_private_dns_zone" "ods" {
  name                = "privatelink.ods.opinsights.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_private_dns_zone" "agentsvc" {
  name                = "privatelink.agentsvc.azure-automation.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_private_dns_zone" "prometheus" {
  name                = "privatelink.${var.location}.prometheus.monitor.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = azurerm_resource_group.main.tags
}

# Link DNS zones to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "monitor" {
  name                  = "${var.prefix}-monitor-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.monitor.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = azurerm_resource_group.main.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "oms" {
  name                  = "${var.prefix}-oms-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.oms.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = azurerm_resource_group.main.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "ods" {
  name                  = "${var.prefix}-ods-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.ods.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = azurerm_resource_group.main.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "agentsvc" {
  name                  = "${var.prefix}-agentsvc-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.agentsvc.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = azurerm_resource_group.main.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "${var.prefix}-blob-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = azurerm_resource_group.main.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "prometheus" {
  name                  = "${var.prefix}-prometheus-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.prometheus.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags = azurerm_resource_group.main.tags
}

# ===============================================================================
# Windows Jump Box VM
# ===============================================================================

resource "azurerm_network_interface" "vm" {
  name                = "${var.prefix}-vm-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_windows_virtual_machine" "jumpbox" {
  name                = "${var.prefix}-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.vm_admin_username
  admin_password      = var.vm_admin_password

  network_interface_ids = [
    azurerm_network_interface.vm.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.vm_os_disk_size_gb
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  tags = var.tags
}

# Install Azure CLI, kubectl, and other tools via Custom Script Extension
resource "azurerm_virtual_machine_extension" "vm_setup" {
  name                 = "setup-tools"
  virtual_machine_id   = azurerm_windows_virtual_machine.jumpbox.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = <<-EOT
      powershell -ExecutionPolicy Unrestricted -Command "
        # Install Chocolatey
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        
        # Install tools
        choco install azure-cli -y
        choco install kubernetes-cli -y
        choco install git -y
        
        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
        
        Write-Host 'Tools installed successfully'
      "
    EOT
  })

  tags = var.tags
}

# ===============================================================================
# Azure Bastion (Optional - ~$140/month)
# ===============================================================================

# Bastion for secure RDP access (can be disabled via enable_bastion variable)
resource "azurerm_subnet" "bastion" {
  count                = var.enable_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.bastion_subnet_address_prefix]
}

resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                = "${var.prefix}-bastion-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

resource "azurerm_bastion_host" "main" {
  count               = var.enable_bastion ? 1 : 0
  name                = "${var.prefix}-bastion"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.bastion_sku

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  tags = var.tags
}

