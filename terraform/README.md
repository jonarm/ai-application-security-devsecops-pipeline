# terraform/ — Infrastructure as Code

## Scope

This configuration provisions: an AKS cluster (OIDC issuer + Workload
Identity enabled, Azure Policy add-on, automatic patch upgrades, Container
Insights wired to an existing Log Analytics workspace via a manually
provisioned DCR/DCE — see "Issues encountered" for why this is a separate
file rather than implicit in the cluster config), an Azure Container
Registry, an Azure Key Vault, and two separate Workload Identity Federation
setups — one for the running application (`workload-identity.tf`), one for
GitHub Actions CI/CD (`github-actions-ci.tf`).

**Azure OpenAI and Azure AI Search are not provisioned here** — both
require quota/access approval and incur ongoing cost independent of whether
the security architecture works, so they're treated as a separate decision.
See `app/README.md` for how `clients.py` is written against those SDKs in
mock mode regardless.

## Files

| File | Purpose |
|---|---|
| `providers.tf` | Provider version constraints |
| `variables.tf` | All input variables with descriptions |
| `resource_group.tf` | Resource group |
| `aks.tf` | AKS cluster with OIDC, Workload Identity, Azure Policy, auto-upgrade, and `oms_agent` block |
| `acr.tf` | Azure Container Registry (Basic SKU) |
| `key-vault.tf` | Azure Key Vault (Standard SKU, RBAC authorization) |
| `workload-identity.tf` | App workload identity + AKS federated credential |
| `github-actions-ci.tf` | Separate CI/CD identity + GitHub OIDC federated credential |
| `container-insights-dcr.tf` | DCE, DCR, and associations for Container Insights — manual workaround for a real Terraform provider gap |
| `outputs.tf` | Outputs consumed by `kubernetes/` manifests and GitHub secrets |

## Prerequisites

- Azure subscription
- Terraform >= 1.5
- Azure CLI, authenticated (`az login`)

## Apply order

```powershell
cd terraform
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — acr_name and key_vault_name must be globally
# unique across all of Azure. github_repository must exactly match your
# real repo (case-sensitive — this is a trust boundary, not a label).
# log_analytics_workspace_id must point to a real, existing Log Analytics
# workspace.

terraform init
terraform plan
terraform apply
```

Outputs that feed into other parts of this repo:

| Terraform output | Goes into |
|---|---|
| `rag_api_workload_identity_client_id` | `azure.workload.identity/client-id` annotation in `kubernetes/rbac.yaml` |
| `acr_login_server` | `image:` field in `kubernetes/deployment.yaml` |
| `github_actions_client_id` | GitHub repo secret `AZURE_CLIENT_ID` |
| `github_actions_tenant_id` | GitHub repo secret `AZURE_TENANT_ID` |
| `github_actions_subscription_id` | GitHub repo secret `AZURE_SUBSCRIPTION_ID` |

Populating `kubernetes/rbac.yaml` and `deployment.yaml` with the real
output values is a manual step — documented here rather than automated.

## What's actually live vs. reference design

| Component | Status |
|---|---|
| HCL syntax | **Validated** — all `.tf` files parsed cleanly with an offline HCL2 parser before each commit, after every edit |
| Resource group, AKS, ACR, Key Vault | **Live** — all provisioned successfully, confirmed via `terraform output` and direct `az` queries |
| App Workload Identity (`id-rag-api-workload`) | **Live** — confirmed via the `AZURE_CLIENT_ID` env var injected correctly into the running AKS pod (visible in `kubectl describe pod`) |
| GitHub Actions OIDC identity (`id-github-actions-ci`) | **Live** — confirmed via a real successful `build-and-push.yml` run authenticating to Azure with no stored credentials |
| AKS Container Insights + DCR/DCE | **Live, confirmed** — `container-insights-dcr.tf` provisioned the DCE, DCR, and both associations; 413 real `ContainerLogV2` rows confirmed in `law-ai-governance-sentinel` for `PodNamespace == "contoso-rag"`. See `screenshots/sentinel-alerts/` and "Issues encountered" for the full story |
| Key Vault secrets | **None populated** — the vault and its RBAC role assignment exist, but no secrets are stored since Azure OpenAI/AI Search are out of scope |

## Issues encountered and resolved

### 1. `Standard_B2s` rejected with a subscription/region SKU restriction

