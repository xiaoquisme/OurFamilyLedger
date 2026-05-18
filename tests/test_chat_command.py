"""Integration tests for the ledger chat command (TES-44).

Tests mock OpenAIClient.parse_transaction and simulate y/n/correction input streams.
"""

from __future__ import annotations

from typing import Callable
from unittest.mock import MagicMock, patch

import pytest

from our_family_ledger.ai.openai_client import OpenAIError
from our_family_ledger.ai.prompts import TransactionDraft, extract_json


# ---------------------------------------------------------------------------
# Helpers / fixtures
# ---------------------------------------------------------------------------


def _make_draft(
    amount: float = 45.0,
    category: str = "餐饮",
    payer: str = "我",
    participants: list[str] | None = None,
    note: str = "买菜",
    date: str = "2026-05-18",
    type: str = "expense",
    merchant: str = "",
) -> TransactionDraft:
    return TransactionDraft(
        date=date,
        amount=amount,
        type=type,
        category=category,
        payer=payer,
        participants=participants or ["我", "老婆"],
        note=note,
        merchant=merchant,
    )


# ---------------------------------------------------------------------------
# Unit tests: extract_json (TES-43's JSON parsing function)
# ---------------------------------------------------------------------------


class TestExtractJson:
    def test_bare_json_array(self):
        text = '[{"date":"2026-05-18","amount":45.0,"type":"expense","category":"餐饮","payer":"我","participants":["我","老婆"],"note":"买菜","merchant":""}]'
        result = extract_json(text)
        assert len(result) == 1
        assert result[0]["amount"] == 45.0
        assert result[0]["category"] == "餐饮"

    def test_json_in_markdown_fence(self):
        text = '```json\n[{"date":"2026-05-18","amount":20.0,"type":"expense","category":"交通","payer":"我","participants":[],"note":"地铁","merchant":""}]\n```'
        result = extract_json(text)
        assert len(result) == 1
        assert result[0]["amount"] == 20.0

    def test_single_object_wrapped_in_array(self):
        text = '{"date":"2026-05-18","amount":100.0,"type":"income","category":"其他","payer":"老婆","participants":[],"note":"工资","merchant":""}'
        result = extract_json(text)
        assert len(result) == 1
        assert result[0]["type"] == "income"

    def test_invalid_json_returns_empty(self):
        result = extract_json("这不是JSON")
        assert result == []

    def test_empty_string_returns_empty(self):
        result = extract_json("")
        assert result == []

    def test_multiple_items(self):
        text = '[{"date":"2026-05-18","amount":10.0,"type":"expense","category":"餐饮","payer":"我","participants":[],"note":"a","merchant":""},{"date":"2026-05-18","amount":20.0,"type":"expense","category":"交通","payer":"老婆","participants":[],"note":"b","merchant":""}]'
        result = extract_json(text)
        assert len(result) == 2
        assert result[1]["amount"] == 20.0


# ---------------------------------------------------------------------------
# Unit tests: TransactionDraft.from_dict
# ---------------------------------------------------------------------------


class TestTransactionDraftFromDict:
    def test_basic_from_dict(self):
        d = {
            "date": "2026-05-18",
            "amount": 45.0,
            "type": "expense",
            "category": "餐饮",
            "payer": "我",
            "participants": ["我", "老婆"],
            "note": "买菜",
            "merchant": "",
        }
        draft = TransactionDraft.from_dict(d)
        assert draft.amount == 45.0
        assert draft.category == "餐饮"
        assert draft.participants == ["我", "老婆"]

    def test_participants_as_string_split(self):
        d = {
            "date": "2026-05-18",
            "amount": 10.0,
            "type": "expense",
            "category": "其他",
            "payer": "我",
            "participants": "我, 老婆",
            "note": "x",
            "merchant": "",
        }
        draft = TransactionDraft.from_dict(d)
        assert "我" in draft.participants
        assert "老婆" in draft.participants

    def test_defaults(self):
        d = {"amount": 10.0}
        draft = TransactionDraft.from_dict(d)
        assert draft.type == "expense"
        assert draft.confidence_amount == 1.0


