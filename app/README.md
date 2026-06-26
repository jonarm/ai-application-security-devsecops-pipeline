# app/ — RAG API and Guardrails

## What's here

- `rag-api/` — the FastAPI service itself (`main.py`, `models.py`, `clients.py`,
  `prompts/system_prompt.txt`, `Dockerfile`, `requirements.txt`)
- `prompt_filter.py` — input guardrail (LLM01:2025 Prompt Injection mitigation)
- `response_filter.py` — output guardrail (LLM07:2025 System Prompt Leakage,
  LLM02:2025 Sensitive Information Disclosure, LLM05:2025 Improper Output Handling)
- `tests/` — pytest test cases for both guardrails, including a documented
  known bypass (see below)

`prompt_filter.py` and `response_filter.py` live as siblings to `rag-api/`
rather than nested inside it, so a second AI-powered service could reuse the
same guardrails without duplicating the code — see the import comment at
the top of `rag-api/main.py`.

## Running locally

```powershell
cd app\rag-api
pip install -r requirements.txt
$env:RAG_MOCK_MODE = "true"
uvicorn main:app --reload
```

With `RAG_MOCK_MODE=true` (the default), `/chat` runs the full guardrail
pipeline against canned retrieval/generation responses — no Azure OpenAI or
Azure AI Search resources are required. This is the only mode that has been
exercised end-to-end so far.

## Running the tests

```powershell
cd app
pytest -v
```

## What's actually live vs. reference design

| Component | Status |
|---|---|
| `prompt_filter.py` | **Live** — real code, unit-tested, including a documented known bypass |
| `response_filter.py` | **Live** — real code, unit-tested |
| `rag-api/main.py` request flow | **Live** — runs end-to-end in mock mode |
| Real Azure OpenAI integration (`clients.py` non-mock path) | **Reference design** — written against the real SDKs and the Workload Identity pattern, but not yet exercised against a deployed Azure OpenAI resource (see `terraform/`) |
| Real Azure AI Search integration (`clients.py` non-mock path) | **Reference design** — same status as above |

## Known limitations (see also: Residual Risk in `docs/threat-model-rag-service.md`)

- **Pattern-based guardrails are not exhaustive.**
  `test_known_bypass_paraphrased_instruction_override` in
  `tests/test_prompt_filter.py` documents a paraphrase that currently
  passes the input guardrail despite adversarial intent. Recorded as a
  backlog item rather than patched with a narrow regex that would just
  shift the bypass to different phrasing.
- **`response_filter.py`'s system-prompt-fragment list must be kept in sync
  with `rag-api/prompts/system_prompt.txt` manually.** If the system prompt
  changes and this list isn't updated, leakage detection silently degrades.
  No automated sync exists yet.
- **Mock mode is the only mode tested so far.** The real Azure OpenAI / AI
  Search code paths in `clients.py` are written to the actual SDK
  interfaces and the Workload Identity pattern, but have not been run
  against live resources at the time of writing this note.

  ## Prerequisites for building the container

Docker Desktop must be running (not just installed) before `docker build`
— check for "Engine running" in the Docker Desktop window. On Windows,
this also requires the WSL2 backend to be enabled.

## Building the image

Two approaches were tried before landing on the one that works for this
subscription:

1. **`az acr build` (ACR Tasks remote build)** — tried first to avoid a
   local Docker dependency entirely. Failed with `TasksOperationsNotAllowed`.
   This is a known Azure restriction: ACR Tasks remote builds are paused
   for subscriptions funded by free trial credits, which this subscription
   is. Not fixable without a support ticket or a subscription upgrade —
   abandoned rather than worth the wait for a portfolio build.
2. **Local `docker build` + `docker push`** — the approach actually used.
   Requires Docker Desktop running locally (WSL2 backend) and an
   `AcrPush` role assignment on the registry, since only the AKS
   cluster's kubelet identity was granted `AcrPull` in Terraform.

```powershell
az acr login --name <acr-name>
docker build -t "<acr-login-server>/rag-api:latest" .
docker push "<acr-login-server>/rag-api:latest"
```

This is a real example of free-tier Azure subscription constraints shaping
a technical decision — documented rather than hidden, consistent with this
repo series' standard.

## Issues encountered and resolved — AKS deployment

- **CrashLoopBackOff on first real AKS deploy — wrong Docker build context.**
  The Dockerfile was originally built and pushed with context scoped to
  `app/rag-api/` only (`docker build . ` run from inside that directory).
  `main.py` imports `prompt_filter` and `response_filter` from one
  directory up by design (see the import comment in `main.py`), but those
  files were never included in that build context — they simply weren't
  in the image. The container crashed with `ModuleNotFoundError` at
  startup, before binding a port, which produced an instant
  `CrashLoopBackOff` with `Exit Code 1` well before the liveness probe's
  5-second delay ever ran. Confirmed via `kubectl logs` before fixing.
  Fixed by changing the build context to `app/` and pointing `-f` at
  `rag-api/Dockerfile`, with the Dockerfile updated to `COPY` the
  guardrail files explicitly before the service code. Workload Identity,
  image pull, and pod scheduling all worked correctly on the very first
  attempt — only the application's own module layout inside the image was
  wrong.