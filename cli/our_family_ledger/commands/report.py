"""ledger report command — monthly expense/income summary report.

Implements TES-40:
  AC-1  ledger report (defaults to current month)
  AC-2  --month YYYY-MM parameter
  AC-3  category breakdown with amount and percentage
  AC-4  member payment and split summary
  AC-5  income/expense totals comparison
  AC-6  rich table output or --csv export
"""

from __future__ import annotations

import csv
import io
import sys
from collections import defaultdict
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.table import Table

from our_family_ledger.db import init_db
from our_family_ledger.repo import TransactionRepository

console = Console()


def report_command(
    month: Optional[str] = None,
    csv_output: bool = False,
    db_path: Optional[str] = None,
) -> None:
    """Generate monthly expense/income report."""
    from datetime import date

    if month is None:
        month = date.today().strftime("%Y-%m")

    conn = init_db(path=db_path)
    repo = TransactionRepository(conn)

    transactions = repo.query(month=month, limit=10000)

    if not transactions:
        console.print(f"[yellow]没有找到 {month} 的交易记录。[/yellow]")
        return

    # Compute totals
    total_expense = Decimal("0")
    total_income = Decimal("0")
    category_expense: dict[str, Decimal] = defaultdict(Decimal)
    category_income: dict[str, Decimal] = defaultdict(Decimal)
    member_paid: dict[str, Decimal] = defaultdict(Decimal)
    member_owed: dict[str, Decimal] = defaultdict(Decimal)

    for tx in transactions:
        try:
            amt = Decimal(tx.amount)
        except InvalidOperation:
            amt = Decimal("0")

        if tx.type == "支出":
            total_expense += amt
            category_expense[tx.category or "未分类"] += amt
            if tx.payer:
                member_paid[tx.payer] += amt
            # Split evenly among participants
            participants = [p for p in tx.participants.split(";") if p]
            if participants:
                per_person = amt / len(participants)
                for p in participants:
                    member_owed[p] += per_person
        else:
            total_income += amt
            category_income[tx.category or "未分类"] += amt

    if csv_output:
        _export_csv(month, transactions, total_expense, total_income, category_expense,
                    member_paid, member_owed)
    else:
        _render_report(month, total_expense, total_income, category_expense,
                       category_income, member_paid, member_owed)


def _render_report(
    month: str,
    total_expense: Decimal,
    total_income: Decimal,
    category_expense: dict,
    category_income: dict,
    member_paid: dict,
    member_owed: dict,
) -> None:
    """Render the report as rich tables."""
    console.print(f"\n[bold cyan]📊 {month} 月度报表[/bold cyan]\n")

    # Summary table
    summary = Table(show_header=True, header_style="bold")
    summary.add_column("项目", width=12)
    summary.add_column("金额", justify="right", width=12)
    summary.add_row("总支出", f"[red]¥{total_expense:.2f}[/red]")
    summary.add_row("总收入", f"[green]¥{total_income:.2f}[/green]")
    net = total_income - total_expense
    net_color = "green" if net >= 0 else "red"
    summary.add_row("净额", f"[{net_color}]¥{net:.2f}[/{net_color}]")
    console.print(summary)
    console.print()

    # Category expense breakdown
    if category_expense:
        console.print("[bold]支出分类明细[/bold]")
        cat_table = Table(show_header=True, header_style="bold cyan")
        cat_table.add_column("分类", width=12)
        cat_table.add_column("金额", justify="right", width=12)
        cat_table.add_column("占比", justify="right", width=8)
        for cat, amt in sorted(category_expense.items(), key=lambda x: x[1], reverse=True):
            pct = (amt / total_expense * 100) if total_expense else Decimal("0")
            cat_table.add_row(cat, f"¥{amt:.2f}", f"{pct:.1f}%")
        console.print(cat_table)
        console.print()

    # Member payment summary
    all_members = set(member_paid.keys()) | set(member_owed.keys())
    if all_members:
        console.print("[bold]成员支付/分摊情况[/bold]")
        member_table = Table(show_header=True, header_style="bold cyan")
        member_table.add_column("成员", width=10)
        member_table.add_column("已付款", justify="right", width=12)
        member_table.add_column("应承担", justify="right", width=12)
        member_table.add_column("差额", justify="right", width=12)
        for m in sorted(all_members):
            paid = member_paid.get(m, Decimal("0"))
            owed = member_owed.get(m, Decimal("0"))
            diff = paid - owed
            diff_color = "green" if diff >= 0 else "red"
            member_table.add_row(
                m,
                f"¥{paid:.2f}",
                f"¥{owed:.2f}",
                f"[{diff_color}]¥{diff:.2f}[/{diff_color}]",
            )
        console.print(member_table)


def _export_csv(
    month: str,
    transactions: list,
    total_expense: Decimal,
    total_income: Decimal,
    category_expense: dict,
    member_paid: dict,
    member_owed: dict,
) -> None:
    """Export raw transactions as CSV to stdout."""
    writer = csv.writer(sys.stdout)
    writer.writerow([
        "id", "created_at", "updated_at", "date", "amount", "type",
        "category", "payer", "participants", "note", "merchant",
        "source", "ocr_text", "currency"
    ])
    for tx in transactions:
        writer.writerow([
            tx.id, tx.created_at, tx.updated_at, tx.date, tx.amount,
            tx.type, tx.category, tx.payer, tx.participants, tx.note,
            tx.merchant, tx.source, tx.ocr_text, tx.currency,
        ])
