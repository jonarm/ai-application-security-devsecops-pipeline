output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "rag_api_workload_identity_client_id" {
  description = "Paste this value into the azure.workload.identity/client-id annotation in kubernetes/rbac.yaml."
  value       = azurerm_user_assigned_identity.rag_api_workload.client_id
}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "github_actions_client_id" {
  description = "Paste into the AZURE_CLIENT_ID GitHub Actions secret."
  value       = azurerm_user_assigned_identity.github_actions_ci.client_id
}

output "github_actions_tenant_id" {
  description = "Paste into the AZURE_TENANT_ID GitHub Actions secret."
  value       = data.azurerm_client_config.current.tenant_id
}

output "github_actions_subscription_id" {
  description = "Paste into the AZURE_SUBSCRIPTION_ID GitHub Actions secret."
  value       = data.azurerm_client_config.current.subscription_id
}