# app/ — RAG API and Guardrails

## What's here

- `rag-api/` — the FastAPI service itself (`main.py`, `models.py`, `clients.py`,
  `prompts/system_prompt.txt`, `Dockerfile`, `requirements.txt`)
- `prompt_filter.py` — input guardrail (LLM01:2025 Prompt Injection mitigation)
- `response_filter.py` — output guardrail (LLM07:2025 System Prompt Leakage,
  LLM02:2025 Sensitive Information Disclosure, LLM05:2025 Improper Output Handling)
- `tests/` — pytest test suite for both guardrails, including a documented
  known bypass (see below)

`prompt_filter.py` and `response_filter.py` live as siblings to `rag-api/`
rather than nested inside it, so a second AI-powered service could reuse
the same guardrails without duplicating the code — see the import comment
at the top of `rag-api/main.py`.

## Running locally

```powershell
cd app\rag-api
python -m pip install -r requirements.txt
$env:RAG_MOCK_MODE = "true"
python -m uvicorn main:app --reload
```

Note: if your local Python is newer than the container's (this project's
Docker image uses `python:3.12-slim`), some pinned dependencies — notably
`pydantic-core`, which is Rust-backed — may fail to build locally on a
very new Python version. See "Issues encountered" below. The container is
the source of truth for what's actually deployed; testing via `docker run`
is preferred over fighting local environment mismatches.

## Running the tests

```powershell
cd app
python -m pytest -v
```

## What's actually live vs. reference design

| Component | Status |
|---|---|
| `prompt_filter.py` | **Live** — unit-tested (17 tests passing), includes one documented known bypass and one real regex gap found and fixed during dependency-upgrade verification |
| `response_filter.py` | **Live** — unit-tested |
| `rag-api/main.py` full request flow | **Live, confirmed twice** — end-to-end against a real AKS deployment (`screenshots/aks-deployment/05-07`) and again via direct container smoke test after the `fastapi`/`starlette` dependency upgrade |
| Real Azure OpenAI integration (`clients.py` non-mock path) | **Reference design** — written against the real SDK and Workload Identity pattern, never exercised against a live Azure OpenAI resource (deliberately out of scope — see `docs/architecture-overview.md`) |
| Real Azure AI Search integration (`clients.py` non-mock path) | **Reference design** — same status as above |

## Building the image

Two approaches were tried before landing on the one that works for this
subscription:

1. **`az acr build` (ACR Tasks remote build)** — tried first to avoid a
   local Docker dependency entirely. Failed with `TasksOperationsNotAllowed`
   — a known Azure restriction pausing ACR Tasks for subscriptions funded
   by free trial credits, which this one is. Abandoned rather than worth
   a support ticket for a portfolio build.
2. **Local `docker build` + `docker push`** — the approach actually used,
   and also how `.github/workflows/build-and-push.yml` builds the image
   in CI (see that workflow's own notes for the OIDC authentication setup).

```powershell
az acr login --name <acr-name>
docker build -t "<acr-login-server>/rag-api:latest" -f rag-api\Dockerfile .
docker push "<acr-login-server>/rag-api:latest"
```

**Build context note:** the build context is `app/`, not `app/rag-api/` —
see "Issues encountered — AKS deployment" below for why this matters.

## Issues encountered and resolved — AKS deployment

- **CrashLoopBackOff on first real AKS deploy — wrong Docker build context.**
  The Dockerfile was originally built with context scoped to `app/rag-api/`
  only. `main.py` imports `prompt_filter` and `response_filter` from one
  directory up by design, but those files were never included in that
  narrower build context — they simply weren't in the image. The container
  crashed with `ModuleNotFoundError` at startup, confirmed via `kubectl
  logs` before fixing. Fixed by changing the build context to `app/` and
  pointing `-f` at `rag-api/Dockerfile`, with the Dockerfile updated to
  `COPY` the guardrail files explicitly before the service code. Workload
  Identity, image pull, and pod scheduling all worked correctly on the
  very first attempt — only the application's own module layout inside
  the image was wrong.

## Issues encountered and resolved — dependency security and a regex gap

- **`starlette` 0.38.6 (transitive via `fastapi==0.115.0`) had 3 HIGH CVEs**
  (CVE-2024-47874, CVE-2026-48818, CVE-2026-54283). No patched `starlette`
  version existed within `fastapi==0.115.0`'s allowed range
  (`<0.39.0,>=0.37.2` — confirmed via a real pip resolver error, not
  assumed), so the fix required upgrading `fastapi` itself to the current
  release (0.138.1) rather than pinning `starlette` directly. Verified
  safe via a full pytest run and a manual `/chat` smoke test against the
  running container — not just a green CVE scan — given how large the
  version jump was.
- **`prompt_filter.py`'s instruction-override regex had a real gap**,
  found independently while re-verifying after the dependency bump:
  phrases like "ignore/disregard **your** previous instructions" — with a
  possessive pronoun between the verb and "previous/prior" — bypassed
  detection entirely. Unrelated to the dependency work, caught by the same
  verification pass. Fixed in both the `ignore` and `disregard` patterns;
  `test_ignore_your_previous_instructions_is_blocked` confirms it.
- **Several Debian system-package CVEs have no available fix** at the time
  of writing (`perl-base`, the `ncurses` family, `libsqlite3-0`).
  `.github/workflows/trivy.yml` sets `ignore-unfixed: true` — the standard
  Trivy practice for CVEs with no upstream patch. This is a category-level
  gate decision: any future unfixed CVE is also silently passed through,
  which is the intended tradeoff, not a loophole.
- **Local dependency installation hit an unrelated environment mismatch**:
  the development machine runs Python 3.14, which `pydantic-core`'s pinned
  version (Rust/PyO3-backed) doesn't yet support — PyO3 explicitly caps at
  Python 3.13. No bearing on the deployed artifact, since the Docker image
  uses `python:3.12-slim`; verification was done by running the built
  container directly rather than fighting the local environment mismatch.

## Known limitations

- **Pattern-based guardrails are not exhaustive.** See
  `tests/test_prompt_filter.py::test_known_bypass_paraphrased_instruction_override`
  for a documented, currently-unfixed bypass — recorded as a backlog item
  rather than patched with a narrow regex that would just shift the bypass
  to different phrasing.
- **`response_filter.py`'s system-prompt-fragment list must be kept in
  sync with `rag-api/prompts/system_prompt.txt` manually.** No automated
  sync exists yet.