"""ledger import/export commands — CSV data migration.

Implements TES-41:
  AC-1  ledger import --file <path> — import CSV (skip duplicate ids)
  AC-2  ledger export --month YYYY-MM --output <path> — export to CSV
  AC-3  skip duplicates and print conflict count
  AC-4  batch import via glob pattern
"""

from __future__ import annotations

import csv
import glob
import sys
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console

from our_family_ledger.db import init_db
from our_family_ledger.models import Transaction
from our_family_ledger.repo import TransactionRepository

console = Console()

# CSV headers matching the original iOS OurFamilyLedger TransactionCSV.headers
CSV_HEADERS = [
    "id", "created_at", "updated_at", "date", "amount", "type",
    "category", "payer", "participants", "note", "merchant",
    "source", "ocr_text", "currency",
]


def import_command(
    file_pattern: str,
    db_path: Optional[str] = None,
) -> None:
    """Import CSV file(s) into the SQLite database."""
    conn = init_db(path=db_path)
    repo = TransactionRepository(conn)

    # Expand glob pattern
    matched_files = sorted(glob.glob(file_pattern))
    if not matched_files:
        console.print(f"[red]没有找到匹配的文件: {file_pattern}[/red]")
        raise typer.Exit(1)

    total_imported = 0
    total_skipped = 0

    for file_path in matched_files:
        imported, skipped = _import_file(repo, file_path)
        total_imported += imported
        total_skipped += skipped
        console.print(
            f"[green]✓[/green] {file_path}: 导入 {imported} 条，跳过 {skipped} 条（重复）"
        )

    console.print(
        f"\n[bold]合计: 导入 {total_imported} 条，跳过 {total_skipped} 条。[/bold]"
    )


def _import_file(repo: TransactionRepository, file_path: str) -> tuple[int, int]:
    """Import a single CSV file. Returns (imported, skipped) counts."""
    imported = 0
    skipped = 0

    with open(file_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            tx_id = row.get("id", "").strip()
            if not tx_id:
                continue

            # Check for duplicate
            existing = repo.find_by_prefix(tx_id)
            if existing:
                skipped += 1
                continue

            tx = Transaction(
                id=tx_id,
                created_at=row.get("created_at", ""),
                updated_at=row.get("updated_at", ""),
                date=row.get("date", ""),
                amount=row.get("amount", "0"),
                type=row.get("type", "支出"),
                category=row.get("category", ""),
                payer=row.get("payer", ""),
                participants=row.get("participants", ""),
                note=row.get("note", ""),
                merchant=row.get("merchant", ""),
                source=row.get("source", "import"),
                ocr_text=row.get("ocr_text", ""),
                currency=row.get("currency", "CNY"),
            )
            repo.insert(tx)
            imported += 1

    return imported, skipped


def export_command(
    month: str,
    output: Optional[str] = None,
    db_path: Optional[str] = None,
) -> None:
    """Export transactions for a given month as CSV."""
    conn = init_db(path=db_path)
    repo = TransactionRepository(conn)

    transactions = repo.query(month=month, limit=100000)

    if not transactions:
        console.print(f"[yellow]没有找到 {month} 的交易记录。[/yellow]")
        return

    if output:
        out_file = open(output, "w", newline="", encoding="utf-8")
        writer = csv.writer(out_file)
    else:
        writer = csv.writer(sys.stdout)
        out_file = None

    try:
        writer.writerow(CSV_HEADERS)
        for tx in transactions:
            writer.writerow([
                tx.id, tx.created_at, tx.updated_at, tx.date, tx.amount,
                tx.type, tx.category, tx.payer, tx.participants, tx.note,
                tx.merchant, tx.source, tx.ocr_text, tx.currency,
            ])
    finally:
        if out_file:
            out_file.close()

    if output:
        console.print(
            f"[green]✓ 已导出 {len(transactions)} 条记录到 {output}[/green]"
        )
