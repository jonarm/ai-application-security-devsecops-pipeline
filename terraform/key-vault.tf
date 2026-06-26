data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                      = var.key_vault_name
  location                  = azurerm_resource_group.main.location
  resource_group_name       = azurerm_resource_group.main.name
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  sku_name                  = "standard"
  enable_rbac_authorization = true
  # RBAC authorization (not legacy access policies) is used so Key Vault
  # access is granted via the azurerm_role_assignment resources below,
  # consistent with the identity-based access pattern used for ACR.
  purge_protection_enabled = false
  # purge_protection disabled deliberately for this lab/portfolio build —
  # it would otherwise block clean teardown via `terraform destroy`.
  # Documented here so this isn't mistaken for an oversight in a
  # production-readiness review.

  tags = merge(var.tags, { environment = var.environment })
}

resource "azurerm_role_assignment" "rag_api_kv_secrets_user" {
  # Grants the workload identity (defined in workload-identity.tf)
  # read-only access to secrets in this vault. This is the Azure-side half
  # of the Workload Identity pattern — the Kubernetes-side half is the
  # ServiceAccount annotation in kubernetes/rbac.yaml.
  #
  # No secrets are actually populated in this vault yet — see
  # terraform/README.md for why, and what would change that.
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.rag_api_workload.principal_id
}