# aks.tf — Minimal AKS cluster with OIDC issuer and Workload Identity enabled.
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "contoso-rag"
  # checkov:skip=CKV_AZURE_6: API server authorized IP ranges intentionally
  # left open for this lab build.
  # checkov:skip=CKV_AZURE_115: A private cluster has no public API server
  # endpoint, which would break kubectl/az aks get-credentials from a
  # dynamic IP without adding a VPN or Azure Bastion.
  # checkov:skip=CKV_AZURE_117: Disk encryption set requires cluster
  # recreation (disk_encryption_set_id forces replacement). Deferred as
  # the top candidate for a future iteration — no extra recurring cost,
  # just real Terraform work and a destructive apply.
  # checkov:skip=CKV_AZURE_227: Host-based encryption requires registering
  # the EncryptionAtHost feature at the subscription level, not yet done.
  # checkov:skip=CKV_AZURE_141: Disabling the local admin account requires
  # Entra ID-integrated cluster RBAC to be configured first — without it,
  # this would lock out kubectl access entirely. Real lockout risk.
  # checkov:skip=CKV_AZURE_168: max_pods forces node pool recreation, and
  # is irrelevant at this lab's scale (2 replicas of one service).
  # checkov:skip=CKV_AZURE_226: Ephemeral OS disks force node pool
  # recreation and require verifying the VM SKU's local cache size first.
  # checkov:skip=CKV_AZURE_172: Does not apply — this repo deliberately
  # uses Workload Identity directly in application code
  # (app/rag-api/clients.py), not the AKS Secrets Store CSI Driver add-on.
  # checkov:skip=CKV_AZURE_232: Requires a second, dedicated system node
  # pool — doubles node cost for a 2-pod workload at this lab's scale.
  # checkov:skip=CKV_AZURE_170: The Paid SKU tier adds real recurring cost
  # (~$73/month) purely for a control-plane SLA, not justified here.

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Real fixes — both are simple, in-place fields with no recreation and
  # no added cost, addressing CKV_AZURE_116 and CKV_AZURE_171.
  azure_policy_enabled      = true
  automatic_channel_upgrade = "patch"

  default_node_pool {
    name       = "default"
    node_count = var.aks_node_count
    vm_size    = var.aks_node_vm_size

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
  }

  # Real fix addressing CKV_AZURE_4 — also closes the gap documented in
  # sentinel/README.md ("no Log Analytics workspace wired to AKS, so the
  # KQL detection rule has nothing to query"). Reuses the existing
  # Sentinel-onboarded workspace from the companion governance repo rather
  # than provisioning a redundant one.
  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  tags = merge(var.tags, { environment = var.environment })
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                             = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}