# ---------------------------------------------------------------------------
# Unit tests: AIConfig
# ---------------------------------------------------------------------------


class TestAIConfig:
    def test_from_dict_defaults(self):
        from our_family_ledger.ai.openai_client import AIConfig

        cfg = AIConfig.from_dict({})
        assert cfg.provider == "openai"
        assert cfg.endpoint == "https://api.openai.com/v1"
        assert cfg.model == "gpt-4o-mini"
        assert cfg.api_key == ""

    def test_from_dict_custom(self):
        from our_family_ledger.ai.openai_client import AIConfig

        cfg = AIConfig.from_dict(
            {
                "provider": "anthropic",
                "endpoint": "https://api.anthropic.com/v1",
                "model": "claude-3",
                "api_key": "sk-ant-abc",
            }
        )
        assert cfg.provider == "anthropic"
        assert cfg.api_key == "sk-ant-abc"


# ---------------------------------------------------------------------------
# Unit tests: load_ai_config / save_ai_config
# ---------------------------------------------------------------------------


class TestLoadSaveAIConfig:
    def test_load_empty_config_returns_defaults(self, isolated_data_dir):
        from our_family_ledger.config import load_ai_config

        cfg = load_ai_config()
        assert cfg.provider == "openai"
        assert cfg.api_key == ""

    def test_save_then_load_roundtrip(self, isolated_data_dir):
        from our_family_ledger.ai.openai_client import AIConfig
        from our_family_ledger.config import load_ai_config, save_ai_config

        original = AIConfig(
            provider="openrouter",
            endpoint="https://openrouter.ai/api/v1",
            model="mistral-7b",
            api_key="or-secret-key",
        )
        save_ai_config(original)

        loaded = load_ai_config()
        assert loaded.provider == "openrouter"
        assert loaded.endpoint == "https://openrouter.ai/api/v1"
        assert loaded.model == "mistral-7b"
        assert loaded.api_key == "or-secret-key"

    def test_save_preserves_existing_ledger_section(self, isolated_data_dir):
        from our_family_ledger.ai.openai_client import AIConfig
        from our_family_ledger.config import load_ai_config, read_config, save_ai_config, write_config

        # Pre-populate with a ledger section
        write_config({"ledger": {"currency": "USD", "default_split_all": False}})

        save_ai_config(AIConfig(api_key="testkey"))

        config = read_config()
        assert config["ledger"]["currency"] == "USD"
        assert config["ai"]["api_key"] == "testkey"


# ---------------------------------------------------------------------------
# Integration tests: _run_chat_loop
# ---------------------------------------------------------------------------


