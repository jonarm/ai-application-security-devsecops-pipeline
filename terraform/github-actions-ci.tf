# github-actions-ci.tf — Workload Identity Federation for GitHub Actions CI/CD.
#
# Deliberately a SEPARATE identity from id-rag-api-workload
# (workload-identity.tf). The running application needs Key Vault Secrets
# User only; this identity needs AcrPush only. Sharing one identity across
# both would violate least privilege in both directions.
resource "azurerm_user_assigned_identity" "github_actions_ci" {
  name                = "id-github-actions-ci"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = merge(var.tags, { environment = var.environment })
}

resource "azurerm_federated_identity_credential" "github_actions_ci" {
  name                = "github-actions-main-branch"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.github_actions_ci.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"

  # EXACT, case-sensitive match required — GitHub's OIDC token's `sub`
  # claim must match this string character-for-character, or Azure AD
  # rejects the token exchange with AADSTS70021.
  subject = "repo:${var.github_repository}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "github_actions_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.github_actions_ci.principal_id
}