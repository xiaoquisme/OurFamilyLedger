"""OurFamilyLedger — main CLI entry point.

Combines all sub-commands:
  ledger add/list/show/edit/delete  — CRUD (TES-37)
  ledger chat                       — AI natural-language entry (TES-39)
  ledger report                     — monthly report (TES-40)
  ledger import/export              — CSV migration (TES-41)
  ledger setup                      — AI config wizard (TES-42)
  ledger members                    — family member management (TES-42)
"""

from __future__ import annotations

from datetime import date as date_type
from decimal import Decimal, InvalidOperation
from typing import Optional

import typer
from rich.prompt import Confirm, Prompt

from our_family_ledger.db import init_db
from our_family_ledger.display import (
    console,
    participants_display,
    participants_to_db,
    render_detail,
    render_table,
)
from our_family_ledger.models import Transaction
from our_family_ledger.repo import TransactionRepository

app = typer.Typer(help="OurFamilyLedger — 家庭账本 CLI。数据存储于 ~/.our-family-ledger/data.db")
members_app = typer.Typer(help="管理家庭成员。")
app.add_typer(members_app, name="members")


def _get_repo(db_path: Optional[str] = None) -> TransactionRepository:
    conn = init_db(path=db_path)
    return TransactionRepository(conn)


def _resolve_tx(repo: TransactionRepository, id_prefix: str) -> Transaction:
    """Look up a transaction by prefix, exit with error if not found/ambiguous."""
    matches = repo.find_by_prefix(id_prefix)
    if not matches:
        console.print(f"[red]错误：找不到交易记录 '{id_prefix}'[/red]")
        raise typer.Exit(1)
    if len(matches) > 1:
        from rich.table import Table as RichTable
        console.print(
            f"[yellow]前缀 '{id_prefix}' 匹配多条记录，请提供更长的前缀：[/yellow]"
        )
        t = RichTable("id前缀", "日期", "金额", "备注")
        for m in matches:
            t.add_row(m.id[:12], m.date, m.amount, m.note)
        console.print(t)
        raise typer.Exit(1)
    return matches[0]


# ---------------------------------------------------------------------------
# AC-1  ledger add
# ---------------------------------------------------------------------------

@app.command("add")
def add(
    amount: Optional[str]       = typer.Option(None, "--amount",       "-a", help="交易金额（数字）"),
    tx_type: Optional[str]      = typer.Option(None, "--type",         "-t", help="支出 / 收入"),
    category: Optional[str]     = typer.Option(None, "--category",     "-c", help="分类名称"),
    payer: Optional[str]        = typer.Option(None, "--payer",        "-p", help="付款人"),
    participants: Optional[str] = typer.Option(None, "--participants", "-P", help="参与者（逗号分隔）"),
    note: Optional[str]         = typer.Option(None, "--note",         "-n", help="备注"),
    merchant: Optional[str]     = typer.Option(None, "--merchant",     "-m", help="商家名称"),
    date: Optional[str]         = typer.Option(None, "--date",         "-d", help="日期 YYYY-MM-DD"),
    currency: str               = typer.Option("CNY", "--currency",          help="货币代码"),
) -> None:
    """添加一条交易记录。"""
    if amount is None:
        amount = Prompt.ask("金额")
    if tx_type is None:
        tx_type = Prompt.ask("类型", choices=["支出", "收入"], default="支出")
    if category is None:
        category = Prompt.ask("分类", default="")
    if payer is None:
        payer = Prompt.ask("付款人", default="")
    if participants is None:
        participants = Prompt.ask("参与者（逗号分隔）", default=payer or "")
    if note is None:
        note = Prompt.ask("备注", default="")
    if merchant is None:
        merchant = Prompt.ask("商家（可选）", default="")
    if date is None:
        date = Prompt.ask("日期", default=date_type.today().isoformat())

    try:
        amt_decimal = Decimal(amount)
    except InvalidOperation:
        console.print(f"[red]金额格式错误: {amount!r}[/red]")
        raise typer.Exit(1)

    tx = Transaction(
        date=date,
        amount=str(amt_decimal),
        type=tx_type,
        category=category or "",
        payer=payer or "",
        participants=participants_to_db(participants or ""),
        note=note or "",
        merchant=merchant or "",
        currency=currency,
    )

    repo = _get_repo()
    repo.insert(tx)
    console.print(f"[green]✅ 已添加: ¥{amt_decimal} {category} [{tx.id[:8]}][/green]")


# ---------------------------------------------------------------------------
# AC-2  ledger list
# ---------------------------------------------------------------------------

@app.command("list")
def list_transactions(
    month: Optional[str]      = typer.Option(None, "--month",      "-M", help="月份 YYYY-MM"),
    category: Optional[str]   = typer.Option(None, "--category",   "-c", help="分类"),
    payer: Optional[str]      = typer.Option(None, "--payer",      "-p", help="付款人"),
    member: Optional[str]     = typer.Option(None, "--member",     "-m", help="参与成员"),
    min_amount: Optional[str] = typer.Option(None, "--min-amount",       help="最小金额"),
    max_amount: Optional[str] = typer.Option(None, "--max-amount",       help="最大金额"),
    tx_type: Optional[str]    = typer.Option(None, "--type",       "-t", help="支出/收入"),
    limit: int                = typer.Option(50, "--limit",         "-l", help="最多显示条数"),
) -> None:
    """列出交易记录。"""
    if month is None:
        month = date_type.today().strftime("%Y-%m")

    min_d = Decimal(min_amount) if min_amount else None
    max_d = Decimal(max_amount) if max_amount else None

    repo = _get_repo()
    transactions = repo.query(
        month=month,
        category=category,
        payer=payer,
        member=member,
        min_amount=min_d,
        max_amount=max_d,
        tx_type=tx_type,
        limit=limit,
    )

    if not transactions:
        console.print("[yellow]没有找到匹配的记录。[/yellow]")
        return

    render_table(transactions, month)


