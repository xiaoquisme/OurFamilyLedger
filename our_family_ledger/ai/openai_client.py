"""OpenAI-compatible HTTP client for transaction parsing.

Pure HTTP layer — no CLI or DB dependencies.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

from our_family_ledger.ai.prompts import SYSTEM_PROMPT, TransactionDraft, extract_json


# ---------------------------------------------------------------------------
# Configuration dataclass
# ---------------------------------------------------------------------------


@dataclass
class AIConfig:
    """AI provider configuration loaded from config.toml [ai] section."""

    endpoint: str = "https://api.openai.com/v1"
    model: str = "gpt-4o-mini"
    api_key: str = ""
    provider: str = "openai"

    @classmethod
    def from_dict(cls, d: dict) -> "AIConfig":
        return cls(
            endpoint=d.get("endpoint", "https://api.openai.com/v1"),
            model=d.get("model", "gpt-4o-mini"),
            api_key=d.get("api_key", ""),
            provider=d.get("provider", "openai"),
        )


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------


class OpenAIClient:
    """Client for OpenAI-compatible /chat/completions API."""

    _TIMEOUT = 30  # seconds

    def __init__(self, config: AIConfig) -> None:
        self._config = config

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def parse_transaction(self, messages: list[dict]) -> list[TransactionDraft]:
        """Parse natural-language transaction input and return structured drafts.

        Args:
            messages: Conversation history.  Must include at least one user
                      message.  The system prompt is prepended automatically if
                      the first message role is not "system".

        Returns:
            A list of :class:`TransactionDraft` objects (may be empty if the
            LLM response cannot be parsed).

        Raises:
            OpenAIError: On non-retryable API errors (401, 429, network).
        """
        full_messages = self._prepend_system(messages)
        raw = self._chat(full_messages)
        dicts = extract_json(raw)
        return [TransactionDraft.from_dict(d) for d in dicts]

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _prepend_system(self, messages: list[dict]) -> list[dict]:
        """Prepend system prompt if not already the first message."""
        if messages and messages[0].get("role") == "system":
            return messages
        system_msg = {"role": "system", "content": SYSTEM_PROMPT}
        return [system_msg, *messages]

    def _chat(self, messages: list[dict]) -> str:
        """POST to /chat/completions and return the assistant message content.

        Raises:
            OpenAIError: on HTTP errors or network failures.
        """
        url = self._config.endpoint.rstrip("/") + "/chat/completions"
        payload: dict[str, Any] = {
            "model": self._config.model,
            "messages": messages,
        }
        body = json.dumps(payload).encode("utf-8")

        req = urllib.request.Request(
            url,
            data=body,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self._config.api_key}",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=self._TIMEOUT) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            status = exc.code
            body_bytes = exc.read()
            try:
                err_body = json.loads(body_bytes.decode("utf-8"))
                err_msg = err_body.get("error", {}).get("message", str(body_bytes))
            except Exception:
                err_msg = body_bytes.decode("utf-8", errors="replace")

            if status == 401:
                raise OpenAIError(
                    f"API key 无效或未授权 (HTTP 401): {err_msg}"
                ) from exc
            if status == 429:
                raise OpenAIError(
                    f"请求频率超限，请稍后重试 (HTTP 429): {err_msg}"
                ) from exc
            raise OpenAIError(f"API 请求失败 (HTTP {status}): {err_msg}") from exc
        except urllib.error.URLError as exc:
            raise OpenAIError(f"网络连接失败: {exc.reason}") from exc
        except TimeoutError as exc:
            raise OpenAIError("请求超时，请检查网络或稍后重试") from exc

        try:
            return str(data["choices"][0]["message"]["content"])
        except (KeyError, IndexError, TypeError) as exc:
            raise OpenAIError(f"响应格式异常: {data}") from exc


# ---------------------------------------------------------------------------
# Custom exception
# ---------------------------------------------------------------------------


class OpenAIError(Exception):
    """Raised for API or network errors from OpenAIClient."""
