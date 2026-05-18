"""ledger report — monthly statistics report command.

Implements TES-40: 月度统计报表命令.

Shows:
  - Overview: total income, total expense, balance, transaction count
  - Category breakdown: expense amount and percentage per category
  - Member statistics: paid amount, share amount, settlement per member

Usage:
  ledger report [--month YYYY-MM] [--csv]
"""

from __future__ import annotations

import csv
import re
import sys
from datetime import datetime

import typer

from our_family_ledger.db import get_db

app = typer.Typer(help="Generate monthly statistics report.")


def _current_month() -> str:
    return datetime.now().strftime("%Y-%m")


def _validate_month(month: str) -> None:
    """Validate YYYY-MM format and exit(1) on invalid input."""
    if not re.match(r"^\d{4}-\d{2}$", month):
        typer.echo(
            f"Error: Invalid month format '{month}'. Expected YYYY-MM (e.g. 2024-01).",
            err=True,
        )
        raise typer.Exit(1)


# ---------------------------------------------------------------------------
# Data-fetching helpers
# ---------------------------------------------------------------------------

def _fetch_overview(conn, month: str) -> dict:
    """Return totals dict: total_expense, total_income, balance, tx_count."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            COALESCE(SUM(CASE WHEN type = '支出' THEN CAST(amount AS REAL) ELSE 0 END), 0) AS total_expense,
            COALESCE(SUM(CASE WHEN type = '收入' THEN CAST(amount AS REAL) ELSE 0 END), 0) AS total_income,
            COUNT(*) AS tx_count
        FROM transactions
        WHERE date LIKE ?
    """, (f"{month}%",))
    row = cursor.fetchone()
    total_expense = row["total_expense"]
    total_income = row["total_income"]
    return {
        "total_expense": total_expense,
        "total_income": total_income,
        "balance": total_income - total_expense,
        "tx_count": row["tx_count"],
    }


def _fetch_category_breakdown(conn, month: str) -> list[dict]:
    """Return list of {name, total, percentage} sorted by total desc."""
    cursor = conn.cursor()

    # Total expense for this month (for percentage calculation)
    cursor.execute("""
        SELECT COALESCE(SUM(CAST(amount AS REAL)), 0) AS total_expense
        FROM transactions
        WHERE type = '支出' AND date LIKE ?
    """, (f"{month}%",))
    total_row = cursor.fetchone()
    total_expense = total_row["total_expense"]

    cursor.execute("""
        SELECT
            COALESCE(c.name, '未分类') AS name,
            COALESCE(SUM(CAST(t.amount AS REAL)), 0) AS total
        FROM transactions t
        LEFT JOIN categories c ON t.category_id = c.id
        WHERE t.type = '支出' AND t.date LIKE ?
        GROUP BY t.category_id
        ORDER BY total DESC
    """, (f"{month}%",))

    rows = cursor.fetchall()
    result = []
    for row in rows:
        pct = (row["total"] / total_expense * 100) if total_expense > 0 else 0.0
        result.append({
            "name": row["name"] or "未分类",
            "total": row["total"],
            "percentage": pct,
        })
    return result


def _fetch_member_stats(conn, month: str) -> list[dict]:
    """Return list of {name, paid, share, settlement} sorted by paid desc."""
    cursor = conn.cursor()

    # 1. Paid by member (payer_id)
    cursor.execute("""
        SELECT
            t.payer_id,
            COALESCE(m.name, '未知') AS name,
            COALESCE(SUM(CAST(t.amount AS REAL)), 0) AS paid
        FROM transactions t
        LEFT JOIN members m ON t.payer_id = m.id
        WHERE t.type = '支出' AND t.date LIKE ?
        GROUP BY t.payer_id
    """, (f"{month}%",))
    paid_rows = cursor.fetchall()
    paid_map: dict[str, float] = {}
    name_map: dict[str, str] = {}
    for row in paid_rows:
        pid = row["payer_id"] or ""
        paid_map[pid] = row["paid"]
        name_map[pid] = row["name"]

    # 2. Share by member (participant_ids, semicolon-separated)
    cursor.execute("""
        SELECT participant_ids, CAST(amount AS REAL) AS amount
        FROM transactions
        WHERE type = '支出' AND date LIKE ?
    """, (f"{month}%",))
    share_map: dict[str, float] = {}
    for row in cursor.fetchall():
        raw = (row["participant_ids"] or "").strip()
        pids = [p.strip() for p in raw.split(";") if p.strip()] if raw else []
        count = max(1, len(pids))
        share = row["amount"] / count
        for pid in pids:
            share_map[pid] = share_map.get(pid, 0.0) + share

    # 3. Resolve names for participants not already in paid_map
    all_pids = set(paid_map) | set(share_map)
    # Fetch member names for any missing IDs
    for pid in all_pids:
        if pid not in name_map and pid:
            cursor.execute("SELECT name FROM members WHERE id = ?", (pid,))
            r = cursor.fetchone()
            name_map[pid] = r["name"] if r else "未知"

    # 4. Merge and compute settlement
    result = []
    for pid in all_pids:
        paid = paid_map.get(pid, 0.0)
        share = share_map.get(pid, 0.0)
        result.append({
            "name": name_map.get(pid, "未知"),
            "paid": paid,
            "share": share,
            "settlement": paid - share,
        })
    result.sort(key=lambda x: x["paid"], reverse=True)
    return result


# ---------------------------------------------------------------------------
# Rich table output helpers
# ---------------------------------------------------------------------------

