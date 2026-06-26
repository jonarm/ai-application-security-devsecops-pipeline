# .github/workflows/ — CI/CD Security Gates

## Pipeline order

| Stage | Workflow | Trigger | Blocks on |
|---|---|---|---|
| Static — SAST | `codeql.yml` | push/PR to `app/**`, weekly schedule | CodeQL findings |
| Static — Secrets | `gitleaks.yml` | push/PR (any path) | Any non-allowlisted secret pattern |
| Static — Container | `trivy.yml` | push/PR to `app/**` | CRITICAL/HIGH CVEs in the built image |
| Static — IaC | `checkov.yml` | push/PR to `terraform/**` | Any non-skipped Checkov finding |
| Dynamic — DAST | `zap-scan.yml` | manual (`workflow_dispatch`) | Any ZAP alert at FAIL threshold (see `.zap/rules.tsv`) |

The four static gates run automatically on every relevant push/PR. The
dynamic gate is manually triggered for now — see "What's actually live"
below for why.

## Real findings caught before first run

- **Gitleaks would flag `app/tests/test_response_filter.py`.** That file
  intentionally contains a fake, key-shaped string
  (`sk-live_AbCdEfGhIjKlMnOpQrSt1234`) as a test fixture for
  `response_filter.py`'s own sensitive-data detection. `.gitleaks.toml`
  scopes an allowlist to that exact file, with the reasoning documented
  inline rather than disabling the rule globally.
- **Checkov would flag two deliberate Terraform decisions:**
  `CKV_AZURE_110` (Key Vault purge protection disabled, for clean lab
  teardown) and `CKV_AZURE_6` (AKS API server authorized IP ranges not
  set, for development convenience against a dynamic IP). Both are
  addressed with inline `#checkov:skip` annotations carrying the same
  justification recorded in `terraform/README.md` — not silently passed
  via `soft_fail: true`.

## What's actually live vs. reference design

| Component | Status |
|---|---|
| YAML syntax for all five workflows | **Validated** — parsed cleanly with an offline parser before commit |
| `codeql.yml`, `gitleaks.yml`, `trivy.yml`, `checkov.yml` | **Reference design** — written to trigger automatically on push/PR, not yet exercised against a real GitHub Actions run at the time of writing |
| `zap-scan.yml` | **Reference design, manually triggered by design** — there is no automated deploy-to-staging workflow in this repo yet, so this cannot run automatically post-deploy. Wiring `zap-scan.yml` to trigger via `workflow_run` after a future deploy workflow is a documented next step, not yet built |

## Known limitations

- **ZAP runs baseline (passive) scans only**, not active scanning.
  Promoting to `zaproxy/action-full-scan` would add active attack payloads
  but risks instability against a low-traffic/shared staging environment —
  noted as a deliberate scope decision for this build.
- **No automated CD step exists yet** to build the `rag-api` image, push
  it to the ACR provisioned in `terraform/`, and deploy it to AKS. The
  four static gates run on source/config; actually getting a running
  staging endpoint for `zap-scan.yml` to target is still a manual step.