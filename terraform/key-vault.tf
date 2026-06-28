data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                      = var.key_vault_name
  location                  = azurerm_resource_group.main.location
  resource_group_name       = azurerm_resource_group.main.name
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  sku_name                  = "standard"
  enable_rbac_authorization = true
  # checkov:skip=CKV_AZURE_109: Firewall rules (network_acls) are not
  # configured — bundled with the same network-restriction gap as
  # CKV_AZURE_189 and CKV2_AZURE_32 below.
  # checkov:skip=CKV_AZURE_189: Disabling public network access requires a
  # private endpoint + VNet, which (unlike ACR's Premium-gated equivalent)
  # is achievable on Standard SKU but not yet built. Documented as a real
  # production-readiness gap, comparable in importance to AKS's
  # CKV_AZURE_117 disk encryption set decision.
  # checkov:skip=CKV2_AZURE_32: Same root cause as CKV_AZURE_189 — no
  # private endpoint/VNet provisioned yet.
  purge_protection_enabled = false
  # checkov:skip=CKV_AZURE_110: Purge protection deliberately disabled for
  # this lab/portfolio build to allow clean teardown via `terraform
  # destroy` — see terraform/README.md.
  # checkov:skip=CKV_AZURE_42: Same root cause as CKV_AZURE_110 — this
  # check also covers soft-delete recoverability, which is implied by the
  # same purge-protection tradeoff above.

  tags = merge(var.tags, { environment = var.environment })
}

resource "azurerm_role_assignment" "rag_api_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.rag_api_workload.principal_id
}