# Framework Mapping — Azure Cloud Adoption Framework (CAF)

## Why CAF, and why only CAF

This program maps its controls to a single framework rather than three, by deliberate
scope decision — see "Scope boundaries" in
[`docs/architecture-overview.md`](./architecture-overview.md). Azure CAF is the right fit
here because every control in this repo runs on Azure (AKS, Key Vault, Azure OpenAI,
Sentinel), and CAF is the framework Microsoft itself uses to organize exactly this kind of
build-and-operate guidance. The companion
[`erp-identity-security-reference-architecture`](https://github.com/jonarm/erp-identity-security-reference-architecture)
repo already covers ACSC Essential Eight, VPDSF, NIST 800-207, and ISO 27001 in depth —
duplicating that mapping here would add volume without adding signal.

## CAF structure (current, as of this build)

CAF organizes Azure guidance into seven methodologies. Four are **foundational** and
sequential (Strategy, Plan, Ready, Adopt) — they apply to an organization's broader cloud
journey and are largely out of scope for a single-service security build like this one.
Three are **operational** and run continuously once a workload exists — **Govern**,
**Secure**, and **Manage** — and these are where this repo's evidence concentrates.

| Methodology | Type | Relevance to this program |
|---|---|---|
| Strategy | Foundational | Out of scope — business justification for cloud adoption, not modelled here |
| Plan | Foundational | Out of scope — organizational adoption planning |
| Ready | Foundational | Partially relevant — landing zone setup; touched briefly via Terraform, not the focus |
| Adopt | Foundational | Relevant — this repo *is* an "innovate" build: a new cloud-native AI workload |
| **Govern** | Operational | **Primary mapping target** — policy-driven control over the AKS/AI workload |
| **Secure** | Operational | **Primary mapping target** — this repo's core subject matter |
| **Manage** | Operational | **Primary mapping target** — monitoring, detection, and operational health |

## Control mapping

### Secure methodology

| CAF Secure area | Control in this repo | Evidence |
|---|---|---|
| Protect against prompt-based and application-layer attacks | Input/output guardrails (`prompt_filter.py`, `response_filter.py`) | [`app/`](../app/), [`docs/threat-model-rag-service.md`](./threat-model-rag-service.md) |
| Identity and access for workloads | AKS Workload Identity Federation to Key Vault (no static credentials in cluster) | [`kubernetes/`](../kubernetes/), [`terraform/`](../terraform/) |
| Network segmentation | NetworkPolicy restricting east-west traffic within the AKS namespace | [`kubernetes/network-policy.yaml`](../kubernetes/network-policy.yaml) |
| Least-privilege access control | Namespace-scoped RBAC; restricted Pod Security Standards | [`kubernetes/rbac.yaml`](../kubernetes/rbac.yaml), [`kubernetes/pod-security.yaml`](../kubernetes/pod-security.yaml) |
| Secure the software supply chain | CodeQL (SAST), Gitleaks (secrets), Trivy (container), Checkov (IaC) gates pre-deploy | [`.github/workflows/`](../.github/workflows/) |
| Validate security of running workloads | OWASP ZAP dynamic scan against staging endpoint, blocking promotion on failure | [`.github/workflows/zap-scan.yml`](../.github/workflows/zap-scan.yml) |
| Protect sensitive data | Retrieval scoping, output PII filtering, Key Vault for secrets | [`docs/threat-model-rag-service.md`](./threat-model-rag-service.md) — LLM02:2025 |
| Threat modelling as a security practice | STRIDE + OWASP LLM Top 10 (2025) applied to this specific service | [`docs/threat-model-rag-service.md`](./threat-model-rag-service.md) |

### Govern methodology

| CAF Govern area | Control in this repo | Evidence |
|---|---|---|
| Policy-driven governance | Infrastructure defined and deployed via Terraform, not manual portal configuration — config drift is visible in version control | [`terraform/`](../terraform/) |
| Security posture visibility | Documented "what's actually live vs. reference design" status, consistent across this repo series | This README's status table (filled in as components are built) |
| Risk-based decision-making | Threat model drives which controls were prioritised (e.g., LLM02:2025 weighted highest given PII exposure) | [`docs/threat-model-rag-service.md`](./threat-model-rag-service.md) |
| Recurring governance processes | CI/CD gates run on every commit, not as a one-time review | [`.github/workflows/`](../.github/workflows/) |

### Manage methodology

| CAF Manage area | Control in this repo | Evidence |
|---|---|---|
| Monitor the cloud estate (security signal) | Sentinel analytics rule for prompt injection, built against real application logs | [`sentinel/`](../sentinel/) |
| Operational logging | Guardrail decisions (pass/block/reason) logged for every request, feeding both detection and incident investigation | [`app/`](../app/) deployment notes |
| Incident readiness | Detection rule maps directly to a threat-model finding (LLM01:2025), not a generic template | [`docs/threat-model-rag-service.md`](./threat-model-rag-service.md), [`sentinel/`](../sentinel/) |

### Adopt methodology (Innovate path)

| CAF Adopt area | Control in this repo | Evidence |
|---|---|---|
| Build cloud-native AI workloads | RAG API built as a containerised, AKS-native service from the outset, not lifted from elsewhere | [`app/`](../app/), [`kubernetes/`](../kubernetes/) |
| Architect for the target platform | Workload Identity, Key Vault, and Sentinel integration designed into the architecture, not retrofitted | [`docs/architecture-overview.md`](./architecture-overview.md) |

## What this mapping deliberately does not claim

CAF is an organization-wide adoption framework; this repo is one workload. Several CAF
areas — multi-subscription governance, enterprise-scale landing zones, cost management at
scale, organizational change management — are out of scope by nature of what a single
fictitious service can demonstrate. This mapping claims coverage only where this repo has
an actual artifact (code, config, or a deployed/tested control) behind the claim — the
same standard applied throughout this repo series.

## Status summary

<!-- TBD — update as each component is built, consistent with the "what's actually live
     vs. reference design" pattern used in the other two repos -->

| CAF methodology | Coverage in this repo | Status |
|---|---|---|
| Secure | Guardrails, network/RBAC/pod security, CI/CD static + dynamic gates | TBD |
| Govern | Terraform-as-policy, threat-model-driven prioritisation | TBD |
| Manage | Sentinel detection rule, application logging | TBD |
| Adopt (Innovate) | Cloud-native AI workload build | TBD |