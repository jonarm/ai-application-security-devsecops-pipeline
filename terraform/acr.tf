resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
  # admin_enabled = false is deliberate — this repo's pattern is identity-
  # based access throughout (Workload Identity, AcrPush/AcrPull role
  # assignments), not shared admin credentials.

  # checkov:skip=CKV_AZURE_165: Geo-replication requires Premium SKU and
  # is irrelevant for a single-region lab with no multi-region deployment.
  # checkov:skip=CKV_AZURE_164: Content trust (image signing) requires
  # Premium SKU. Also worth noting Docker Content Trust itself is being
  # migrated to the Notary Project by Microsoft's own 2028 deprecation
  # timeline, independent of this repo's scope decision.
  # checkov:skip=CKV_AZURE_237: Dedicated data endpoints require Premium SKU.
  # checkov:skip=CKV_AZURE_167: Untagged-manifest retention policy requires
  # Premium SKU; low stakes with a single image in this registry.
  # checkov:skip=CKV_AZURE_139: Disabling public network access requires a
  # Premium-tier private endpoint, which would break both the GitHub
  # Actions OIDC push (build-and-push.yml, runner has no VNet peering) and
  # local docker push from a development machine — both currently working.
  # checkov:skip=CKV_AZURE_233: Zone redundancy as an explicit Terraform
  # attribute is historically Premium-gated; some current Microsoft docs
  # suggest certain regions default to zone redundancy regardless of SKU,
  # but this is not asserted with confidence here — documented as an
  # honest ambiguity, not a resolved finding.
  # checkov:skip=CKV_AZURE_166: The quarantine/scan/verify pattern relies
  # on ACR Tasks, which this subscription has already been confirmed to
  # block outright (TasksOperationsNotAllowed — see terraform/README.md's
  # "Issues encountered and resolved" section for the real error).
  # checkov:skip=CKV_AZURE_163: Trivy already provides container
  # vulnerability scanning in this repo's CI/CD (.github/workflows/trivy.yml).
  # Microsoft Defender for Containers would add registry-level continuous
  # scanning but introduces real recurring cost beyond this lab's scope.
  tags = merge(var.tags, { environment = var.environment })
}