class TestChatLoop:
    """Test the REPL loop using mocked OpenAIClient and save_fn."""

    def _make_client(self, side_effects):
        """Build a mock OpenAIClient whose parse_transaction returns side_effects in order."""
        client = MagicMock()
        client.parse_transaction.side_effect = side_effects
        return client

    def test_confirm_y_calls_save_fn(self, isolated_data_dir):
        """Happy path: user describes transaction, confirms with y, save_fn is called."""
        from our_family_ledger.commands.chat import _run_chat_loop

        draft = _make_draft()
        client = self._make_client([[draft]])
        saved: list[TransactionDraft] = []

        # Simulate: user input "买菜45" then confirm "y", then "quit"
        inputs = iter(["今天买菜花了45块", "y", "quit"])
        with patch("typer.prompt", side_effect=inputs):
            _run_chat_loop(client, saved.append)

        assert len(saved) == 1
        assert saved[0].amount == 45.0

    def test_confirm_n_skips_save_fn(self, isolated_data_dir):
        """User declines with n — save_fn should NOT be called."""
        from our_family_ledger.commands.chat import _run_chat_loop

        draft = _make_draft()
        client = self._make_client([[draft]])
        saved: list[TransactionDraft] = []

        inputs = iter(["买东西", "n", "quit"])
        with patch("typer.prompt", side_effect=inputs):
            _run_chat_loop(client, saved.append)

        assert saved == []

    def test_correction_re_parses_then_confirms(self, isolated_data_dir):
        """Multi-round: user types a correction instead of y/n, then confirms."""
        from our_family_ledger.commands.chat import _run_chat_loop

        draft1 = _make_draft(amount=45.0)
        draft2 = _make_draft(amount=50.0, note="买菜+牛奶")

        # First call returns draft1; correction call returns draft2
        client = self._make_client([[draft1], [draft2]])
        saved: list[TransactionDraft] = []

        # "买菜" → draft1 shown; "金额改成50" (correction, >2 chars) → draft2 shown; "y" → saved; "quit"
        inputs = iter(["今天买菜45块", "金额改成50", "y", "quit"])
        with patch("typer.prompt", side_effect=inputs):
            _run_chat_loop(client, saved.append)

        assert len(saved) == 1
        assert saved[0].amount == 50.0

    def test_api_error_does_not_crash_loop(self, isolated_data_dir):
        """If parse_transaction raises OpenAIError, loop continues without crashing."""
        from our_family_ledger.commands.chat import _run_chat_loop

        client = MagicMock()
        client.parse_transaction.side_effect = [OpenAIError("API error"), StopIteration]
        saved: list[TransactionDraft] = []

        inputs = iter(["买东西", "quit"])
        with patch("typer.prompt", side_effect=inputs):
            _run_chat_loop(client, saved.append)

        assert saved == []

    def test_empty_response_does_not_crash(self, isolated_data_dir):
        """If parse_transaction returns empty list, loop shows warning and continues."""
        from our_family_ledger.commands.chat import _run_chat_loop

        client = self._make_client([[]])
        saved: list[TransactionDraft] = []

        inputs = iter(["???", "quit"])
        with patch("typer.prompt", side_effect=inputs):
            _run_chat_loop(client, saved.append)

        assert saved == []

    def test_quit_exits_immediately(self, isolated_data_dir):
        """Typing quit on the first prompt exits without error."""
        from our_family_ledger.commands.chat import _run_chat_loop

        client = MagicMock()
        saved: list[TransactionDraft] = []

        inputs = iter(["quit"])
        with patch("typer.prompt", side_effect=inputs):
            _run_chat_loop(client, saved.append)

        client.parse_transaction.assert_not_called()

    def test_eof_exits_gracefully(self, isolated_data_dir):
        """EOFError on prompt exits gracefully."""
        from our_family_ledger.commands.chat import _run_chat_loop

        client = MagicMock()
        saved: list[TransactionDraft] = []

        with patch("typer.prompt", side_effect=EOFError):
            _run_chat_loop(client, saved.append)

        client.parse_transaction.assert_not_called()


# ---------------------------------------------------------------------------
# Integration tests: CLI `ledger chat` command via CliRunner
# ---------------------------------------------------------------------------


