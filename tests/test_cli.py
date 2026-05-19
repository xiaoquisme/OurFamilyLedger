"""Tests for our_family_ledger CLI."""

from __future__ import annotations

import sqlite3
import os
from pathlib import Path

import pytest
from typer.testing import CliRunner


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def isolated_data_dir(tmp_path, monkeypatch):
    """
    Redirect all config module globals to a temp directory so tests never
    touch the real ~/.our-family-ledger/.
    """
    import our_family_ledger.config as cfg

    data_dir = tmp_path / ".our-family-ledger"
    data_dir.mkdir()
    db_file = data_dir / "data.db"
    config_file = data_dir / "config.toml"

    monkeypatch.setattr(cfg, "DATA_DIR", data_dir)
    monkeypatch.setattr(cfg, "DB_FILE", db_file)
    monkeypatch.setattr(cfg, "CONFIG_FILE", config_file)

    # Initialise DB with the patched paths
    cfg.init_db(db_file)

    return data_dir


# ---------------------------------------------------------------------------
# config.py tests
# ---------------------------------------------------------------------------


class TestEnsureInitialized:
    def test_creates_data_dir(self, isolated_data_dir):
        assert isolated_data_dir.exists()

    def test_creates_db_file(self, isolated_data_dir):
        import our_family_ledger.config as cfg
        assert cfg.DB_FILE.exists()

    def test_creates_members_table(self, isolated_data_dir):
        import our_family_ledger.config as cfg
        conn = sqlite3.connect(cfg.DB_FILE)
        rows = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='members'"
        ).fetchall()
        conn.close()
        assert rows, "members table should exist"

    def test_idempotent(self, isolated_data_dir):
        """Calling ensure_initialized twice should not raise."""
        import our_family_ledger.config as cfg
        cfg.ensure_initialized()  # second call
        assert cfg.DB_FILE.exists()


class TestWriteReadConfig:
    def test_roundtrip(self, isolated_data_dir):
        import our_family_ledger.config as cfg

        data = {
            "ai": {"provider": "openai", "model": "gpt-4o-mini", "api_key": "tok123", "endpoint": "https://x"},
            "ledger": {"currency": "CNY", "default_split_all": True},
        }
        cfg.write_config(data)
        result = cfg.read_config()
        assert result["ai"]["provider"] == "openai"
        assert result["ai"]["api_key"] == "tok123"
        assert result["ledger"]["currency"] == "CNY"
        assert result["ledger"]["default_split_all"] is True

    def test_read_missing_returns_empty(self, isolated_data_dir):
        import our_family_ledger.config as cfg
        # CONFIG_FILE doesn't exist yet in fresh tmp dir
        assert cfg.read_config() == {}


# ---------------------------------------------------------------------------
# members commands tests
# ---------------------------------------------------------------------------


class TestMembersAdd:
    def test_add_member_basic(self):
        from our_family_ledger.cli import app
        runner = CliRunner()
        result = runner.invoke(app, ["members", "add", "小明"])
        assert result.exit_code == 0, result.output
        assert "小明" in result.output

    def test_add_member_with_options(self):
        from our_family_ledger.cli import app
        runner = CliRunner()
        result = runner.invoke(
            app, ["members", "add", "小红", "--nickname", "红红", "--role", "admin", "--color", "red"]
        )
        assert result.exit_code == 0, result.output
        assert "小红" in result.output

    def test_add_member_invalid_role(self):
        from our_family_ledger.cli import app
        runner = CliRunner()
        result = runner.invoke(app, ["members", "add", "测试", "--role", "superadmin"])
        assert result.exit_code != 0

    def test_add_member_invalid_color(self):
        from our_family_ledger.cli import app
        runner = CliRunner()
        result = runner.invoke(app, ["members", "add", "测试", "--color", "rainbow"])
        assert result.exit_code != 0


class TestMembersList:
    def test_list_empty(self):
        from our_family_ledger.cli import app
        runner = CliRunner()
        result = runner.invoke(app, ["members", "list"])
        assert result.exit_code == 0, result.output
        assert "暂无成员" in result.output

    def test_list_shows_added_member(self):
        from our_family_ledger.cli import app
        runner = CliRunner()
        runner.invoke(app, ["members", "add", "张三"])
        result = runner.invoke(app, ["members", "list"])
        assert result.exit_code == 0, result.output
        assert "张三" in result.output

    def test_nickname_defaults_to_name(self):
        """When no nickname given, nickname should equal name."""
        import our_family_ledger.config as cfg
        from our_family_ledger.cli import app

        runner = CliRunner()
        runner.invoke(app, ["members", "add", "李四"])
        conn = cfg.get_connection()
        row = conn.execute("SELECT nickname FROM members WHERE name='李四'").fetchone()
        conn.close()
        assert row["nickname"] == "李四"


class TestMembersRemove:
    def test_remove_by_name(self):
        from our_family_ledger.cli import app
        runner = CliRunner()
        runner.invoke(app, ["members", "add", "王五"])
        result = runner.invoke(app, ["members", "remove", "王五"])
        assert result.exit_code == 0, result.output
        assert "王五" in result.output

        list_result = runner.invoke(app, ["members", "list"])
        assert "王五" not in list_result.output

    def test_remove_nonexistent(self):
        from our_family_ledger.cli import app
        runner = CliRunner()
        result = runner.invoke(app, ["members", "remove", "不存在的人"])
        assert result.exit_code != 0


# ---------------------------------------------------------------------------
# setup command tests
# ---------------------------------------------------------------------------


class TestSetup:
    def test_non_interactive_writes_config(self, monkeypatch):
        import our_family_ledger.config as cfg
        from our_family_ledger.cli import app

        monkeypatch.setenv("LEDGER_PROVIDER", "anthropic")
        monkeypatch.setenv("LEDGER_MODEL", "claude-3-opus")
        monkeypatch.setenv("LEDGER_API_KEY", "mykey999")
        monkeypatch.setenv("LEDGER_ENDPOINT", "https://api.anthropic.com/v1")
        monkeypatch.setenv("LEDGER_CURRENCY", "USD")

        runner = CliRunner()
        result = runner.invoke(app, ["setup", "--non-interactive"])
        assert result.exit_code == 0, result.output

        config = cfg.read_config()
        assert config["ai"]["provider"] == "anthropic"
        assert config["ai"]["api_key"] == "mykey999"
        assert config["ledger"]["currency"] == "USD"

    def test_non_interactive_defaults(self, monkeypatch):
        """Without env vars, should use defaults without crashing."""
        from our_family_ledger.cli import app

        for k in ("LEDGER_PROVIDER", "LEDGER_MODEL", "LEDGER_API_KEY", "LEDGER_ENDPOINT", "LEDGER_CURRENCY"):
            monkeypatch.delenv(k, raising=False)

        runner = CliRunner()
        result = runner.invoke(app, ["setup", "--non-interactive"])
        assert result.exit_code == 0, result.output
