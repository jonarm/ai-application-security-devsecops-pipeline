# sentinel/ — Detection Engineering

## What this rule detects

`prompt-injection-detection.kql` implements the detection mitigation for
**LLM01:2025 (Prompt Injection)** described in
[`docs/threat-model-rag-service.md`](../docs/threat-model-rag-service.md).
It reads the structured guardrail decision logs emitted by
`app/rag-api/main.py` and fires on two patterns: sustained probing (3+
blocked input-guardrail events from the same `customer_id` within 15
minutes) and high-confidence single events (`system_prompt_probe` or
`role_manipulation` reasons, which indicate deliberate intent on their own).

## Schema verification

This query targets `ContainerLogV2`, the current Azure Monitor Container
Insights schema for AKS, verified against Microsoft's own documentation
before writing the query — including the fact that `LogMessage` is a
`dynamic` column that auto-parses valid JSON but falls back to an escaped
plain string if a log line is malformed. The query's `tostring()` →
`parse_json()` round trip handles both cases.

## What's actually live vs. reference design

| Component | Status |
|---|---|
| KQL syntax and schema | **Verified** — written against ContainerLogV2's real, documented schema |
| Application-side logging (`_log_guardrail_event` in `app/rag-api/main.py`) | **Live** — confirmed producing the exact JSON shape this query expects, both in mock mode locally and against the real AKS deployment |
| AKS → Log Analytics wiring (`oms_agent` in `terraform/aks.tf`) | **Live, confirmed** — `az aks show` confirms the Container Insights add-on is enabled and pointed at the real `law-ai-governance-sentinel` workspace, reused from the companion `ai-security-llm-governance-controls` repo rather than provisioning a redundant one |
| This query actually returning real rows when run against that workspace | **Not yet confirmed** — the wiring exists, but a real KQL query has not yet been run against `law-ai-governance-sentinel` to confirm `ContainerLogV2` rows are actually arriving with `PodNamespace == "contoso-rag"`. Container Insights typically takes 5-15 minutes after enablement before data flows; this gap between "agent enabled" and "data confirmed queryable" is the one remaining honest verification step |

## Known tuning limitation

A single well-crafted `instruction_override` or `suspicious_encoding`
block does not alone trigger this rule — only `system_prompt_probe` and
`role_manipulation` are treated as high-confidence on their own. Lowering
the sustained-count threshold or adding those two reasons to the
high-confidence branch would catch more, at the cost of more noise. Left
as a documented tuning decision rather than silently resolved one way.