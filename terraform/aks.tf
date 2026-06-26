# aks.tf — Minimal AKS cluster with OIDC issuer and Workload Identity enabled.
#
# oidc_issuer_enabled and workload_identity_enabled are BOTH required for
# the federated identity credential in workload-identity.tf to function —
# without oidc_issuer_enabled, there is no OIDC issuer URL for Azure AD to
# trust, and the federated credential creation will fail referencing a
# null issuer URL.
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "contoso-rag"
  # checkov:skip=CKV_AZURE_6: API server authorized IP ranges intentionally
  # left open for this lab build — this cluster is accessed from a
  # residential/dynamic IP during development, and a static allow-list
  # would need constant updating. Noted as a production-readiness gap,
  # not an oversight — see terraform/README.md.

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "default"
    node_count = var.aks_node_count
    vm_size    = var.aks_node_vm_size
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    # network_policy = "azure" is required for the NetworkPolicy resources
    # in kubernetes/network-policy.yaml to actually be enforced — without
    # a network policy engine enabled at the cluster level, those
    # NetworkPolicy manifests would apply with no effect.
  }

  tags = merge(var.tags, { environment = var.environment })
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  # Grants the AKS cluster's kubelet identity permission to pull images
  # from the ACR created in acr.tf — without this, image pulls in
  # kubernetes/deployment.yaml fail with an authorization error at pod
  # scheduling time, not at apply time, which makes it an easy thing to
  # miss until first deploy.
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                             = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}