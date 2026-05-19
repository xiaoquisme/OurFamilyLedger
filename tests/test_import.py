"""Tests for ledger import command (TES-41)."""

from __future__ import annotations

import csv
import sqlite3
import tempfile
import uuid
from pathlib import Path

import pytest

from our_family_ledger.config import TRANSACTION_HEADERS, init_db


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def tmp_db(tmp_path: Path) -> Path:
    """Return path to an initialised temporary SQLite DB."""
    db = tmp_path / "data.db"
    init_db(db)
    return db


def _make_row(
    *,
    tx_id: str | None = None,
    date: str = "2024-01-15",
    amount: str = "100.00",
    tx_type: str = "支出",
    category: str = "餐饮",
    payer: str = "Alice",
    participants: str = "Alice;Bob",
    note: str = "",
    merchant: str = "",
    source: str = "manual",
    ocr_text: str = "",
    currency: str = "CNY",
) -> dict:
    """Build a CSV row dict compatible with TRANSACTION_HEADERS."""
    now = "2024-01-15T10:00:00+00:00"
    return {
        "id": tx_id or str(uuid.uuid4()),
        "created_at": now,
        "updated_at": now,
        "date": date,
        "amount": amount,
        "type": tx_type,
        "category": category,
        "payer": payer,
        "participants": participants,
        "note": note,
        "merchant": merchant,
        "source": source,
        "ocr_text": ocr_text,
        "currency": currency,
    }


def _write_csv(path: Path, rows: list[dict], headers: list[str] | None = None) -> None:
    headers = headers or TRANSACTION_HEADERS
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=headers, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


# ---------------------------------------------------------------------------
# Helper to invoke import_cmd directly
# ---------------------------------------------------------------------------


def _run_import(file_pattern: str, db: Path) -> None:
    from our_family_ledger.commands.import_cmd import import_cmd
    from typer.testing import CliRunner
    from our_family_ledger.cli import app

    runner = CliRunner()
    result = runner.invoke(app, ["import", "--file", file_pattern, "--db", str(db)])
    assert result.exit_code == 0, result.output


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_import_normal(tmp_db: Path, tmp_path: Path) -> None:
    """Happy path: import rows from a CSV and verify they land in DB."""
    csv_path = tmp_path / "transactions_2024-01.csv"
    rows = [_make_row(tx_id=str(uuid.uuid4())) for _ in range(5)]
    _write_csv(csv_path, rows)

    _run_import(str(csv_path), tmp_db)

    conn = sqlite3.connect(tmp_db)
    count = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
    conn.close()
    assert count == 5


def test_import_duplicate_skip(tmp_db: Path, tmp_path: Path) -> None:
    """Duplicate ids are skipped; count reflects actual inserts."""
    fixed_id = str(uuid.uuid4())
    rows = [_make_row(tx_id=fixed_id), _make_row(tx_id=str(uuid.uuid4()))]
    csv_path = tmp_path / "transactions.csv"
    _write_csv(csv_path, rows)

    # First import — both inserted
    _run_import(str(csv_path), tmp_db)

    # Second import with same file — fixed_id should be skipped
    _run_import(str(csv_path), tmp_db)

    conn = sqlite3.connect(tmp_db)
    count = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
    conn.close()
    # Still only 2 unique rows
    assert count == 2


def test_import_glob_multiple_files(tmp_db: Path, tmp_path: Path) -> None:
    """Glob pattern imports from multiple files."""
    ids_jan = [str(uuid.uuid4()) for _ in range(3)]
    ids_feb = [str(uuid.uuid4()) for _ in range(2)]

    _write_csv(tmp_path / "transactions_2024-01.csv", [_make_row(tx_id=i) for i in ids_jan])
    _write_csv(tmp_path / "transactions_2024-02.csv", [_make_row(tx_id=i) for i in ids_feb])

    _run_import(str(tmp_path / "transactions_2024-*.csv"), tmp_db)

    conn = sqlite3.connect(tmp_db)
    count = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
    conn.close()
    assert count == 5


def test_import_missing_required_column(tmp_db: Path, tmp_path: Path) -> None:
    """CSV missing required column should be skipped without crashing."""
    bad_headers = [h for h in TRANSACTION_HEADERS if h != "amount"]
    csv_path = tmp_path / "bad.csv"
    row = _make_row()
    _write_csv(csv_path, [row], headers=bad_headers)

    from typer.testing import CliRunner
    from our_family_ledger.cli import app

    runner = CliRunner()
    result = runner.invoke(app, ["import", "--file", str(csv_path), "--db", str(tmp_db)])
    # Exit code 0 (graceful skip), DB empty
    assert result.exit_code == 0
    conn = sqlite3.connect(tmp_db)
    count = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
    conn.close()
    assert count == 0


def test_import_no_matching_files(tmp_db: Path, tmp_path: Path) -> None:
    """Non-existent glob pattern exits with error code 1."""
    from typer.testing import CliRunner
    from our_family_ledger.cli import app

    runner = CliRunner()
    result = runner.invoke(
        app, ["import", "--file", str(tmp_path / "no_such_*.csv"), "--db", str(tmp_db)]
    )
    assert result.exit_code == 1


def test_import_participants_raw_string(tmp_db: Path, tmp_path: Path) -> None:
    """participants semicolon-separated value is stored as-is."""
    tx_id = str(uuid.uuid4())
    row = _make_row(tx_id=tx_id, participants="Alice;Bob;Charlie")
    csv_path = tmp_path / "transactions.csv"
    _write_csv(csv_path, [row])

    _run_import(str(csv_path), tmp_db)

    conn = sqlite3.connect(tmp_db)
    conn.row_factory = sqlite3.Row
    result = conn.execute("SELECT participants FROM transactions WHERE id = ?", (tx_id,)).fetchone()
    conn.close()
    assert result["participants"] == "Alice;Bob;Charlie"
