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
  # left open for this lab build — accessed from a residential/dynamic IP
  # during development.
  # checkov:skip=CKV_AZURE_115: A private cluster has no public API server
  # endpoint, which would break kubectl/az aks get-credentials from a
  # dynamic IP without adding a VPN or Azure Bastion — same root cause as
  # the CKV_AZURE_6 decision above.

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "default"
    node_count = var.aks_node_count
    vm_size    = var.aks_node_vm_size

    # Azure sets these defaults automatically on node pool creation, even
    # though they were never declared here. Without explicitly matching
    # them, every subsequent `terraform plan` shows drift and attempts to
    # null them out on `apply` — which is harmless when the cluster is
    # running, but fails outright when it's stopped, since AKS disallows
    # any node pool modification on a stopped cluster. Declaring the exact
    # values Azure already set eliminates the diff entirely.
    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
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