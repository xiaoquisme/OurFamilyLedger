"""Display helpers for OurFamilyLedger CLI.

Renders Transaction objects to rich tables, panels, and summary lines.
"""

from __future__ import annotations

from decimal import Decimal, InvalidOperation

from rich.console import Console
from rich.panel import Panel
from rich.table import Table

from our_family_ledger.models import Transaction

console = Console()


def participants_display(semicolon_str: str) -> str:
    """Convert semicolon-separated DB value to comma-separated display string."""
    if not semicolon_str:
        return ""
    return ", ".join(p for p in semicolon_str.split(";") if p)


def participants_to_db(comma_or_semi_str: str) -> str:
    """Convert comma-separated input to semicolon-separated DB storage value."""
    if not comma_or_semi_str:
        return ""
    parts = [
        p.strip()
        for p in comma_or_semi_str.replace(";", ",").split(",")
        if p.strip()
    ]
    return ";".join(parts)


def render_table(transactions: list[Transaction], month: str) -> None:
    """Render a list of transactions as a rich table with totals."""
    table = Table(
        title=f"交易记录 — {month}",
        show_lines=False,
        header_style="bold cyan",
    )
    table.add_column("ID", style="dim", width=8)
    table.add_column("日期", width=10)
    table.add_column("金额", justify="right", width=10)
    table.add_column("类型", width=4)
    table.add_column("分类", width=8)
    table.add_column("付款人", width=8)
    table.add_column("参与者", width=16)
    table.add_column("备注")

    total_expense = Decimal("0")
    total_income = Decimal("0")

    for tx in transactions:
        try:
            amt = tx.amount_decimal
        except InvalidOperation:
            amt = Decimal("0")
        if tx.type == "支出":
            total_expense += amt
        else:
            total_income += amt

        table.add_row(
            tx.id[:8],
            tx.date,
            tx.amount,
            tx.type,
            tx.category,
            tx.payer,
            participants_display(tx.participants),
            tx.note,
        )

    console.print(table)
    console.print(
        f"共 [bold]{len(transactions)}[/bold] 笔  "
        f"支出合计 [red]{total_expense}[/red]  "
        f"收入合计 [green]{total_income}[/green]"
    )


def render_detail(tx: Transaction) -> None:
    """Render full transaction detail in a rich panel with split amount."""
    participants_list = tx.participants_list
    try:
        amt = tx.amount_decimal
        if participants_list:
            split = amt / len(participants_list)
            split_line = f"{split:.2f} 元/人（共 {len(participants_list)} 人）"
        else:
            split_line = f"{amt:.2f} 元（无参与者）"
    except (InvalidOperation, ZeroDivisionError):
        split_line = "—"

    lines = [
        f"[bold]ID[/bold]           {tx.id}",
        f"[bold]日期[/bold]         {tx.date}",
        f"[bold]金额[/bold]         {tx.amount} {tx.currency}",
        f"[bold]类型[/bold]         {tx.type}",
        f"[bold]分类[/bold]         {tx.category}",
        f"[bold]付款人[/bold]       {tx.payer}",
        f"[bold]参与者[/bold]       {participants_display(tx.participants)}",
        f"[bold]每人分摊[/bold]     {split_line}",
        f"[bold]商家[/bold]         {tx.merchant}",
        f"[bold]备注[/bold]         {tx.note}",
        f"[bold]来源[/bold]         {tx.source}",
        f"[bold]创建时间[/bold]     {tx.created_at}",
        f"[bold]更新时间[/bold]     {tx.updated_at}",
    ]

    console.print(Panel("\n".join(lines), title=f"交易详情 [{tx.id[:8]}]"))
