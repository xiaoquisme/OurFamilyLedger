"""ledger export — export transactions for a given month to CSV."""

from __future__ import annotations

import csv
import re
from pathlib import Path
from typing import Optional

import typer
from rich import print as rprint

from our_family_ledger import config as _cfg
from our_family_ledger.config import TRANSACTION_HEADERS, get_connection

_MONTH_RE = re.compile(r"^\d{4}-(?:0[1-9]|1[0-2])$")


def export_cmd(
    month: str = typer.Option(
        ...,
        "--month",
        "-m",
        help="要导出的月份，格式 YYYY-MM（如 2024-01）",
    ),
    output: Optional[str] = typer.Option(
        None,
        "--output",
        "-o",
        help="输出 CSV 文件路径。省略时默认写到 ~/.our-family-ledger/exports/transactions_YYYY-MM.csv",
    ),
    db: Optional[str] = typer.Option(
        None,
        "--db",
        hidden=True,
        help="Override DB path (for testing).",
    ),
) -> None:
    """将指定月份的交易记录导出为 CSV 文件。"""
    if not _MONTH_RE.match(month):
        rprint(f"[red]Error:[/red] --month 格式错误，需要 YYYY-MM，收到: {month!r}")
        raise typer.Exit(code=1)

    db_path = Path(db) if db else _cfg.DB_FILE

    # Determine output path
    if output:
        out_path = Path(output)
    else:
        exports_dir = _cfg.DATA_DIR / "exports"
        exports_dir.mkdir(parents=True, exist_ok=True)
        out_path = exports_dir / f"transactions_{month}.csv"

    # Query
    with get_connection(db_path) as conn:
        rows = conn.execute(
            "SELECT * FROM transactions WHERE strftime('%Y-%m', date) = ? ORDER BY date",
            (month,),
        ).fetchall()

    count = len(rows)

    # Write CSV
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(TRANSACTION_HEADERS)
        for row in rows:
            writer.writerow(
                [
                    row["id"],
                    row["created_at"],
                    row["updated_at"],
                    row["date"],
                    row["amount"],
                    row["type"],
                    row["category"],
                    row["payer"],
                    row["participants"],
                    row["note"],
                    row["merchant"],
                    row["source"],
                    row["ocr_text"] if row["ocr_text"] is not None else "",
                    row["currency"],
                ]
            )

    rprint(f"[green]✓[/green] 已导出 [bold]{count}[/bold] 条记录到 {out_path}")