# ---------------------------------------------------------------------------
# AC-3  ledger show
# ---------------------------------------------------------------------------

@app.command("show")
def show(id_prefix: str = typer.Argument(..., help="交易ID前缀（至少4位）")) -> None:
    """显示交易记录详情。"""
    repo = _get_repo()
    tx = _resolve_tx(repo, id_prefix)
    render_detail(tx)


# ---------------------------------------------------------------------------
# AC-4  ledger edit
# ---------------------------------------------------------------------------

@app.command("edit")
def edit(
    id_prefix: str            = typer.Argument(..., help="交易ID前缀"),
    amount: Optional[str]     = typer.Option(None, "--amount",       "-a"),
    tx_type: Optional[str]    = typer.Option(None, "--type",         "-t"),
    category: Optional[str]   = typer.Option(None, "--category",     "-c"),
    payer: Optional[str]      = typer.Option(None, "--payer",        "-p"),
    participants: Optional[str] = typer.Option(None, "--participants", "-P"),
    note: Optional[str]       = typer.Option(None, "--note",         "-n"),
    merchant: Optional[str]   = typer.Option(None, "--merchant",     "-m"),
    date: Optional[str]       = typer.Option(None, "--date",         "-d"),
) -> None:
    """修改交易记录字段。"""
    repo = _get_repo()
    tx = _resolve_tx(repo, id_prefix)

    updates: dict = {}
    if amount is not None:
        try:
            updates["amount"] = str(Decimal(amount))
        except InvalidOperation:
            console.print(f"[red]金额格式错误: {amount!r}[/red]")
            raise typer.Exit(1)
    if tx_type is not None:
        updates["type"] = tx_type
    if category is not None:
        updates["category"] = category
    if payer is not None:
        updates["payer"] = payer
    if participants is not None:
        updates["participants"] = participants_to_db(participants)
    if note is not None:
        updates["note"] = note
    if merchant is not None:
        updates["merchant"] = merchant
    if date is not None:
        updates["date"] = date

    if not updates:
        console.print("[yellow]没有提供任何修改。[/yellow]")
        return

    repo.update(tx.id, **updates)
    console.print(f"[green]✅ 已更新 [{tx.id[:8]}][/green]")


# ---------------------------------------------------------------------------
# AC-5  ledger delete
# ---------------------------------------------------------------------------

@app.command("delete")
def delete(
    id_prefix: str  = typer.Argument(..., help="交易ID前缀"),
    force: bool     = typer.Option(False, "--force", "-f", help="跳过确认"),
) -> None:
    """删除交易记录。"""
    repo = _get_repo()
    tx = _resolve_tx(repo, id_prefix)
    render_detail(tx)

    if not force:
        confirmed = Confirm.ask("确认删除？", default=False)
        if not confirmed:
            console.print("[yellow]已取消。[/yellow]")
            return

    repo.delete(tx.id)
    console.print(f"[green]✅ 已删除 [{tx.id[:8]}][/green]")


# ---------------------------------------------------------------------------
# ledger chat (TES-39)
# ---------------------------------------------------------------------------

@app.command("chat")
def chat() -> None:
    """进入 AI 自然语言记账模式。"""
    from our_family_ledger.commands.chat import chat_command
    chat_command()


# ---------------------------------------------------------------------------
# ledger report (TES-40)
# ---------------------------------------------------------------------------

@app.command("report")
def report(
    month: Optional[str] = typer.Option(None, "--month", "-M", help="月份 YYYY-MM（默认当月）"),
    csv: bool = typer.Option(False, "--csv", help="以 CSV 格式输出到 stdout"),
) -> None:
    """查看月度统计报表。"""
    from our_family_ledger.commands.report import report_command
    report_command(month=month, csv_output=csv)


# ---------------------------------------------------------------------------
# ledger import/export (TES-41)
# ---------------------------------------------------------------------------

@app.command("import")
def import_data(
    file: str = typer.Option(..., "--file", "-f", help="CSV 文件路径（支持 glob 通配符）"),
) -> None:
    """从 CSV 文件导入历史交易数据。"""
    from our_family_ledger.commands.data import import_command
    import_command(file_pattern=file)


@app.command("export")
def export_data(
    month: str = typer.Option(..., "--month", "-M", help="导出月份 YYYY-MM"),
    output: Optional[str] = typer.Option(None, "--output", "-o", help="输出文件路径（默认输出到 stdout）"),
) -> None:
    """将指定月份数据导出为 CSV 文件。"""
    from our_family_ledger.commands.data import export_command
    export_command(month=month, output=output)


# ---------------------------------------------------------------------------
# ledger setup (TES-42)
# ---------------------------------------------------------------------------

@app.command("setup")
def setup() -> None:
    """引导配置 AI provider/endpoint/model/api_key，写入 config.toml。"""
    from our_family_ledger.commands.setup import setup_command
    setup_command()


# ---------------------------------------------------------------------------
# ledger members (TES-42)
# ---------------------------------------------------------------------------

@members_app.command("list")
def members_list() -> None:
    """列出所有家庭成员。"""
    from our_family_ledger.commands.setup import members_list_command
    members_list_command()


@members_app.command("add")
def members_add(name: str = typer.Argument(..., help="成员姓名")) -> None:
    """添加家庭成员。"""
    from our_family_ledger.commands.setup import members_add_command
    members_add_command(name=name)


def main() -> None:
    app()


if __name__ == "__main__":
    main()
