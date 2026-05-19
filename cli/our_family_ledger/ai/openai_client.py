"""OpenAI-compatible API client for OurFamilyLedger chat command (TES-43).

Sends natural-language transaction text to an OpenAI-compatible endpoint
and parses the structured JSON response into TransactionDraft objects.
"""

from __future__ import annotations

import json
import socket
import urllib.error
import urllib.request
from typing import TYPE_CHECKING

from our_family_ledger.ai.prompts import SYSTEM_PROMPT, TransactionDraft, extract_json

if TYPE_CHECKING:
    from our_family_ledger.config import AIConfig


class OpenAIClientError(Exception):
    """Raised when the API call fails."""


class OpenAIClient:
    """HTTP client for OpenAI-compatible chat completions API."""

    def __init__(self, config: "AIConfig") -> None:
        self._config = config

    def _chat(self, messages: list[dict]) -> str:
        """Call chat/completions endpoint; return the assistant reply text."""
        import urllib.error
        import urllib.request

        url = f"{self._config.endpoint.rstrip('/')}/chat/completions"
        payload = json.dumps(
            {
                "model": self._config.model,
                "messages": messages,
                "temperature": 0.2,
            }
        ).encode()

        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Authorization": f"Bearer {self._config.api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        try:
            ctx = urllib.request.urlopen(req, timeout=30)
            body = ctx.read().decode()
        except urllib.error.HTTPError as exc:
            code = exc.code
            try:
                detail = exc.read().decode()
            except Exception:
                detail = ""
            if code == 401:
                raise OpenAIClientError(
                    "API Key 无效或已过期，请运行 `ledger chat` 重新配置。"
                ) from exc
            if code == 429:
                raise OpenAIClientError(
                    "API 速率限制，请稍候再试。"
                ) from exc
            raise OpenAIClientError(
                f"API 请求失败（HTTP {code}）：{detail[:200]}"
            ) from exc
        except (OSError, socket.timeout) as exc:
            raise OpenAIClientError(
                f"网络连接失败：{exc}"
            ) from exc

        try:
            data = json.loads(body)
            return data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, json.JSONDecodeError) as exc:
            raise OpenAIClientError(
                f"API 响应格式异常：{body[:300]}"
            ) from exc

    def parse_transaction(self, messages: list[dict]) -> list[TransactionDraft]:
        """Parse natural-language transaction text via the LLM.

        Args:
            messages: Conversation history in OpenAI format.
                      System prompt is prepended automatically.

        Returns:
            List of TransactionDraft objects (usually one, may be empty on failure).
        """
        full_messages = [{"role": "system", "content": SYSTEM_PROMPT}] + messages
        reply = self._chat(full_messages)
        items = extract_json(reply)
        return [TransactionDraft.from_dict(item) for item in items]