First `terraform apply` failed creating the AKS cluster with: *"The VM
size of Standard_B2s is not allowed in your subscription in location
'eastus'"* — followed by an allow-list containing no B-series VMs at all.
`eastus` is capacity-constrained and this subscription is restricted to a
curated SKU list there. Resolved by switching to `Standard_D2s_v7`,
confirmed available directly from the error's own allow-list rather than
guessed. Resource group, Key Vault, ACR, the workload identity, and the
Key Vault role assignment all succeeded on the first apply — only the AKS
cluster (and its two dependents) needed a retry.

### 2. AKS auto-populates `upgrade_settings` defaults causing persistent drift

AKS silently sets `upgrade_settings` (`max_surge: 10%`,
`drain_timeout_in_minutes: 0`, `node_soak_duration_in_minutes: 0`) on node
pool creation — never declared in `aks.tf`. Every subsequent `plan` showed
these as drift. This became a blocking error once combined with `az aks
stop`, since AKS disallows node pool modifications on a stopped cluster.
Fixed by explicitly declaring the exact values Azure had already set,
eliminating the diff permanently.

### 3. A hand-edit introduced an unclosed brace in `aks.tf`

Adding the `upgrade_settings` block manually introduced one missing closing
brace — swallowing `identity {}`, `network_profile {}`, and `tags` inside
`default_node_pool {}`. Caught immediately by `terraform output` failing to
parse the file; fixed by adding the missing brace. All Terraform files in
this repo are now validated with an offline HCL2 parser before any commit,
preventing a recurrence.

### 4. ACR Tasks blocked on this subscription

`az acr build` (`TasksOperationsNotAllowed`) is blocked for subscriptions
funded by free trial credits. This shaped two decisions: image builds use
local `docker build` + `docker push` instead (and `build-and-push.yml` in
CI), and the `CKV_AZURE_166` Checkov check (container image quarantine via
ACR Tasks) carries a `#checkov:skip` annotation with this exact
justification rather than failing the pipeline.

### 5. Checkov surfaced 36 total checks — 5 fixed for real, the rest skipped with justification

First real Checkov run found checks beyond the two anticipated. Triaged
individually — every skip carries an inline `#checkov:skip` comment in the
relevant `.tf` file:

