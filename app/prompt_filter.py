"""
prompt_filter.py — Input guardrail for the RAG Customer Service Assistant.

Purpose
-------
Runs on every customer message BEFORE it reaches Azure OpenAI. Implements the
LLM01:2025 (Prompt Injection) mitigation described in
docs/threat-model-rag-service.md.

Design decision
----------------
This guardrail uses pattern matching, not a secondary LLM-based classifier.
That's deliberate — it keeps the control auditable, testable offline, and
free of a second model dependency, cost, and latency. The tradeoff is real:
pattern matching cannot catch every injection variant. Known bypasses are
documented in tests/test_prompt_filter.py rather than hidden, consistent
with the Residual Risk section of the threat model.

Every decision this filter makes is returned as a structured result so the
caller (rag-api/main.py) can log it — that log is the data source for the
Sentinel prompt-injection-detection.kql rule.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from enum import Enum


class BlockReason(str, Enum):
    INSTRUCTION_OVERRIDE = "instruction_override"
    ROLE_MANIPULATION = "role_manipulation"
    SYSTEM_PROMPT_PROBE = "system_prompt_probe"
    EXCESSIVE_LENGTH = "excessive_length"
    SUSPICIOUS_ENCODING = "suspicious_encoding"


@dataclass
class FilterResult:
    allowed: bool
    reason: BlockReason | None = None
    matched_pattern: str | None = None
    normalized_input: str = ""

    def to_log_dict(self) -> dict:
        """Structured form for application logging / Sentinel ingestion."""
        return {
            "control": "prompt_filter",
            "allowed": self.allowed,
            "reason": self.reason.value if self.reason else None,
            "matched_pattern": self.matched_pattern,
        }


# Maximum input length, in characters. Generous enough for a genuine customer
# question, restrictive enough to limit token-consumption abuse (LLM10:2025).
MAX_INPUT_LENGTH = 2000

# Instruction-override patterns: attempts to make the model disregard its
# system prompt or prior instructions.
_INSTRUCTION_OVERRIDE_PATTERNS = [
    r"ignore\s+(all\s+)?(?:your\s+|my\s+|the\s+)?(previous|prior|above)\s+instructions?",
    r"disregard\s+(all\s+)?(?:your\s+|my\s+|the\s+)?(previous|prior|above)\s+(instructions?|rules?|prompts?)",
    r"forget\s+(all\s+)?(previous|prior|your)\s+(instructions?|rules?|training)",
    r"new\s+instructions?\s*:",
    r"override\s+(your\s+)?(instructions?|system\s+prompt|rules?)",
    r"from\s+now\s+on\s*,?\s*you\s+(will|must|should)",
]

# Role-manipulation patterns: attempts to get the model to adopt a persona
# that wouldn't be bound by its guardrails.
_ROLE_MANIPULATION_PATTERNS = [
    r"you\s+are\s+now\s+(a|an)\s+\w+",
    r"act\s+as\s+(a|an)\s+\w+\s+(with\s+no|without)\s+(restrictions?|filters?|limits?)",
    r"pretend\s+(you('|\u2019)?re|to\s+be)\s+",
    r"developer\s+mode",
    r"jailbreak",
    r"DAN\s+mode",  # common "Do Anything Now" jailbreak shorthand
]

# System-prompt probing: attempts to extract the system prompt itself
# (an early signal of LLM07:2025 — System Prompt Leakage).
_SYSTEM_PROMPT_PROBE_PATTERNS = [
    r"(repeat|print|show|reveal|output)\s+(your\s+)?(system\s+prompt|instructions?)",
    r"what\s+(are|were)\s+you\s+(told|instructed)\s+to\s+do",
    r"what\s+is\s+your\s+(system\s+)?prompt",
]

_ALL_PATTERN_GROUPS: list[tuple[BlockReason, list[str]]] = [
    (BlockReason.INSTRUCTION_OVERRIDE, _INSTRUCTION_OVERRIDE_PATTERNS),
    (BlockReason.ROLE_MANIPULATION, _ROLE_MANIPULATION_PATTERNS),
    (BlockReason.SYSTEM_PROMPT_PROBE, _SYSTEM_PROMPT_PROBE_PATTERNS),
]

_COMPILED_GROUPS = [
    (reason, [re.compile(p, re.IGNORECASE) for p in patterns])
    for reason, patterns in _ALL_PATTERN_GROUPS
]


def _normalize(text: str) -> str:
    """
    Normalize Unicode to catch simple homoglyph / invisible-character evasion
    (e.g. zero-width spaces inserted mid-word to dodge a literal regex
    match). This is NOT a complete defence against Unicode-based evasion —
    see tests/test_prompt_filter.py for a documented bypass that survives
    this normalization.
    """
    stripped = "".join(ch for ch in text if unicodedata.category(ch) != "Cf")
    return unicodedata.normalize("NFKC", stripped)


def _looks_like_suspicious_encoding(text: str) -> bool:
    """
    Flags inputs unusually dense in non-printable/control characters
    relative to their length — a common technique for smuggling content
    past a literal-string review while it's still interpreted by the model.
    """
    if not text:
        return False
    control_chars = sum(1 for ch in text if unicodedata.category(ch) in ("Cc", "Cf"))
    return control_chars / max(len(text), 1) > 0.05


def check_prompt(user_input: str) -> FilterResult:
    """
    Run the full input guardrail against a single customer message.

    Returns a FilterResult. The caller is responsible for rejecting the
    request and logging the result when allowed=False — this function does
    not raise exceptions or perform I/O, to keep it easily unit-testable.
    """
    if len(user_input) > MAX_INPUT_LENGTH:
        return FilterResult(
            allowed=False,
            reason=BlockReason.EXCESSIVE_LENGTH,
            matched_pattern=f"length={len(user_input)}>{MAX_INPUT_LENGTH}",
        )

    normalized = _normalize(user_input)

    if _looks_like_suspicious_encoding(user_input):
        return FilterResult(
            allowed=False,
            reason=BlockReason.SUSPICIOUS_ENCODING,
            matched_pattern="high control-character density",
            normalized_input=normalized,
        )

    for reason, compiled_patterns in _COMPILED_GROUPS:
        for pattern in compiled_patterns:
            match = pattern.search(normalized)
            if match:
                return FilterResult(
                    allowed=False,
                    reason=reason,
                    matched_pattern=match.group(0),
                    normalized_input=normalized,
                )

    return FilterResult(allowed=True, normalized_input=normalized)