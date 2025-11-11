# ===============================================================================
# Outputs for Fully Private AKS with Azure Monitor Workspace (Prometheus)
# ===============================================================================

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster (private)"
  value       = azurerm_kubernetes_cluster.main.private_fqdn
}

output "monitor_workspace_id" {
  description = "Resource ID of the Azure Monitor Workspace"
  value       = azurerm_monitor_workspace.main.id
}

output "monitor_workspace_query_endpoint" {
  description = "Query endpoint for the Azure Monitor Workspace"
  value       = azurerm_monitor_workspace.main.query_endpoint
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "ampls_id" {
  description = "Resource ID of the Azure Monitor Private Link Scope"
  value       = azurerm_monitor_private_link_scope.main.id
}

output "ampls_private_endpoint_ip" {
  description = "Private IP address of the AMPLS private endpoint"
  value       = azurerm_private_endpoint.ampls.private_service_connection[0].private_ip_address
}

output "amw_private_endpoint_ip" {
  description = "Private IP address of the Azure Monitor Workspace private endpoint"
  value       = azurerm_private_endpoint.amw.private_service_connection[0].private_ip_address
}

output "jumpbox_vm_name" {
  description = "Name of the Windows jumpbox VM"
  value       = azurerm_windows_virtual_machine.jumpbox.name
}

output "jumpbox_private_ip" {
  description = "Private IP address of the Windows jumpbox VM"
  value       = azurerm_windows_virtual_machine.jumpbox.private_ip_address
}

output "kubectl_config_command" {
  description = "Command to configure kubectl to access the AKS cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "bastion_connect_instructions" {
  description = "Instructions to connect to the jumpbox via Azure Bastion"
  value       = var.enable_bastion ? "Connect via Azure Portal: Navigate to the VM '${azurerm_windows_virtual_machine.jumpbox.name}' and click 'Connect' > 'Bastion'. Username: ${var.vm_admin_username}, Password: ${var.vm_admin_password}" : "Bastion is disabled. Configure alternative access method."
  sensitive   = true
}

output "azure_portal_links" {
  description = "Direct links to Azure Portal resources"
  value = {
    resource_group     = "https://portal.azure.com/#@/resource${azurerm_resource_group.main.id}"
    aks_cluster        = "https://portal.azure.com/#@/resource${azurerm_kubernetes_cluster.main.id}"
    monitor_workspace  = "https://portal.azure.com/#@/resource${azurerm_monitor_workspace.main.id}"
    log_analytics      = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}"
    ampls              = "https://portal.azure.com/#@/resource${azurerm_monitor_private_link_scope.main.id}"
  }
}

output "data_collection_rule_id" {
  description = "Resource ID of the Data Collection Rule"
  value       = azurerm_monitor_data_collection_rule.prometheus.id
}

output "data_collection_endpoint_id" {
  description = "Resource ID of the Data Collection Endpoint"
  value       = azurerm_monitor_data_collection_endpoint.prometheus.id
}

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    region                    = var.location
    aks_nodes                 = "${var.node_min_count}-${var.node_max_count}"
    kubernetes_version        = var.kubernetes_version
    private_cluster           = true
    monitoring_configured     = true
    bastion_enabled           = var.enable_bastion
    private_endpoints_created = 2
    dns_zones_created         = 7
  }
}