def _print_rich_report(overview: dict, categories: list[dict], members: list[dict], month: str) -> None:
    """Print report using rich tables."""
    from rich.console import Console
    from rich.table import Table
    from rich import box

    console = Console()

    console.print(f"\n[bold cyan]📊 {month} 月度统计报表[/bold cyan]\n")

    # --- Overview table ---
    overview_table = Table(title="总览", box=box.ROUNDED, show_lines=True)
    overview_table.add_column("项目", style="bold")
    overview_table.add_column("金额", justify="right")

    total_income = overview["total_income"]
    total_expense = overview["total_expense"]
    balance = overview["balance"]

    overview_table.add_row("总收入", f"[green]¥{total_income:.2f}[/green]")
    overview_table.add_row("总支出", f"[red]¥{total_expense:.2f}[/red]")
    balance_color = "green" if balance >= 0 else "red"
    overview_table.add_row(
        "结余",
        f"[{balance_color}]¥{balance:.2f}[/{balance_color}]"
    )
    overview_table.add_row("交易笔数", str(overview["tx_count"]))
    console.print(overview_table)

    # --- Category breakdown table ---
    if categories:
        cat_table = Table(title="分类支出", box=box.ROUNDED, show_lines=True)
        cat_table.add_column("分类", style="bold")
        cat_table.add_column("金额(¥)", justify="right")
        cat_table.add_column("占比(%)", justify="right")

        for cat in categories:
            cat_table.add_row(
                cat["name"],
                f"{cat['total']:.2f}",
                f"{cat['percentage']:.1f}%",
            )
        console.print(cat_table)
    else:
        console.print("[dim]本月无支出分类数据。[/dim]\n")

    # --- Member stats table ---
    if members:
        member_table = Table(title="成员统计", box=box.ROUNDED, show_lines=True)
        member_table.add_column("成员", style="bold")
        member_table.add_column("实付(¥)", justify="right")
        member_table.add_column("分摊(¥)", justify="right")
        member_table.add_column("差额(¥)", justify="right")

        for m in members:
            settlement = m["settlement"]
            if settlement > 0:
                settle_str = f"[green]+{settlement:.2f}[/green]"
            elif settlement < 0:
                settle_str = f"[red]{settlement:.2f}[/red]"
            else:
                settle_str = f"0.00"

            member_table.add_row(
                m["name"],
                f"{m['paid']:.2f}",
                f"{m['share']:.2f}",
                settle_str,
            )
        console.print(member_table)
    else:
        console.print("[dim]本月无成员统计数据。[/dim]\n")


def _print_csv_report(overview: dict, categories: list[dict], members: list[dict], month: str) -> None:
    """Print report in CSV format to stdout."""
    writer = csv.writer(sys.stdout)

    # Overview section
    writer.writerow([f"# 总览 — {month}"])
    writer.writerow(["项目", "金额"])
    writer.writerow(["总收入", f"{overview['total_income']:.2f}"])
    writer.writerow(["总支出", f"{overview['total_expense']:.2f}"])
    writer.writerow(["结余", f"{overview['balance']:.2f}"])
    writer.writerow(["交易笔数", overview["tx_count"]])

    writer.writerow([])

    # Category section
    writer.writerow([f"# 分类支出 — {month}"])
    writer.writerow(["分类", "金额(¥)", "占比(%)"])
    for cat in categories:
        writer.writerow([cat["name"], f"{cat['total']:.2f}", f"{cat['percentage']:.1f}"])

    writer.writerow([])

    # Member section
    writer.writerow([f"# 成员统计 — {month}"])
    writer.writerow(["成员", "实付(¥)", "分摊(¥)", "差额(¥)"])
    for m in members:
        writer.writerow([
            m["name"],
            f"{m['paid']:.2f}",
            f"{m['share']:.2f}",
            f"{m['settlement']:.2f}",
        ])


# ---------------------------------------------------------------------------
# Typer command
# ---------------------------------------------------------------------------

@app.callback(invoke_without_command=True)
def report(
    month: str = typer.Option(
        default_factory=_current_month,
        help="Month to report in YYYY-MM format (default: current month).",
    ),
    csv_mode: bool = typer.Option(
        False,
        "--csv",
        help="Output in CSV format instead of terminal tables.",
    ),
    db_path: str = typer.Option(
        "",
        "--db",
        help="Path to the database file.",
        hidden=True,
    ),
) -> None:
    """Show monthly ledger statistics report."""
    if not month:
        month = _current_month()

    _validate_month(month)

    # Resolve DB path
    from pathlib import Path
    resolved_db = Path(db_path) if db_path else None

    # Check DB exists
    from our_family_ledger.db import DEFAULT_DB_PATH
    actual_db = resolved_db or DEFAULT_DB_PATH
    if not actual_db.exists():
        typer.echo(
            "Error: Database not found. Run 'ledger setup' to initialize first.",
            err=True,
        )
        raise typer.Exit(1)

    try:
        conn = get_db(resolved_db)
    except Exception as exc:
        typer.echo(f"Error: Could not open database: {exc}", err=True)
        raise typer.Exit(1)

    overview = _fetch_overview(conn, month)
    categories = _fetch_category_breakdown(conn, month)
    members = _fetch_member_stats(conn, month)

    conn.close()

    if csv_mode:
        _print_csv_report(overview, categories, members, month)
    else:
        _print_rich_report(overview, categories, members, month)
