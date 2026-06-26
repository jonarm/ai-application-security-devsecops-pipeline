# kubernetes/ — AKS Workload Manifests

## Apply order

These manifests have a dependency order — `pod-security.yaml` creates the
namespace itself; the others assume it already exists.

```powershell
kubectl apply -f kubernetes\pod-security.yaml
kubectl apply -f kubernetes\rbac.yaml
kubectl apply -f kubernetes\network-policy.yaml
kubectl apply -f kubernetes\deployment.yaml
```

## What's actually live vs. reference design

| Component | Status |
|---|---|
| YAML syntax | **Validated** — all four manifests parsed and checked as well-formed Kubernetes resources |
| Applied to a live AKS cluster | **Reference design** — AKS has not yet been provisioned (see `terraform/`); these manifests have not yet been run against a real API server |
| Workload Identity client-id / image registry / Azure endpoint placeholders | **Not yet populated** — `<MANAGED_IDENTITY_CLIENT_ID>`, `<ACR_NAME>`, and the four `<SET_VIA_TERRAFORM_OUTPUT>` values in `deployment.yaml` are filled in from Terraform outputs once `terraform/` is applied |

## Issues caught before first deploy

- **`readOnlyRootFilesystem: true` + MSAL token cache write.** `azure-identity`
  (used in `app/rag-api/clients.py`) attempts to write a token cache to the
  home directory on first credential use. Under a read-only root
  filesystem, this would crash the pod on the first real (non-mock) Azure
  OpenAI call. Fixed by mounting an `emptyDir` at `/tmp` and setting
  `HOME=/tmp` — see the inline comments in `deployment.yaml`.
- **PodSecurityPolicy vs. Pod Security Standards.** PSP was removed in
  Kubernetes 1.25. `pod-security.yaml` uses namespace-label-based Pod
  Security Standards instead, which is the current supported mechanism.

## Known limitations

- **Egress NetworkPolicy allows `0.0.0.0/0:443`** rather than IP-scoped
  rules, because Azure PaaS services (OpenAI, AI Search, Key Vault, Entra
  token endpoint) don't expose stable IP ranges suitable for an `ipBlock`
  allow-list. A tighter alternative — Azure Firewall or NAT Gateway with
  FQDN-based egress filtering — would scope this further but is not
  implemented in this build; noted here as a deliberate scope decision,
  not an oversight.
- **No Ingress resource is included.** This repo exposes the service via a
  `ClusterIP` Service only; a production deployment would add an Ingress
  (or Azure Application Gateway Ingress Controller) in front of it, which
  is out of scope for this single-service security build.