"""System prompt constants and TransactionDraft dataclass for AI parsing."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------


@dataclass
class TransactionDraft:
    """Structured transaction draft returned by the AI parser."""

    date: str           # YYYY-MM-DD
    amount: float
    type: str           # "expense" | "income"
    category: str
    payer: str
    participants: list[str] = field(default_factory=list)
    note: str = ""
    merchant: str = ""
    confidence_amount: float = 1.0
    confidence_date: float = 1.0

    @classmethod
    def from_dict(cls, d: dict) -> "TransactionDraft":
        """Build a TransactionDraft from a raw dict (AI JSON response)."""
        participants = d.get("participants", [])
        if isinstance(participants, str):
            participants = [p.strip() for p in participants.split(",") if p.strip()]
        return cls(
            date=str(d.get("date", "")),
            amount=float(d.get("amount", 0.0)),
            type=str(d.get("type", "expense")),
            category=str(d.get("category", "")),
            payer=str(d.get("payer", "")),
            participants=list(participants),
            note=str(d.get("note", "")),
            merchant=str(d.get("merchant", "")),
            confidence_amount=float(d.get("confidence_amount", 1.0)),
            confidence_date=float(d.get("confidence_date", 1.0)),
        )


# ---------------------------------------------------------------------------
# System prompt (translated from Swift TransactionParsePrompt.systemPrompt)
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """\
你是家庭记账助手。从用户输入中提取交易信息，返回 JSON 数组。

输出格式（严格 JSON，禁止额外文字）：
[
  {
    "date": "YYYY-MM-DD",
    "amount": 0.0,
    "type": "expense",
    "category": "餐饮",
    "payer": "我",
    "participants": ["我", "老婆"],
    "note": "",
    "merchant": "",
    "confidence_amount": 0.9,
    "confidence_date": 0.8
  }
]

规则：
- type 只能是 "expense"（支出）或 "income"（收入）
- date 使用 YYYY-MM-DD 格式；若用户未提及日期，使用今天日期
- participants 是分摊者列表（包括付款人本人）
- confidence_amount / confidence_date 范围 0~1，越确定越高
- 若一条输入含多笔交易，每笔单独列出
- 只返回 JSON，不要解释\
"""


# ---------------------------------------------------------------------------
# JSON extraction helpers
# ---------------------------------------------------------------------------


def extract_json(text: str) -> list[dict]:
    """Extract a list of transaction dicts from raw LLM output.

    Strategy (priority order):
    1. Regex-strip ```json ... ``` markdown code fences.
    2. Direct json.loads on cleaned text.
    3. Find first '[' (array) and try to parse from there.
    4. Find first '{' (single object) and wrap in list.
    """
    cleaned = _strip_markdown_fences(text.strip())

    # Direct parse
    try:
        result = json.loads(cleaned)
        return _normalise(result)
    except json.JSONDecodeError:
        pass

    # Fallback: find array start
    idx_arr = cleaned.find("[")
    idx_obj = cleaned.find("{")

    if idx_arr != -1 and (idx_obj == -1 or idx_arr <= idx_obj):
        snippet = cleaned[idx_arr:]
        try:
            return _normalise(json.loads(snippet))
        except json.JSONDecodeError:
            pass

    if idx_obj != -1:
        snippet = cleaned[idx_obj:]
        try:
            return _normalise(json.loads(snippet))
        except json.JSONDecodeError:
            pass

    return []


def _strip_markdown_fences(text: str) -> str:
    """Remove leading/trailing ```json ... ``` or ``` ... ``` fences."""
    pattern = r"^```(?:json)?\s*([\s\S]*?)\s*```$"
    match = re.match(pattern, text, re.MULTILINE)
    if match:
        return match.group(1).strip()
    return text


def _normalise(value: object) -> list[dict]:
    """Ensure the parsed value is a list of dicts."""
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    if isinstance(value, dict):
        return [value]
    return []
