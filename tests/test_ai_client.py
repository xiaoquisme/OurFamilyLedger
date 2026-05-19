"""Unit tests for ledger/ai — OpenAI client and JSON parsing.

All HTTP calls are mocked; no real API key required.
"""

from __future__ import annotations

import json
import urllib.error
from io import BytesIO
from unittest.mock import MagicMock, patch

import pytest

from our_family_ledger.ai.openai_client import AIConfig, OpenAIClient, OpenAIError
from our_family_ledger.ai.prompts import (
    SYSTEM_PROMPT,
    TransactionDraft,
    extract_json,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def config() -> AIConfig:
    return AIConfig(
        endpoint="https://api.openai.com/v1",
        model="gpt-4o-mini",
        api_key="sk-test",
    )


@pytest.fixture()
def client(config: AIConfig) -> OpenAIClient:
    return OpenAIClient(config)


def _make_response(content: str, status: int = 200) -> MagicMock:
    """Build a mock urllib response object."""
    body = json.dumps({
        "choices": [{"message": {"content": content, "role": "assistant"}}]
    }).encode()
    mock_resp = MagicMock()
    mock_resp.read.return_value = body
    mock_resp.status = status
    mock_resp.__enter__ = lambda s: s
    mock_resp.__exit__ = MagicMock(return_value=False)
    return mock_resp


# ---------------------------------------------------------------------------
# extract_json — multi-format parsing
# ---------------------------------------------------------------------------


class TestExtractJson:
    """Validate JSON extraction from various LLM output formats."""

    def test_plain_array(self):
        raw = '[{"date":"2024-01-01","amount":45.0,"type":"expense","category":"餐饮","payer":"我","participants":["我","老婆"],"note":"买菜","merchant":"","confidence_amount":0.9,"confidence_date":0.8}]'
        result = extract_json(raw)
        assert len(result) == 1
        assert result[0]["amount"] == 45.0

    def test_markdown_json_fence(self):
        raw = '```json\n[{"date":"2024-01-01","amount":20.0,"type":"expense","category":"交通","payer":"我","participants":["我"],"note":"","merchant":"","confidence_amount":1.0,"confidence_date":1.0}]\n```'
        result = extract_json(raw)
        assert len(result) == 1
        assert result[0]["category"] == "交通"

    def test_markdown_plain_fence(self):
        raw = '```\n[{"date":"2024-01-02","amount":100.0,"type":"income","category":"工资","payer":"公司","participants":["我"],"note":"","merchant":"","confidence_amount":1.0,"confidence_date":1.0}]\n```'
        result = extract_json(raw)
        assert len(result) == 1
        assert result[0]["type"] == "income"

    def test_single_object_wrapped(self):
        raw = '{"date":"2024-01-01","amount":30.0,"type":"expense","category":"购物","payer":"老婆","participants":["老婆","我"],"note":"","merchant":"","confidence_amount":0.8,"confidence_date":0.9}'
        result = extract_json(raw)
        assert len(result) == 1
        assert result[0]["payer"] == "老婆"

    def test_array_with_preamble(self):
        raw = 'Sure, here is the result:\n[{"date":"2024-01-01","amount":50.0,"type":"expense","category":"餐饮","payer":"我","participants":["我"],"note":"","merchant":"","confidence_amount":0.9,"confidence_date":0.9}]'
        result = extract_json(raw)
        assert len(result) == 1
        assert result[0]["amount"] == 50.0

    def test_multiple_transactions(self):
        raw = json.dumps([
            {"date": "2024-01-01", "amount": 45.0, "type": "expense", "category": "餐饮", "payer": "我", "participants": ["我"], "note": "", "merchant": "", "confidence_amount": 0.9, "confidence_date": 0.9},
            {"date": "2024-01-01", "amount": 20.0, "type": "expense", "category": "交通", "payer": "老婆", "participants": ["老婆"], "note": "", "merchant": "", "confidence_amount": 1.0, "confidence_date": 1.0},
        ])
        result = extract_json(raw)
        assert len(result) == 2

    def test_empty_string_returns_empty(self):
        assert extract_json("") == []

    def test_invalid_json_returns_empty(self):
        assert extract_json("not json at all") == []


# ---------------------------------------------------------------------------
# TransactionDraft.from_dict
# ---------------------------------------------------------------------------


class TestTransactionDraftFromDict:
    def test_basic(self):
        d = {
            "date": "2024-03-15",
            "amount": 45.0,
            "type": "expense",
            "category": "餐饮",
            "payer": "我",
            "participants": ["我", "老婆"],
            "note": "买菜",
            "merchant": "超市",
            "confidence_amount": 0.9,
            "confidence_date": 0.8,
        }
        draft = TransactionDraft.from_dict(d)
        assert draft.date == "2024-03-15"
        assert draft.amount == 45.0
        assert draft.type == "expense"
        assert draft.payer == "我"
        assert draft.participants == ["我", "老婆"]
        assert draft.confidence_amount == 0.9

    def test_participants_as_comma_string(self):
        d = {
            "date": "2024-01-01",
            "amount": 10.0,
            "type": "expense",
            "category": "其他",
            "payer": "我",
            "participants": "我, 老婆",
            "note": "",
            "merchant": "",
            "confidence_amount": 1.0,
            "confidence_date": 1.0,
        }
        draft = TransactionDraft.from_dict(d)
        assert draft.participants == ["我", "老婆"]

    def test_missing_optional_fields_use_defaults(self):
        d = {"date": "2024-01-01", "amount": 5.0, "type": "expense", "category": "其他", "payer": "我"}
        draft = TransactionDraft.from_dict(d)
        assert draft.note == ""
        assert draft.merchant == ""
        assert draft.confidence_amount == 1.0


# ---------------------------------------------------------------------------
# OpenAIClient.parse_transaction — happy path
# ---------------------------------------------------------------------------


class TestOpenAIClientParseTransaction:
    def test_returns_drafts_on_success(self, client: OpenAIClient):
        response_json = json.dumps([{
            "date": "2024-05-18",
            "amount": 45.0,
            "type": "expense",
            "category": "餐饮",
            "payer": "我",
            "participants": ["我", "老婆"],
            "note": "买菜",
            "merchant": "菜市场",
            "confidence_amount": 0.95,
            "confidence_date": 0.9,
        }])

        with patch("urllib.request.urlopen", return_value=_make_response(response_json)):
            messages = [{"role": "user", "content": "今天买菜花了45块，我付的，老婆和我均摊"}]
            drafts = client.parse_transaction(messages)

        assert len(drafts) == 1
        d = drafts[0]
        assert d.amount == 45.0
        assert d.category == "餐饮"
        assert d.payer == "我"
        assert "老婆" in d.participants

    def test_system_prompt_prepended_automatically(self, client: OpenAIClient):
        """System prompt is inserted as the first message if absent."""
        captured: list = []

        def fake_urlopen(req, timeout=None):
            body = json.loads(req.data.decode())
            captured.extend(body["messages"])
            return _make_response("[]")

        with patch("urllib.request.urlopen", side_effect=fake_urlopen):
            client.parse_transaction([{"role": "user", "content": "测试"}])

        assert captured[0]["role"] == "system"
        assert "家庭记账助手" in captured[0]["content"]

    def test_system_prompt_not_duplicated(self, client: OpenAIClient):
        """If caller already includes system message, it is not duplicated."""
        captured: list = []

        def fake_urlopen(req, timeout=None):
            body = json.loads(req.data.decode())
            captured.extend(body["messages"])
            return _make_response("[]")

        messages = [
            {"role": "system", "content": "custom system"},
            {"role": "user", "content": "hi"},
        ]
        with patch("urllib.request.urlopen", side_effect=fake_urlopen):
            client.parse_transaction(messages)

        system_msgs = [m for m in captured if m["role"] == "system"]
        assert len(system_msgs) == 1
        assert system_msgs[0]["content"] == "custom system"

    def test_markdown_wrapped_response(self, client: OpenAIClient):
        response = '```json\n[{"date":"2024-01-01","amount":20.0,"type":"expense","category":"交通","payer":"我","participants":["我"],"note":"","merchant":"","confidence_amount":1.0,"confidence_date":1.0}]\n```'
        with patch("urllib.request.urlopen", return_value=_make_response(response)):
            drafts = client.parse_transaction([{"role": "user", "content": "打车20块"}])
        assert len(drafts) == 1
        assert drafts[0].amount == 20.0

    def test_empty_response_returns_empty_list(self, client: OpenAIClient):
        with patch("urllib.request.urlopen", return_value=_make_response("[]")):
            drafts = client.parse_transaction([{"role": "user", "content": ""}])
        assert drafts == []


# ---------------------------------------------------------------------------
# OpenAIClient — error handling
# ---------------------------------------------------------------------------


class TestOpenAIClientErrors:
    def _make_http_error(self, code: int, message: str) -> urllib.error.HTTPError:
        body = json.dumps({"error": {"message": message}}).encode()
        return urllib.error.HTTPError(
            url="https://api.openai.com/v1/chat/completions",
            code=code,
            msg=message,
            hdrs=None,  # type: ignore[arg-type]
            fp=BytesIO(body),
        )

    def test_401_raises_openai_error(self, client: OpenAIClient):
        err = self._make_http_error(401, "Invalid API key")
        with patch("urllib.request.urlopen", side_effect=err):
            with pytest.raises(OpenAIError, match="401"):
                client.parse_transaction([{"role": "user", "content": "x"}])

    def test_429_raises_openai_error(self, client: OpenAIClient):
        err = self._make_http_error(429, "Rate limit exceeded")
        with patch("urllib.request.urlopen", side_effect=err):
            with pytest.raises(OpenAIError, match="429"):
                client.parse_transaction([{"role": "user", "content": "x"}])

    def test_network_error_raises_openai_error(self, client: OpenAIClient):
        import socket
        url_err = urllib.error.URLError(reason="Connection refused")
        with patch("urllib.request.urlopen", side_effect=url_err):
            with pytest.raises(OpenAIError, match="网络连接失败"):
                client.parse_transaction([{"role": "user", "content": "x"}])

    def test_bearer_token_in_request_header(self, client: OpenAIClient):
        """Verify Authorization header uses Bearer scheme."""
        captured_req: list = []

        def fake_urlopen(req, timeout=None):
            captured_req.append(req)
            return _make_response("[]")

        with patch("urllib.request.urlopen", side_effect=fake_urlopen):
            client.parse_transaction([{"role": "user", "content": "test"}])

        auth = captured_req[0].get_header("Authorization")
        assert auth == "Bearer sk-test"


# ---------------------------------------------------------------------------
# AIConfig.from_dict
# ---------------------------------------------------------------------------


class TestAIConfig:
    def test_defaults(self):
        cfg = AIConfig.from_dict({})
        assert cfg.endpoint == "https://api.openai.com/v1"
        assert cfg.model == "gpt-4o-mini"
        assert cfg.api_key == ""

    def test_custom_values(self):
        cfg = AIConfig.from_dict({
            "endpoint": "https://my.llm.host/v1",
            "model": "llama-3.1-70b",
            "api_key": "tok-abc",
            "provider": "custom",
        })
        assert cfg.endpoint == "https://my.llm.host/v1"
        assert cfg.model == "llama-3.1-70b"
        assert cfg.api_key == "tok-abc"
        assert cfg.provider == "custom"
