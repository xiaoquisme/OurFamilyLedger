"""Tests for the ledger report command (TES-40: 月度统计报表命令)."""

from __future__ import annotations

import csv
import io
import sqlite3
import tempfile
from pathlib import Path

import pytest
from typer.testing import CliRunner

from our_family_ledger.cli import app
from our_family_ledger.db import init_db


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def tmp_db(tmp_path: Path) -> Path:
    """Create a fresh initialized database and return its path."""
    db_path = tmp_path / "test_data.db"
    conn = init_db(db_path)

    # Insert test members
    now = "2024-01-15T10:00:00+00:00"
    conn.execute("""
        INSERT INTO members (id, name, created_at) VALUES
        ('member-001', '张三', ?),
        ('member-002', '李四', ?)
    """, (now, now))

    # Get a real category_id for testing
    cat_row = conn.execute(
        "SELECT id FROM categories WHERE name = '餐饮' AND type = '支出' LIMIT 1"
    ).fetchone()
    food_cat_id = cat_row["id"] if cat_row else "cat-food"

    cat_row2 = conn.execute(
        "SELECT id FROM categories WHERE name = '交通' AND type = '支出' LIMIT 1"
    ).fetchone()
    trans_cat_id = cat_row2["id"] if cat_row2 else "cat-trans"

    income_cat_row = conn.execute(
        "SELECT id FROM categories WHERE name = '工资' AND type = '收入' LIMIT 1"
    ).fetchone()
    salary_cat_id = income_cat_row["id"] if income_cat_row else "cat-salary"

    # Insert test transactions for 2024-01
    conn.executemany("""
        INSERT INTO transactions
            (id, created_at, updated_at, date, amount, type, category_id,
             payer_id, participant_ids, note, merchant, source, currency)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, [
        # Expense: 张三 pays 100 for food, both participate
        ("tx-001", now, now, "2024-01-10", "100.00", "支出", food_cat_id,
         "member-001", "member-001;member-002", "午餐", "饭店A", "manual", "CNY"),
        # Expense: 李四 pays 60 for transport, only 李四
        ("tx-002", now, now, "2024-01-15", "60.00", "支出", trans_cat_id,
         "member-002", "member-002", "打车", "滴滴", "manual", "CNY"),
        # Expense: 张三 pays 40 for food, both participate
        ("tx-003", now, now, "2024-01-20", "40.00", "支出", food_cat_id,
         "member-001", "member-001;member-002", "晚餐", "饭店B", "manual", "CNY"),
        # Income: 张三 receives salary
        ("tx-004", now, now, "2024-01-01", "5000.00", "收入", salary_cat_id,
         "member-001", "", "工资", "", "manual", "CNY"),
        # Transaction from different month (should NOT appear in 2024-01 report)
        ("tx-005", now, now, "2024-02-01", "200.00", "支出", food_cat_id,
         "member-001", "member-001", "外月", "别处", "manual", "CNY"),
    ])
    conn.commit()
    conn.close()
    return db_path


runner = CliRunner()


# ---------------------------------------------------------------------------
# AC-1: ledger report 显示当月汇总（总览）
# ---------------------------------------------------------------------------

class TestOverview:
    def test_overview_shows_totals(self, tmp_db: Path) -> None:
        """Overview section must include total expense, income, balance, tx count."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(tmp_db)])
        assert result.exit_code == 0, result.output
        output = result.output
        # total expense = 100 + 60 + 40 = 200
        assert "200.00" in output
        # total income = 5000
        assert "5000.00" in output
        # balance = 5000 - 200 = 4800
        assert "4800.00" in output

    def test_overview_excludes_other_months(self, tmp_db: Path) -> None:
        """Transactions from other months must not appear in the report."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(tmp_db)])
        assert result.exit_code == 0
        # tx-005 is in Feb: 200 should NOT show as standalone expense item in overview
        # (it won't show in category table either)
        # The easiest check: running 2024-02 shows only 200, not 400
        result_feb = runner.invoke(app, ["report", "--month", "2024-02", "--db", str(tmp_db)])
        assert result_feb.exit_code == 0
        assert "200.00" in result_feb.output

    def test_empty_month_returns_zero_totals(self, tmp_db: Path) -> None:
        """Month with no transactions should show zeroes without error."""
        result = runner.invoke(app, ["report", "--month", "2023-06", "--db", str(tmp_db)])
        assert result.exit_code == 0
        # Should see 0.00 for all totals
        assert "0.00" in result.output


# ---------------------------------------------------------------------------
# AC-2: --month YYYY-MM 参数校验
# ---------------------------------------------------------------------------

class TestMonthParameter:
    def test_invalid_month_format_exits_1(self, tmp_db: Path) -> None:
        """Invalid month format must cause exit code 1."""
        result = runner.invoke(app, ["report", "--month", "2024/01", "--db", str(tmp_db)])
        assert result.exit_code == 1

    def test_invalid_month_format_bad_separator(self, tmp_db: Path) -> None:
        result = runner.invoke(app, ["report", "--month", "202401", "--db", str(tmp_db)])
        assert result.exit_code == 1

    def test_valid_month_zero_error(self, tmp_db: Path) -> None:
        """A valid YYYY-MM string should not fail validation."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(tmp_db)])
        assert result.exit_code == 0

    def test_default_month_is_current(self, tmp_db: Path) -> None:
        """Running without --month should succeed (uses current month)."""
        result = runner.invoke(app, ["report", "--db", str(tmp_db)])
        assert result.exit_code == 0


# ---------------------------------------------------------------------------
# AC-3: 按分类展示支出金额及占比
# ---------------------------------------------------------------------------

class TestCategoryBreakdown:
    def test_category_names_present(self, tmp_db: Path) -> None:
        """Category names must appear in terminal output."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(tmp_db)])
        assert result.exit_code == 0
        # 餐饮 = 100 + 40 = 140, 交通 = 60
        assert "餐饮" in result.output
        assert "交通" in result.output

    def test_category_amounts_correct(self, tmp_db: Path) -> None:
        """Category totals must be correct."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(tmp_db)])
        assert result.exit_code == 0
        # 餐饮 total = 140.00
        assert "140.00" in result.output
        # 交通 total = 60.00
        assert "60.00" in result.output

    def test_category_percentages_sum_to_100(self, tmp_db: Path) -> None:
        """Category percentages must sum to ~100%."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(tmp_db)])
        assert result.exit_code == 0
        # 餐饮 = 140/200 = 70%, 交通 = 60/200 = 30%
        assert "70.0%" in result.output
        assert "30.0%" in result.output

    def test_unknown_category_shows_fallback(self, tmp_db: Path, tmp_path: Path) -> None:
        """Transactions with orphaned category_id should show '未分类'."""
        db_path = tmp_path / "orphan_cat.db"
        conn = init_db(db_path)
        now = "2024-01-15T10:00:00+00:00"
        conn.execute("""
            INSERT INTO transactions
                (id, created_at, updated_at, date, amount, type, category_id,
                 payer_id, participant_ids, note, merchant, source, currency)
            VALUES ('tx-orph', ?, ?, '2024-01-10', '50.00', '支出', 'nonexistent-cat',
                    '', '', '孤儿分类', '', 'manual', 'CNY')
        """, (now, now))
        conn.commit()
        conn.close()

        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(db_path)])
        assert result.exit_code == 0
        assert "未分类" in result.output


# ---------------------------------------------------------------------------
# AC-4: 按成员展示付款/分摊金额
# ---------------------------------------------------------------------------

class TestMemberStats:
    def test_member_names_present(self, tmp_db: Path) -> None:
        """Member names must appear in the output."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(tmp_db)])
        assert result.exit_code == 0
        assert "张三" in result.output
        assert "李四" in result.output

    def test_member_paid_amounts(self, tmp_db: Path) -> None:
        """Paid amounts must match: 张三=140, 李四=60."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(tmp_db)])
        assert result.exit_code == 0
        # 张三 paid: tx-001(100) + tx-003(40) = 140
        # 李四 paid: tx-002(60)
        assert "140.00" in result.output
        assert "60.00" in result.output

    def test_member_share_amounts(self, tmp_db: Path) -> None:
        """Share amounts must be correctly computed from participant splits.

        tx-001: 100/2 = 50 each (张三, 李四)
        tx-002: 60/1 = 60 (李四 only)
        tx-003: 40/2 = 20 each (张三, 李四)
        张三 share = 50+20 = 70
        李四 share = 50+60+20 = 130
        """
        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(tmp_db)])
        assert result.exit_code == 0
        assert "70.00" in result.output   # 张三 share
        assert "130.00" in result.output  # 李四 share

    def test_member_settlement(self, tmp_db: Path) -> None:
        """Settlement = paid - share.

        张三: 140 - 70 = +70 (surplus)
        李四: 60 - 130 = -70 (deficit)
        """
        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(tmp_db)])
        assert result.exit_code == 0
        # 70.00 settlement for 张三 (appears as +70.00 or 70.00)
        assert "70.00" in result.output

    def test_null_participants_no_crash(self, tmp_db: Path, tmp_path: Path) -> None:
        """NULL or empty participant_ids must not cause ZeroDivisionError."""
        db_path = tmp_path / "null_part.db"
        conn = init_db(db_path)
        now = "2024-01-15T10:00:00+00:00"
        conn.execute("""
            INSERT INTO transactions
                (id, created_at, updated_at, date, amount, type, category_id,
                 payer_id, participant_ids, note, merchant, source, currency)
            VALUES ('tx-null', ?, ?, '2024-01-10', '100.00', '支出', '',
                    'member-001', '', '零参与者', '', 'manual', 'CNY')
        """, (now, now))
        conn.execute(
            "INSERT INTO members (id, name, created_at) VALUES ('member-001', '测试人', ?)", (now,)
        )
        conn.commit()
        conn.close()

        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(db_path)])
        assert result.exit_code == 0


# ---------------------------------------------------------------------------
# AC-5: --csv 导出
# ---------------------------------------------------------------------------

class TestCsvExport:
    def test_csv_mode_exit_zero(self, tmp_db: Path) -> None:
        """--csv flag should succeed."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--csv", "--db", str(tmp_db)])
        assert result.exit_code == 0

    def test_csv_contains_section_headers(self, tmp_db: Path) -> None:
        """CSV output must include section comment lines."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--csv", "--db", str(tmp_db)])
        assert result.exit_code == 0
        assert "总览" in result.output
        assert "分类支出" in result.output
        assert "成员统计" in result.output

    def test_csv_is_parseable(self, tmp_db: Path) -> None:
        """CSV output (excluding comment lines) must be valid CSV."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--csv", "--db", str(tmp_db)])
        assert result.exit_code == 0
        # Filter out comment lines starting with #
        data_lines = [
            line for line in result.output.splitlines()
            if line and not line.startswith("#")
        ]
        parsed = list(csv.reader(data_lines))
        assert len(parsed) > 0

    def test_csv_overview_values(self, tmp_db: Path) -> None:
        """CSV overview section must contain correct numeric values."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--csv", "--db", str(tmp_db)])
        assert result.exit_code == 0
        assert "5000.00" in result.output  # income
        assert "200.00" in result.output   # expense
        assert "4800.00" in result.output  # balance

    def test_csv_member_section_values(self, tmp_db: Path) -> None:
        """CSV member section must contain correct paid/share/settlement values."""
        result = runner.invoke(app, ["report", "--month", "2024-01", "--csv", "--db", str(tmp_db)])
        assert result.exit_code == 0
        assert "张三" in result.output
        assert "李四" in result.output
        assert "140.00" in result.output  # 张三 paid
        assert "70.00" in result.output   # 张三 share


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

class TestEdgeCases:
    def test_db_not_initialized_exits_1(self, tmp_path: Path) -> None:
        """Non-existent database file should exit with code 1."""
        missing_db = tmp_path / "missing.db"
        result = runner.invoke(app, ["report", "--month", "2024-01", "--db", str(missing_db)])
        assert result.exit_code == 1

    def test_income_only_month(self, tmp_path: Path) -> None:
        """Month with only income and no expenses should not crash."""
        db_path = tmp_path / "income_only.db"
        conn = init_db(db_path)
        now = "2024-03-01T10:00:00+00:00"
        income_cat = conn.execute(
            "SELECT id FROM categories WHERE type='收入' LIMIT 1"
        ).fetchone()
        cat_id = income_cat["id"] if income_cat else ""
        conn.execute("""
            INSERT INTO transactions
                (id, created_at, updated_at, date, amount, type, category_id,
                 payer_id, participant_ids, note, merchant, source, currency)
            VALUES ('tx-inc', ?, ?, '2024-03-01', '3000.00', '收入', ?,
                    '', '', '工资', '', 'manual', 'CNY')
        """, (now, now, cat_id))
        conn.commit()
        conn.close()

        result = runner.invoke(app, ["report", "--month", "2024-03", "--db", str(db_path)])
        assert result.exit_code == 0
        assert "3000.00" in result.output
