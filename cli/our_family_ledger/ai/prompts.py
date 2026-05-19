"""AI prompts and TransactionDraft dataclass for OurFamilyLedger chat command.

Provides:
  - SYSTEM_PROMPT: instruction for the LLM to parse natural-language transaction input
  - TransactionDraft: structured output returned by the AI layer
  - extract_json: robust JSON extraction from LLM output (handles ```json blocks, arrays, objects)
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from datetime import date as date_type
from typing import Any


SYSTEM_PROMPT = """你是一个家庭记账助手。用户会用自然语言描述一笔交易，你需要解析出结构化的交易信息。

请以 JSON 格式返回，包含以下字段：
- date: 交易日期，格式 YYYY-MM-DD（如未提及，使用今天的日期）
- amount: 金额，数字类型（如 45.0）
- type: 交易类型，"支出" 或 "收入"
- category: 分类（如：餐饮、购物、交通、日用等）
- payer: 付款人（如：我、老婆、孩子等）
- participants: 参与人列表，数组格式（如 ["我", "老婆"]）
- note: 备注说明
- merchant: 商家名称（如未提及留空字符串）
- confidence_amount: 对金额解析的置信度，0.0~1.0
- confidence_date: 对日期解析的置信度，0.0~1.0

注意：
- 如果用户说"均摊"或"AA制"，参与人应包含付款人和其他提到的人
- 分类请从常见生活分类中选择最合适的
- 付款人和参与人使用用户原文中的称谓

示例输入：今天买菜花了45块，我付的，老婆和我均摊
示例输出：
{
  "date": "2026-05-18",
  "amount": 45.0,
  "type": "支出",
  "category": "餐饮",
  "payer": "我",
  "participants": ["我", "老婆"],
  "note": "买菜",
  "merchant": "",
  "confidence_amount": 0.99,
  "confidence_date": 0.85
}

只返回 JSON，不要其他解释文字。"""


@dataclass
class TransactionDraft:
    """Structured transaction draft parsed from natural language input."""

    date: str = field(default_factory=lambda: date_type.today().isoformat())
    amount: float = 0.0
    type: str = "支出"
    category: str = ""
    payer: str = "我"
    participants: list[str] = field(default_factory=list)
    note: str = ""
    merchant: str = ""
    confidence_amount: float = 1.0
    confidence_date: float = 1.0

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "TransactionDraft":
        """Construct from a parsed JSON dict, with safe defaults for missing fields."""
        today = date_type.today().isoformat()
        participants = data.get("participants", [])
        # Handle both list and comma-separated string
        if isinstance(participants, str):
            participants = [p.strip() for p in participants.split(",") if p.strip()]

        return cls(
            date=data.get("date") or today,
            amount=float(data.get("amount", 0.0)),
            type=data.get("type", "支出"),
            category=data.get("category", ""),
            payer=data.get("payer", "我"),
            participants=participants,
            note=data.get("note", ""),
            merchant=data.get("merchant", ""),
            confidence_amount=float(data.get("confidence_amount", 1.0)),
            confidence_date=float(data.get("confidence_date", 1.0)),
        )


def extract_json(text: str) -> list[dict[str, Any]]:
    """Extract JSON objects/arrays from LLM output text.

    Handles:
      - ```json ... ``` fenced blocks
      - Bare JSON arrays [...]
      - Bare JSON objects {...}

    Always returns a list of dicts (single object is wrapped in a list).
    """
    # Try ```json ... ``` block first
    fenced = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if fenced:
        candidate = fenced.group(1).strip()
        try:
            result = json.loads(candidate)
            if isinstance(result, list):
                return result
            if isinstance(result, dict):
                return [result]
        except json.JSONDecodeError:
            pass

    # Try to find first [ or { and parse from there
    for start_char, end_char in [("[", "]"), ("{", "}")]:
        idx = text.find(start_char)
        if idx == -1:
            continue
        # Find matching closing bracket
        depth = 0
        end_idx = -1
        in_str = False
        escape_next = False
        for i, ch in enumerate(text[idx:], idx):
            if escape_next:
                escape_next = False
                continue
            if ch == "\\" and in_str:
                escape_next = True
                continue
            if ch == '"' and not escape_next:
                in_str = not in_str
                continue
            if in_str:
                continue
            if ch == start_char:
                depth += 1
            elif ch == end_char:
                depth -= 1
                if depth == 0:
                    end_idx = i
                    break
        if end_idx != -1:
            try:
                result = json.loads(text[idx : end_idx + 1])
                if isinstance(result, list):
                    return result
                if isinstance(result, dict):
                    return [result]
            except json.JSONDecodeError:
                continue

    return []
