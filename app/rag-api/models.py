"""
models.py — Pydantic request/response schemas for the RAG API.
"""

from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    customer_id: str = Field(..., min_length=1, max_length=64)
    message: str = Field(..., min_length=1)


class ChatResponse(BaseModel):
    answer: str
    blocked: bool = False
    block_reason: str | None = None