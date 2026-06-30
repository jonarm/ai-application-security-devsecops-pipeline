# container-insights-dcr.tf — Manually provisioned Data Collection Rule
# for AKS Container Insights, working around a real Terraform provider gap.
#
# Microsoft's own documentation states plainly that "Enabling managed
# identity authentication (preview) is not currently supported using
# Terraform or Azure Policy" — confirmed by a live, unresolved GitHub
# issue against the azurerm provider (hashicorp/terraform-provider-azurerm
# #23510) reporting the exact symptom hit here: msi_auth_for_monitoring_enabled
# was set to true in aks.tf, but no Data Collection Rule was ever created,
# and ContainerLogV2 never started flowing. The Azure CLI has a dedicated
# flag for this (`az aks enable-addons -a monitoring
# --enable-msi-auth-for-monitoring`) with no Terraform equivalent.
#
# This file manually provisions the DCE, DCR, and both required DCR
# associations that AKS would otherwise create automatically through that
# CLI/portal path — the community-recognized workaround for this gap.
resource "azurerm_monitor_data_collection_endpoint" "container_insights" {
  name                = "dce-${var.aks_cluster_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "Linux"
  tags                = merge(var.tags, { environment = var.environment })
}

resource "azurerm_monitor_data_collection_rule" "container_insights" {
  # Matches the naming pattern Azure itself uses for the auto-created
  # version of this resource (MSCI-<region>-<cluster-name>), for
  # consistency with what engineers familiar with the AKS portal flow
  # would expect to see.
  name                        = "MSCI-${var.aks_cluster_name}-${azurerm_resource_group.main.location}"
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  kind                        = "Linux"
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.container_insights.id

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace_id
      name                  = "ciworkspace"
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory"]
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      streams        = ["Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory"]
      extension_name = "ContainerInsights"
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Off"
          enableContainerLogV2   = true
        }
      })
    }
  }

  tags = merge(var.tags, { environment = var.environment })
}

# Required association binding the cluster's AMA agent to the Data
# Collection Endpoint — without this, the agent has no configuration
# access path to the DCE at all. The name "configurationAccessEndpoint"
# is a hard Azure requirement, not an arbitrary label — confirmed against
# Microsoft's own API documentation for this association type.
resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                         = "configurationAccessEndpoint"
  target_resource_id           = azurerm_kubernetes_cluster.main.id
  data_collection_endpoint_id  = azurerm_monitor_data_collection_endpoint.container_insights.id
}

# The actual association telling the AMA agent which DCR to follow for
# log collection — this is the link the AKS portal/CLI creates
# automatically that the Terraform oms_agent block alone does not.
resource "azurerm_monitor_data_collection_rule_association" "container_insights_dcr" {
  name                     = "send-rag-api-logs-to-law"
  target_resource_id       = azurerm_kubernetes_cluster.main.id
  data_collection_rule_id  = azurerm_monitor_data_collection_rule.container_insights.id
}