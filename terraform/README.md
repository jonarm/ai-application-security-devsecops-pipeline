# terraform/ — Infrastructure as Code

## Scope

This configuration provisions exactly three things, by deliberate scope
decision: an AKS cluster (with OIDC issuer + Workload Identity enabled),
an Azure Container Registry, and an Azure Key Vault — plus the Workload
Identity Federation wiring that connects the `rag-api-sa` Kubernetes
ServiceAccount (`kubernetes/rbac.yaml`) to a real Azure identity with
scoped Key Vault access.

**Azure OpenAI and Azure AI Search are not provisioned here.** Both require
quota/access approval and incur ongoing cost independent of whether the
security architecture works, so they're treated as a separate decision —
see `app/README.md` for how `clients.py` is written against those SDKs in
mock mode regardless.

## Prerequisites

- Azure subscription
- Terraform >= 1.5
- Azure CLI, authenticated (`az login`)

## Apply order

```powershell
cd terraform
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — acr_name and key_vault_name must be globally
# unique across all of Azure, not just this subscription.

terraform init
terraform plan
terraform apply
```

After apply succeeds, two outputs feed directly back into the
`kubernetes/` manifests:

| Terraform output | Goes into |
|---|---|
| `rag_api_workload_identity_client_id` | `azure.workload.identity/client-id` annotation in `kubernetes/rbac.yaml` |
| `acr_login_server` | `image:` field in `kubernetes/deployment.yaml` (replace `<ACR_NAME>.azurecr.io`) |

This substitution is currently a manual step, documented here rather than
automated — consistent with this repo series' preference for explicit,
auditable steps over hidden automation magic.

## What's actually live vs. reference design

| Component | Status |
|---|---|
| HCL syntax | **Validated** — all `.tf` files parsed cleanly with an offline HCL2 parser |
| Applied to a real Azure subscription | **Reference design** — not yet run; no `terraform apply` has been executed against live Azure resources at the time of writing |
| Key Vault secrets | **None populated** — the vault and its RBAC role assignment exist in this config, but no secrets are stored yet since Azure OpenAI / AI Search (the things that would need secret-stored connection info) are out of scope here |

## Anticipated issues (flagged in advance, not yet observed)

These are called out because they're easy to hit on first real apply, not
because they've happened yet — that distinction matters for the "what's
actually live" standard this repo series holds itself to:

- **Globally unique name collisions.** `acr_name` and `key_vault_name`
  must be unique across *all* of Azure, not just this subscription. The
  `XXXX` suffixes in `terraform.tfvars.example` are a placeholder reminder,
  not a real uniqueness guarantee.
- **Federated credential `subject` mismatch.** If `kubernetes/rbac.yaml`'s
  ServiceAccount name or namespace ever changes without updating
  `rag_api_namespace` / `rag_api_service_account` in `terraform.tfvars`,
  the federated credential becomes silently useless — Azure AD will
  reject the token exchange at runtime with no apply-time warning.
- **AKS `network_policy = "azure"` is required**, not optional, for the
  NetworkPolicy manifests in `kubernetes/` to actually be enforced. Easy
  to deploy both successfully and assume they're working when they
  silently aren't.