class TestChatCommand:
    def test_chat_command_registered(self, isolated_data_dir):
        """ledger chat --help should be reachable without error."""
        from our_family_ledger.cli import app
        from typer.testing import CliRunner

        runner = CliRunner()
        result = runner.invoke(app, ["chat", "--help"])
        assert result.exit_code == 0

    def test_chat_runs_with_mocked_client(self, isolated_data_dir, monkeypatch):
        """End-to-end CLI test: mock OpenAIClient, simulate y, verify save_fn called."""
        from our_family_ledger.cli import app
        from our_family_ledger.ai.openai_client import AIConfig, OpenAIClient
        from typer.testing import CliRunner

        draft = _make_draft()

        mock_client = MagicMock(spec=OpenAIClient)
        mock_client.parse_transaction.return_value = [draft]

        # Patch OpenAIClient constructor to return our mock
        with patch(
            "our_family_ledger.commands.chat.OpenAIClient",
            return_value=mock_client,
        ):
            # Patch load_ai_config to return a config with api_key set
            with patch(
                "our_family_ledger.commands.chat.load_ai_config",
                return_value=AIConfig(api_key="test-key"),
            ):
                runner = CliRunner()
                # Simulate: describe transaction, confirm y, then quit
                result = runner.invoke(
                    app,
                    ["chat"],
                    input="今天买菜45块\ny\nquit\n",
                )

        # Should not crash
        assert result.exit_code == 0
        assert mock_client.parse_transaction.called

    def test_chat_wizard_when_no_api_key(self, isolated_data_dir, monkeypatch):
        """When api_key is empty, config wizard is triggered."""
        from our_family_ledger.cli import app
        from our_family_ledger.ai.openai_client import AIConfig, OpenAIClient
        from typer.testing import CliRunner

        draft = _make_draft()
        mock_client = MagicMock(spec=OpenAIClient)
        mock_client.parse_transaction.return_value = [draft]

        with patch(
            "our_family_ledger.commands.chat.OpenAIClient",
            return_value=mock_client,
        ):
            with patch(
                "our_family_ledger.commands.chat.load_ai_config",
                return_value=AIConfig(api_key=""),  # empty → wizard
            ):
                with patch(
                    "our_family_ledger.commands.chat.save_ai_config",
                ):
                    runner = CliRunner()
                    # Wizard prompts: provider, endpoint, model, api_key, then chat, then quit
                    result = runner.invoke(
                        app,
                        ["chat"],
                        input="openai\nhttps://api.openai.com/v1\ngpt-4o-mini\nsk-test\nquit\n",
                    )

        # Should not crash
        assert result.exit_code == 0

    def test_y_confirm_inserts_transaction(self, isolated_data_dir, monkeypatch):
        """DB integration: confirming y writes a real row to SQLite transactions table."""
        import sqlite3
        from our_family_ledger.cli import app
        from our_family_ledger.ai.openai_client import AIConfig, OpenAIClient
        import our_family_ledger.config as cfg
        from typer.testing import CliRunner

        draft = _make_draft(amount=45.0, category="餐饮", payer="我", note="买菜")

        mock_client = MagicMock(spec=OpenAIClient)
        mock_client.parse_transaction.return_value = [draft]

        with patch(
            "our_family_ledger.commands.chat.OpenAIClient",
            return_value=mock_client,
        ):
            with patch(
                "our_family_ledger.commands.chat.load_ai_config",
                return_value=AIConfig(api_key="test-key"),
            ):
                runner = CliRunner()
                result = runner.invoke(
                    app,
                    ["chat"],
                    input="今天买菜45块\ny\nquit\n",
                )

        assert result.exit_code == 0

        # Verify the transaction was actually written to DB
        conn = sqlite3.connect(str(cfg.DB_FILE))
        rows = conn.execute("SELECT * FROM transactions").fetchall()
        conn.close()

        assert len(rows) == 1
        row = rows[0]
        assert row[4] == "45.0"   # amount column (index 4)
        assert row[5] == "支出"    # type column (index 5)
        assert row[6] == "餐饮"    # category column (index 6)


# ---------------------------------------------------------------------------
# Reuse isolated_data_dir fixture
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def isolated_data_dir(tmp_path, monkeypatch):
    """Redirect config globals to a temp dir."""
    import our_family_ledger.config as cfg

    data_dir = tmp_path / ".our-family-ledger"
    data_dir.mkdir()
    db_file = data_dir / "data.db"
    config_file = data_dir / "config.toml"

    monkeypatch.setattr(cfg, "DATA_DIR", data_dir)
    monkeypatch.setattr(cfg, "DB_FILE", db_file)
    monkeypatch.setattr(cfg, "CONFIG_FILE", config_file)

    cfg.init_db(db_file)
    return data_dir
