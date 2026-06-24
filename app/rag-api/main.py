"""
main.py — RAG API service entry point.

Single endpoint: POST /chat
Flow: input guardrail -> retrieval -> generation -> output guardrail

Every guardrail decision is logged as structured JSON so it can be picked up
by the Sentinel detection rule in sentinel/prompt-injection-detection.kql
once shipped to a real Log Analytics workspace. Locally, it goes to stdout —
see app/README.md for the logging-to-Sentinel pipeline status.
"""

from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

from fastapi import FastAPI, HTTPException

# prompt_filter.py and response_filter.py live one directory up (app/), as
# siblings of this service rather than nested inside it, so a second
# AI-powered service could reuse the same guardrails without duplication.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from prompt_filter import check_prompt  # noqa: E402
from response_filter import check_response  # noqa: E402

from clients import generate_response, retrieve_context  # noqa: E402
from models import ChatRequest, ChatResponse  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("rag-api")

SYSTEM_PROMPT_PATH = Path(__file__).resolve().parent / "prompts" / "system_prompt.txt"
SYSTEM_PROMPT = SYSTEM_PROMPT_PATH.read_text(encoding="utf-8")

app = FastAPI(title="Contoso RAG Customer Service Assistant")


def _log_guardrail_event(stage: str, customer_id: str, result_dict: dict) -> None:
    """
    Structured log line — one JSON object per guardrail decision. This is
    the data source for sentinel/prompt-injection-detection.kql; the field
    names here must stay in sync with that query.
    """
    logger.info(json.dumps({"stage": stage, "customer_id": customer_id, **result_dict}))


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}


@app.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest) -> ChatResponse:
    # 1. Input guardrail — first trust boundary (see architecture-overview.md)
    input_result = check_prompt(request.message)
    _log_guardrail_event("input", request.customer_id, input_result.to_log_dict())

    if not input_result.allowed:
        return ChatResponse(
            answer="I'm not able to process that request. Please rephrase your question.",
            blocked=True,
            block_reason=input_result.reason.value if input_result.reason else None,
        )

    # 2. Retrieval — scoped server-side to the requesting customer only
    try:
        context = retrieve_context(request.message, request.customer_id)
    except Exception as exc:  # pragma: no cover - exercised via integration tests once live
        logger.error(json.dumps({"stage": "retrieval", "error": str(exc)}))
        raise HTTPException(status_code=502, detail="Retrieval service unavailable") from exc

    # 3. Generation
    try:
        raw_answer = generate_response(request.message, context, SYSTEM_PROMPT)
    except Exception as exc:  # pragma: no cover - exercised via integration tests once live
        logger.error(json.dumps({"stage": "generation", "error": str(exc)}))
        raise HTTPException(status_code=502, detail="Generation service unavailable") from exc

    # 4. Output guardrail — second trust boundary
    output_result = check_response(raw_answer)
    _log_guardrail_event("output", request.customer_id, output_result.to_log_dict())

    if not output_result.allowed:
        return ChatResponse(
            answer="I'm not able to share that information. Please contact support directly.",
            blocked=True,
            block_reason=output_result.reason.value if output_result.reason else None,
        )

    return ChatResponse(answer=output_result.sanitized_output)