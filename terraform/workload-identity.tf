# workload-identity.tf — Azure Workload Identity Federation for the RAG API.
#
# This is the Azure-side configuration that, combined with the
# ServiceAccount annotation in kubernetes/rbac.yaml, lets the rag-api pod
# obtain Azure AD tokens without any client secret, certificate, or key
# ever existing in the cluster — see docs/architecture-overview.md's
# "Secrets" entry in the Technology stack section.
resource "azurerm_user_assigned_identity" "rag_api_workload" {
  name                = var.workload_identity_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = merge(var.tags, { environment = var.environment })
}

resource "azurerm_federated_identity_credential" "rag_api" {
  name                = "rag-api-federated-credential"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.rag_api_workload.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url

  # This subject string is the exact binding between this Azure identity
  # and a specific Kubernetes ServiceAccount. It must match
  # system:serviceaccount:<namespace>:<service-account-name> EXACTLY — a
  # mismatch here is a common real-world failure mode: the federated
  # credential is created successfully, but token exchange silently fails
  # at runtime because the subject doesn't match what AKS presents.
  subject = "system:serviceaccount:${var.rag_api_namespace}:${var.rag_api_service_account}"
}