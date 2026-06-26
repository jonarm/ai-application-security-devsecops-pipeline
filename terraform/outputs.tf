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