| Finding | Decision | Reason |
|---|---|---|
| `CKV_AZURE_4` (AKS → Log Analytics) | **Fixed** | `oms_agent` block added; see issue #6 below for the full DCR story |
| `CKV_AZURE_116` (Azure Policy add-on) | **Fixed** | Simple boolean, in-place, no cost |
| `CKV_AZURE_171` (upgrade channel) | **Fixed** | Simple string field, in-place, no cost |
| `CKV_AZURE_115` (AKS private cluster) | Skipped | Would break `kubectl`/`az aks get-credentials` from a dynamic IP |
| `CKV_AZURE_117` (disk encryption set) | Skipped, deferred | Forces cluster recreation; the top candidate for a future iteration |
| `CKV_AZURE_141` (disable local admin) | Skipped | Requires Entra ID-integrated RBAC first — lockout risk without it |
| `CKV_AZURE_168` (min 50 pods/node) | Skipped | Forces node pool recreation; irrelevant at this lab's scale |
| `CKV_AZURE_170` (Paid SKU tier) | Skipped | ~$73/month for a control-plane SLA not justified here |
| `CKV_AZURE_172` (Secrets Store CSI) | Skipped | Doesn't apply — this repo uses Workload Identity directly, not the CSI driver |
| `CKV_AZURE_226` (ephemeral OS disks) | Skipped | Forces node pool recreation; requires VM SKU cache-size verification first |
| `CKV_AZURE_227` (encrypt temp disks) | Skipped | Requires `EncryptionAtHost` subscription feature, not yet registered |
| `CKV_AZURE_232` (system node pool) | Skipped | Needs a second dedicated node pool — doubles node cost for 2 pods |
| `CKV_AZURE_163` (Defender for Containers) | Skipped | Trivy already provides CVE scanning in CI; Defender adds cost |
| `CKV_AZURE_164` (content trust) | Skipped | Requires ACR Premium SKU |
| `CKV_AZURE_165` (geo-replication) | Skipped | Requires ACR Premium SKU; irrelevant for single-region lab |
| `CKV_AZURE_166` (quarantine/scan) | Skipped | Relies on ACR Tasks — blocked by subscription restriction (issue #4 above) |
| `CKV_AZURE_167` (retention policy) | Skipped | Requires ACR Premium SKU |
| `CKV_AZURE_233` (zone redundancy) | Skipped | Premium-gated as an explicit Terraform attribute |
| `CKV_AZURE_237` (dedicated endpoints) | Skipped | Requires ACR Premium SKU |
| `CKV_AZURE_139` (disable public ACR networking) | Skipped | Requires Premium private endpoint; would break CI push from GitHub runners |
| `CKV_AZURE_42` (Key Vault recoverability) | Skipped | Same root cause as `CKV_AZURE_110` |
| `CKV_AZURE_109` (Key Vault firewall) | Skipped, deferred | Achievable on Standard SKU but needs VNet/private endpoint not yet built |
| `CKV_AZURE_110` (Key Vault purge protection) | Skipped | Deliberately disabled for clean `terraform destroy` in lab context |
| `CKV_AZURE_189` (disable public Key Vault networking) | Skipped, deferred | Same as `CKV_AZURE_109` — documented production-readiness gap |
| `CKV2_AZURE_32` (Key Vault private endpoint) | Skipped, deferred | Same as `CKV_AZURE_109` |
| `CKV_AZURE_6` (AKS API server IP ranges) | Skipped | Accessed from residential/dynamic IP during development |

Final tally: **13 passed, 0 failed, 23 skipped** — verified by counting
23 `#checkov:skip` annotations across `acr.tf`, `aks.tf`, and
`key-vault.tf`, exactly matching the 23 Checkov reported.

### 6. `oms_agent` block does not auto-provision a Data Collection Rule via Terraform

This is the most nuanced issue in this repo's Terraform history — worth
documenting in full.

**What was expected:** setting `oms_agent { log_analytics_workspace_id = ...
msi_auth_for_monitoring_enabled = true }` in `azurerm_kubernetes_cluster`
would provision a DCR automatically, as it does via the Azure CLI
(`az aks enable-addons -a monitoring --enable-msi-auth-for-monitoring`).

**What actually happened:** `az aks show` confirmed
`addonProfiles.omsagent.enabled: true`, but `ContainerLogV2` showed zero
rows after 15+ minutes. The `ama-logs` DaemonSet (AKS's current monitoring
agent, renamed from `omsagent`) was running healthy on both nodes. But
`az monitor data-collection rule list` against both resource groups
returned empty — no DCR existed anywhere.

**Root cause:** Microsoft's own documentation states plainly that "Enabling
managed identity authentication is not currently supported using Terraform
or Azure Policy." There is a live, unresolved GitHub issue against the
`azurerm` provider confirming that `msi_auth_for_monitoring_enabled = true`
in Terraform does not trigger automatic DCR creation — unlike the
equivalent Azure CLI or portal path.

**Fix:** `container-insights-dcr.tf` manually provisions the four resources
the AKS monitoring extension would otherwise create automatically: a Data
Collection Endpoint, a Data Collection Rule with the
`Microsoft-ContainerLogV2` stream configured, and both required
associations (one binding the cluster to the DCE via the
`configurationAccessEndpoint` association name — a hard Azure requirement,
not an arbitrary label — and one binding the cluster to the DCR itself).

**Confirmation:** 413 real `ContainerLogV2` rows returned for
`PodNamespace == "contoso-rag"` after apply. Blocked prompt injection
attempts logged from the live AKS service are visible in the workspace
and queryable by `sentinel/prompt-injection-detection.kql`.

## Known limitations / deferred work

- **`CKV_AZURE_117` (AKS disk encryption set)** — free to add, but
  `disk_encryption_set_id` forces cluster recreation. The top candidate
  for a future iteration.
- **Key Vault network restrictions** (`CKV_AZURE_109`, `CKV_AZURE_189`,
  `CKV2_AZURE_32`) — achievable on Standard SKU via a private endpoint +
  VNet, but not yet built. A genuine production-readiness gap.
- **`msi_auth_for_monitoring_enabled = true` in `aks.tf` is now
  superseded** by `container-insights-dcr.tf`, but deliberately left in
  place as a documented artifact of this investigation — removing it would
  silently erase the evidence that the root cause was a provider gap, not
  a config omission.