# kubernetes/ — AKS Workload Manifests

## Apply order

```powershell
kubectl apply -f kubernetes\pod-security.yaml
kubectl apply -f kubernetes\rbac.yaml
kubectl apply -f kubernetes\network-policy.yaml
kubectl apply -f kubernetes\deployment.yaml
```

## What's actually live vs. reference design

| Component | Status |
|---|---|
| YAML syntax | **Validated** — all four manifests parsed and checked as well-formed Kubernetes resources before first apply |
| Applied to a live AKS cluster | **Live** — deployed and confirmed running (`screenshots/aks-deployment/02`, `04`) after fixing a real CrashLoopBackOff (see below) |
| Workload Identity client-id, ACR login server | **Live** — populated from real `terraform output` values into `rbac.yaml` and `deployment.yaml` |
| Azure OpenAI / AI Search endpoint placeholders | **Not populated** — deliberately out of scope; `RAG_MOCK_MODE=true` is the only mode exercised |
| Full guardrail pipeline confirmed against the running pods | **Live** — `/healthz`, a benign `/chat` request, and a real prompt injection attempt all tested via `kubectl port-forward` against the actual AKS-hosted pods (`screenshots/aks-deployment/05-07`) |

## Issues encountered on the first real deploy

- **`readOnlyRootFilesystem: true` + MSAL token cache write** — caught
  before deploy via code review, not a real crash. `azure-identity`/MSAL
  attempts to write a token cache to the home directory on first
  credential use; under a read-only root filesystem this would crash the
  pod on first real Azure OpenAI call. Fixed by mounting an `emptyDir` at
  `/tmp` and setting `HOME=/tmp` in `deployment.yaml`.
- **PodSecurityPolicy vs. Pod Security Standards** — PSP was removed in
  Kubernetes 1.25. `pod-security.yaml` uses namespace-label-based Pod
  Security Standards instead, the current supported mechanism.
- **CrashLoopBackOff from a Docker build context bug — a real crash, not
  anticipated in advance.** Root cause was in the image build (wrong
  build context excluding sibling guardrail modules), not in any
  manifest in this folder. Confirmed via `kubectl logs` showing
  `ModuleNotFoundError: No module named 'prompt_filter'`. Full writeup in
  `app/README.md`.

## Known limitations

- **Egress NetworkPolicy allows `0.0.0.0/0:443`** rather than IP-scoped
  rules, because Azure PaaS services (OpenAI, AI Search, Key Vault, Entra
  token endpoint) don't expose stable IP ranges suitable for an `ipBlock`
  allow-list. A tighter alternative — Azure Firewall or NAT Gateway with
  FQDN-based egress filtering — would scope this further but is not
  implemented in this build.
- **No Ingress resource is included.** This repo exposes the service via
  a `ClusterIP` Service only, accessed during testing via
  `kubectl port-forward`. A production deployment would add an Ingress
  (or Azure Application Gateway Ingress Controller) in front of it.