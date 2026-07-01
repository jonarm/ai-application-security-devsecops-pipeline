# .github/workflows/ — CI/CD Security Gates

## Pipeline order

| Stage | Workflow | Trigger | Blocks on |
|---|---|---|---|
| Build & Push | `build-and-push.yml` | push to `app/**`, manual (`workflow_dispatch`) | Build or push failure |
| Static — SAST | `codeql.yml` | push/PR to `app/**`, weekly schedule | CodeQL findings |
| Static — Secrets | `gitleaks.yml` | push/PR (any path) | Any non-allowlisted secret pattern |
| Static — Container | `trivy.yml` | push/PR to `app/**` | CRITICAL/HIGH CVEs in the built image |
| Static — IaC | `checkov.yml` | push/PR to `terraform/**` | Any non-skipped Checkov finding |
| Dynamic — DAST | `zap-scan.yml` | manual (`workflow_dispatch`) | Any ZAP alert at FAIL threshold (see `.zap/rules.tsv`) |

`build-and-push.yml` authenticates to Azure via OIDC using a dedicated
`id-github-actions-ci` managed identity (see `terraform/github-actions-ci.tf`)
— deliberately separate from the `id-rag-api-workload` identity the running
application uses, so CI/CD only ever holds `AcrPush` and the app only ever
holds `Key Vault Secrets User`. The four static gates run automatically on
every relevant push/PR. The dynamic gate is manually triggered for now —
see "What's actually live" below for why.

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
| YAML syntax for all six workflows | **Validated** — parsed cleanly with an offline parser before commit |
| `build-and-push.yml` | **Live** — first real run succeeded via manual `workflow_dispatch` trigger, OIDC authentication to Azure with no stored credentials, image built and pushed to ACR with both `:latest` and commit-SHA tags. See `screenshots/aks-deployment/08-github-actions-build-push-success.png` and `09-acr-tags-sha-and-latest.png` |
| `codeql.yml`, `gitleaks.yml`, `trivy.yml`, `checkov.yml` | **Reference design** — written to trigger automatically on push/PR, not yet exercised against a real GitHub Actions run at the time of writing |
| `zap-scan.yml` | **Live** — run once against a temporary public LoadBalancer endpoint (`http://40.90.240.206`). 68 checks passed, 0 failed, 2 warnings (both justified ignores for a JSON REST API — `10049` on 404 responses for non-existent endpoints, `90005` on a browser-specific fetch metadata header not applicable to API scanning). **Known limitation:** ZAP's spider could not discover `/healthz` or `/chat` because a pure JSON API has no HTML, sitemap, or links for the spider to follow — the scan surface was effectively three 404 endpoints. A more thorough DAST scan would require configuring ZAP with an explicit API definition (OpenAPI/Swagger spec) to target the real endpoints directly. |

## Known limitations

- **ZAP runs baseline (passive) scans only**, not active scanning.
  Promoting to `zaproxy/action-full-scan` would add active attack payloads
  but risks instability against a low-traffic/shared staging environment —
  noted as a deliberate scope decision for this build.
- **`build-and-push.yml` builds and pushes the image, but does not deploy
  it to AKS.** Getting a newly-pushed image actually running on the
  cluster still requires a manual `kubectl rollout restart` — there is no
  automated CD step from ACR to AKS yet. This is also why `zap-scan.yml`
  has no automatic trigger: there's no automated step that produces a
  fresh, reachable staging endpoint to scan.

## CI/CD identity setup — issues encountered and resolved

- **Output values copied from the wrong identity initially.** Before the
  GitHub Actions CI identity (`id-github-actions-ci`) was actually
  applied via Terraform, a `terraform output` value was mistakenly