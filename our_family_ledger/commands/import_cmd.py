"""ledger import — import historical transactions from CSV file(s)."""

from __future__ import annotations

import csv
import glob as glob_module
import sqlite3
from pathlib import Path
from typing import Optional

import typer
from rich import print as rprint

from our_family_ledger import config as _cfg
from our_family_ledger.config import TRANSACTION_HEADERS, get_connection

# Required non-nullable CSV columns (ocr_text is nullable → may be empty/missing)
_REQUIRED_COLS = set(TRANSACTION_HEADERS) - {"ocr_text"}


def _import_file(conn: sqlite3.Connection, path: Path) -> tuple[int, int]:
    """Import a single CSV file. Returns (imported, skipped) counts."""
    imported = 0
    skipped = 0

    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)

        # Validate header
        if reader.fieldnames is None:
            rprint(f"[yellow]⚠[/yellow]  {path.name}: 文件为空，跳过")
            return 0, 0
        missing = _REQUIRED_COLS - set(reader.fieldnames)
        if missing:
            rprint(
                f"[red]Error:[/red] {path.name}: 缺少列 {sorted(missing)}，跳过此文件"
            )
            return 0, 0

        rows: list[tuple] = []
        for row in reader:
            rows.append(
                (
                    row.get("id", ""),
                    row.get("created_at", ""),
                    row.get("updated_at", ""),
                    row.get("date", ""),
                    row.get("amount", ""),
                    row.get("type", ""),
                    row.get("category", ""),
                    row.get("payer", ""),
                    row.get("participants", ""),
                    row.get("note", ""),
                    row.get("merchant", ""),
                    row.get("source", "manual"),
                    row.get("ocr_text") or None,
                    row.get("currency", "CNY"),
                )
            )

    if not rows:
        return 0, 0

    # Use INSERT OR IGNORE — duplicate ids are silently skipped
    before = conn.execute("SELECT changes()").fetchone()[0]
    conn.executemany(
        """
        INSERT OR IGNORE INTO transactions
            (id, created_at, updated_at, date, amount, type, category,
             payer, participants, note, merchant, source, ocr_text, currency)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )
    conn.commit()

    # Count how many were actually inserted
    imported = conn.execute("SELECT changes()").fetchone()[0]
    skipped = len(rows) - imported
    return imported, skipped


def import_cmd(
    file: str = typer.Option(
        ...,
        "--file",
        "-f",
        help="CSV 文件路径，支持 glob 通配符（如 '*.csv' 或 '2024-*.csv'）",
    ),
    db: Optional[str] = typer.Option(
        None,
        "--db",
        hidden=True,
        help="Override DB path (for testing).",
    ),
) -> None:
    """从原项目 CSV 文件导入历史交易数据。"""
    db_path = Path(db) if db else _cfg.DB_FILE

    # Expand glob pattern
    matched = glob_module.glob(file)
    if not matched:
        rprint(f"[red]Error:[/red] 没有找到匹配的文件: {file}")
        raise typer.Exit(code=1)

    matched_paths = sorted(Path(p) for p in matched)

    total_imported = 0
    total_skipped = 0

    with get_connection(db_path) as conn:
        for path in matched_paths:
            if not path.is_file():
                rprint(f"[yellow]⚠[/yellow]  {path} 不是文件，跳过")
                continue
            imp, skip = _import_file(conn, path)
            total_imported += imp
            total_skipped += skip
            rprint(
                f"[dim]{path.name}[/dim]: 导入 {imp} 条，跳过重复 {skip} 条"
            )

    rprint(
        f"\n[green]✓[/green] 合计导入 [bold]{total_imported}[/bold] 条，"
        f"跳过重复 [bold]{total_skipped}[/bold] 条"
    )
