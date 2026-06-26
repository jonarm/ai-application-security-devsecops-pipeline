# sentinel/ — Detection Engineering

## What this rule detects

`prompt-injection-detection.kql` implements the detection mitigation for
**LLM01:2025 (Prompt Injection)** described in
[`docs/threat-model-rag-service.md`](../docs/threat-model-rag-service.md).
It reads the structured guardrail decision logs emitted by
`app/rag-api/main.py` and fires on two patterns:

1. **Sustained probing** — 3+ blocked input-guardrail events from the same
   `customer_id` within a 15-minute window.
2. **High-confidence single event** — any single block reasoned as
   `system_prompt_probe` or `role_manipulation`, which indicate deliberate
   intent on their own.

## Schema verification

This query targets `ContainerLogV2`, the current Azure Monitor Container
Insights schema for AKS (the legacy `ContainerLog` table is being retired
30 September 2026). This was verified against Microsoft's own schema
documentation before writing the query — specifically the fact that
`LogMessage` is a `dynamic` column that auto-parses valid JSON, but falls
back to an escaped plain string if a log line is ever malformed JSON. The
`tostring()` → `parse_json()` round trip in the query handles both cases
rather than assuming clean parsing throughout. This mirrors the same
discipline that caught real schema-assumption errors when building the
analogous Sentinel rule in the companion governance repo.

## What's actually live vs. reference design

| Component | Status |
|---|---|
| KQL syntax and schema | **Verified** — written against ContainerLogV2's real, documented schema, not assumed from memory |
| Application-side logging (`_log_guardrail_event` in `app/rag-api/main.py`) | **Live in mock mode** — produces the exact JSON shape this query expects, verified locally |
| A Log Analytics workspace receiving these logs | **Not provisioned in this repo** — `terraform/` deliberately scopes to AKS, ACR, and Key Vault only (see `terraform/README.md`); no Log Analytics workspace or AKS Container Insights onboarding exists yet in this repo's Terraform |
| This rule actually firing against real data | **Reference design** — cannot run until the gap above is closed |

## The gap, explicitly

There are two ways to close this, neither implemented yet:

- **Provision a new Log Analytics workspace** in this repo's `terraform/`
  and enable AKS monitoring (`az aks enable-addons -a monitoring
  --workspace-resource-id <id>` or the Terraform equivalent
  `oms_agent` block on `azurerm_kubernetes_cluster`).
- **Reuse the existing Sentinel-onboarded Log Analytics workspace** from
  the companion
  [`ai-security-llm-governance-controls`](https://github.com/jonarm/ai-security-llm-governance-controls)
  repo, since both model the same fictitious Contoso Retail Group tenant.

Either path is a real next step, not a blocker disguised as a feature —
recorded here in the same spirit as the governance repo's own "Shadow AI
Detection: blocked by a genuine licensing/connector limitation" entry.

## Known tuning limitation

A single well-crafted `instruction_override` or `suspicious_encoding`
block does not alone trigger this rule — only `system_prompt_probe` and
`role_manipulation` are treated as high-confidence on their own. Lowering
the sustained-count threshold or adding those two reasons to the
high-confidence branch would catch more, at the cost of more noise. Left
as a documented tuning decision rather than silently resolved one way.