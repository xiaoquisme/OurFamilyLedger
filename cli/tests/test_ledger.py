"""Tests for OurFamilyLedger CLI — DB, CRUD, report, import/export."""

from __future__ import annotations

import csv
import io
import tempfile
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path

import pytest

from our_family_ledger.db import init_db
from our_family_ledger.models import Transaction
from our_family_ledger.repo import TransactionRepository


@pytest.fixture
def tmp_db(tmp_path):
    """Return a fresh in-memory-ish DB in a temp dir."""
    db_path = tmp_path / "test.db"
    conn = init_db(path=str(db_path))
    return conn, str(db_path)


@pytest.fixture
def repo(tmp_db):
    conn, _ = tmp_db
    return TransactionRepository(conn)


def make_tx(**kwargs) -> Transaction:
    defaults = dict(
        date="2026-05-19",
        amount="45.00",
        type="支出",
        category="餐饮",
        payer="我",
        participants="我;老婆",
        note="买菜",
        merchant="",
        currency="CNY",
    )
    defaults.update(kwargs)
    return Transaction(**defaults)


# ---------------------------------------------------------------------------
# DB init
# ---------------------------------------------------------------------------

class TestInitDB:
    def test_creates_all_tables(self, tmp_db):
        conn, _ = tmp_db
        tables = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()}
        assert {"transactions", "members", "categories"}.issubset(tables)

    def test_seeds_categories(self, tmp_db):
        conn, _ = tmp_db
        count = conn.execute("SELECT COUNT(*) FROM categories").fetchone()[0]
        assert count == 37  # 32 expense + 5 income

    def test_idempotent(self, tmp_db):
        conn, db_path = tmp_db
        # Call init_db again on same path
        conn2 = init_db(path=db_path)
        count = conn2.execute("SELECT COUNT(*) FROM categories").fetchone()[0]
        assert count == 37

    def test_wal_mode(self, tmp_db):
        conn, _ = tmp_db
        mode = conn.execute("PRAGMA journal_mode").fetchone()[0]
        assert mode == "wal"


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------

class TestTransactionRepository:
    def test_insert_and_find(self, repo):
        tx = make_tx()
        repo.insert(tx)
        matches = repo.find_by_prefix(tx.id[:8])
        assert len(matches) == 1
        assert matches[0].amount == "45.00"

    def test_query_by_month(self, repo):
        repo.insert(make_tx(date="2026-05-10"))
        repo.insert(make_tx(date="2026-04-10"))
        results = repo.query(month="2026-05")
        assert len(results) == 1
        assert results[0].date == "2026-05-10"

    def test_query_by_category(self, repo):
        repo.insert(make_tx(category="餐饮"))
        repo.insert(make_tx(category="交通"))
        results = repo.query(category="餐饮")
        assert all(r.category == "餐饮" for r in results)

    def test_query_by_payer(self, repo):
        repo.insert(make_tx(payer="我"))
        repo.insert(make_tx(payer="老婆"))
        results = repo.query(payer="我")
        assert all(r.payer == "我" for r in results)

    def test_update(self, repo):
        tx = make_tx()
        repo.insert(tx)
        repo.update(tx.id, amount="99.00", note="修改")
        updated = repo.find_by_prefix(tx.id[:8])[0]
        assert updated.amount == "99.00"
        assert updated.note == "修改"

    def test_delete(self, repo):
        tx = make_tx()
        repo.insert(tx)
        repo.delete(tx.id)
        assert repo.find_by_prefix(tx.id[:8]) == []

    def test_find_by_prefix_ambiguous(self, repo):
        # Two transactions with same prefix (extremely unlikely with uuid but
        # we test the multi-match case by inserting a fixed id)
        tx1 = make_tx()
        tx1.id = "aaaa1111-0000-0000-0000-000000000001"
        tx2 = make_tx()
        tx2.id = "aaaa1111-0000-0000-0000-000000000002"
        repo.insert(tx1)
        repo.insert(tx2)
        matches = repo.find_by_prefix("aaaa1111")
        assert len(matches) == 2


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

