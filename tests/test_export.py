"""Tests for ledger export command (TES-41)."""

from __future__ import annotations

import csv
import sqlite3
import uuid
from pathlib import Path

import pytest

from our_family_ledger.config import TRANSACTION_HEADERS, init_db


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def tmp_db(tmp_path: Path) -> Path:
    db = tmp_path / "data.db"
    init_db(db)
    return db


def _insert_transaction(db: Path, *, date: str, tx_id: str | None = None) -> str:
    """Insert a minimal transaction row and return its id."""
    tx_id = tx_id or str(uuid.uuid4())
    now = "2024-01-15T10:00:00+00:00"
    conn = sqlite3.connect(db)
    conn.execute(
        """
        INSERT INTO transactions
            (id, created_at, updated_at, date, amount, type, category,
             payer, participants, note, merchant, source, ocr_text, currency)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (tx_id, now, now, date, "99.00", "支出", "餐饮",
         "Alice", "Alice;Bob", "", "", "manual", None, "CNY"),
    )
    conn.commit()
    conn.close()
    return tx_id


def _run_export(month: str, db: Path, output: str | None = None) -> tuple[int, Path]:
    """Invoke export_cmd and return (exit_code, output_path)."""
    from typer.testing import CliRunner
    from our_family_ledger.cli import app

    args = ["export", "--month", month, "--db", str(db)]
    if output:
        args += ["--output", output]
    runner = CliRunner()
    result = runner.invoke(app, args)
    # Derive the output path (default pattern)
    out_path = Path(output) if output else Path.home() / ".our-family-ledger" / "exports" / f"transactions_{month}.csv"
    return result.exit_code, out_path


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_export_correct_month(tmp_db: Path, tmp_path: Path) -> None:
    """Only rows for the requested month are exported."""
    _insert_transaction(tmp_db, date="2024-01-10")
    _insert_transaction(tmp_db, date="2024-01-20")
    _insert_transaction(tmp_db, date="2024-02-05")  # different month

    out = tmp_path / "out.csv"
    code, _ = _run_export("2024-01", tmp_db, str(out))
    assert code == 0

    with open(out, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == 2
    for row in rows:
        assert row["date"].startswith("2024-01")


def test_export_headers_match(tmp_db: Path, tmp_path: Path) -> None:
    """CSV headers must exactly match TRANSACTION_HEADERS."""
    _insert_transaction(tmp_db, date="2024-03-01")
    out = tmp_path / "out.csv"
    code, _ = _run_export("2024-03", tmp_db, str(out))
    assert code == 0

    with open(out, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header_row = next(reader)
    assert header_row == TRANSACTION_HEADERS


def test_export_default_output_path(tmp_db: Path, tmp_path: Path) -> None:
    """When --output is omitted, file lands in ~/.our-family-ledger/exports/."""
    # Use a specific far-future month unlikely to be used by other tests
    month = "2088-11"
    # Clean up any pre-existing file from a prior test run
    out_path = Path.home() / ".our-family-ledger" / "exports" / f"transactions_{month}.csv"
    out_path.unlink(missing_ok=True)

    _insert_transaction(tmp_db, date=f"{month}-15")
    code, returned_path = _run_export(month, tmp_db)
    assert code == 0
    assert out_path.exists()
    # Clean up
    out_path.unlink(missing_ok=True)


def test_export_empty_month(tmp_db: Path, tmp_path: Path) -> None:
    """Exporting a month with no data produces a header-only CSV."""
    out = tmp_path / "empty.csv"
    code, _ = _run_export("2099-12", tmp_db, str(out))
    assert code == 0

    with open(out, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    assert rows == []


def test_export_invalid_month_format(tmp_db: Path, tmp_path: Path) -> None:
    """Invalid --month format should exit with code 1."""
    from typer.testing import CliRunner
    from our_family_ledger.cli import app

    runner = CliRunner()
    for bad in ("2024/01", "24-01", "2024-13", "january"):
        result = runner.invoke(
            app, ["export", "--month", bad, "--db", str(tmp_db)]
        )
        assert result.exit_code == 1, f"Expected exit 1 for {bad!r}"


def test_export_participants_preserved(tmp_db: Path, tmp_path: Path) -> None:
    """participants semicolon string round-trips correctly through export."""
    tx_id = str(uuid.uuid4())
    _insert_transaction(tmp_db, date="2024-05-01", tx_id=tx_id)

    out = tmp_path / "out.csv"
    code, _ = _run_export("2024-05", tmp_db, str(out))
    assert code == 0

    with open(out, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    row = next(r for r in rows if r["id"] == tx_id)
    assert row["participants"] == "Alice;Bob"