class TestReport:
    def test_report_output(self, tmp_db, capsys):
        conn, db_path = tmp_db
        repo = TransactionRepository(conn)
        repo.insert(make_tx(amount="100.00", payer="我", participants="我;老婆"))
        repo.insert(make_tx(amount="50.00", type="收入", category="工资", payer="老婆", participants="老婆"))

        from our_family_ledger.commands.report import report_command
        report_command(month="2026-05", db_path=db_path)
        captured = capsys.readouterr()
        assert "100.00" in captured.out
        assert "50.00" in captured.out

    def test_report_csv(self, tmp_db, capsys):
        conn, db_path = tmp_db
        repo = TransactionRepository(conn)
        repo.insert(make_tx(amount="75.00"))

        from our_family_ledger.commands.report import report_command
        report_command(month="2026-05", csv_output=True, db_path=db_path)
        captured = capsys.readouterr()
        rows = list(csv.reader(io.StringIO(captured.out)))
        assert rows[0] == [
            "id", "created_at", "updated_at", "date", "amount", "type",
            "category", "payer", "participants", "note", "merchant",
            "source", "ocr_text", "currency"
        ]
        assert any("75.00" in row for row in rows)


# ---------------------------------------------------------------------------
# Import / Export
# ---------------------------------------------------------------------------

class TestImportExport:
    def _make_csv(self, rows: list[dict], path: Path) -> None:
        headers = [
            "id", "created_at", "updated_at", "date", "amount", "type",
            "category", "payer", "participants", "note", "merchant",
            "source", "ocr_text", "currency"
        ]
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=headers)
            writer.writeheader()
            for row in rows:
                base = {h: "" for h in headers}
                base.update(row)
                writer.writerow(base)

    def test_import_basic(self, tmp_db, tmp_path):
        conn, db_path = tmp_db
        csv_path = tmp_path / "input.csv"
        tx_id = str(uuid.uuid4())
        self._make_csv([
            {"id": tx_id, "date": "2026-05-01", "amount": "88.00",
             "type": "支出", "category": "餐饮", "currency": "CNY",
             "participants": "我;老婆", "payer": "我"}
        ], csv_path)

        from our_family_ledger.commands.data import import_command
        import_command(file_pattern=str(csv_path), db_path=db_path)

        repo = TransactionRepository(conn)
        matches = repo.find_by_prefix(tx_id[:8])
        assert len(matches) == 1
        assert matches[0].amount == "88.00"

    def test_import_skips_duplicates(self, tmp_db, tmp_path):
        conn, db_path = tmp_db
        csv_path = tmp_path / "dup.csv"
        tx_id = str(uuid.uuid4())
        self._make_csv([
            {"id": tx_id, "date": "2026-05-01", "amount": "10.00",
             "type": "支出", "category": "餐饮", "currency": "CNY"}
        ], csv_path)

        from our_family_ledger.commands.data import import_command
        import_command(file_pattern=str(csv_path), db_path=db_path)
        import_command(file_pattern=str(csv_path), db_path=db_path)  # second time

        repo = TransactionRepository(conn)
        all_rows = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
        assert all_rows == 1

    def test_export_csv(self, tmp_db, tmp_path):
        conn, db_path = tmp_db
        repo = TransactionRepository(conn)
        repo.insert(make_tx(amount="200.00", date="2026-05-15"))

        out_path = str(tmp_path / "out.csv")
        from our_family_ledger.commands.data import export_command
        export_command(month="2026-05", output=out_path, db_path=db_path)

        with open(out_path, newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        assert len(rows) == 1
        assert rows[0]["amount"] == "200.00"

    def test_import_glob(self, tmp_db, tmp_path):
        conn, db_path = tmp_db
        for i in range(3):
            csv_path = tmp_path / f"tx_{i}.csv"
            self._make_csv([
                {"id": str(uuid.uuid4()), "date": "2026-05-01", "amount": f"{i * 10}.00",
                 "type": "支出", "category": "餐饮", "currency": "CNY"}
            ], csv_path)

        from our_family_ledger.commands.data import import_command
        import_command(file_pattern=str(tmp_path / "tx_*.csv"), db_path=db_path)

        count = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
        assert count == 3
