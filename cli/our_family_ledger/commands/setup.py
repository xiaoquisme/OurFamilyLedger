"""ledger setup and members commands.

Implements TES-42:
  - ledger setup: interactive config wizard for AI provider/endpoint/model/api_key
  - ledger members: add/list family members
"""

from __future__ import annotations

import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.table import Table

from our_family_ledger.config import AIConfig, load_ai_config, save_ai_config
from our_family_ledger.db import init_db

console = Console()


def setup_command(db_path: Optional[str] = None) -> None:
    """Interactive AI configuration setup wizard."""
    # Initialize DB first
    init_db(path=db_path)

    existing = load_ai_config()

    console.print("\n[bold cyan]🔧 OurFamilyLedger 设置向导[/bold cyan]\n")
    console.print("配置 AI 服务用于自然语言记账（ledger chat）。")
    console.print("配置将保存到 ~/.our-family-ledger/config.toml\n")

    provider = _prompt("AI 提供商", default=existing.provider if existing else "openai")
    endpoint = _prompt(
        "API Endpoint",
        default=existing.endpoint if existing else "https://api.openai.com/v1",
    )
    model = _prompt("模型", default=existing.model if existing else "gpt-4o-mini")
    api_key = _prompt("API Key", default=existing.api_key if existing else "")

    cfg = AIConfig(provider=provider, endpoint=endpoint, model=model, api_key=api_key)
    save_ai_config(cfg)

    console.print("\n[green]✓ 配置已保存。[/green]")
    console.print("\n现在可以运行 [bold]ledger chat[/bold] 开始 AI 记账。\n")


def _prompt(label: str, default: str = "") -> str:
    """Simple stdin prompt with optional default."""
    if default and default != "":
        console.print(f"{label} [dim](当前: {default})[/dim]: ", end="")
    else:
        console.print(f"{label}: ", end="")
    value = sys.stdin.readline().strip()
    return value if value else default


def members_list_command(db_path: Optional[str] = None) -> None:
    """List all family members."""
    conn = init_db(path=db_path)
    rows = conn.execute(
        "SELECT id, name, created_at FROM members ORDER BY created_at ASC"
    ).fetchall()

    if not rows:
        console.print("[yellow]尚未添加家庭成员。[/yellow]")
        console.print("使用 [bold]ledger members add <姓名>[/bold] 添加成员。")
        return

    table = Table(show_header=True, header_style="bold cyan")
    table.add_column("ID", style="dim", width=8)
    table.add_column("姓名", width=16)
    table.add_column("添加时间", width=20)
    for row in rows:
        table.add_row(row["id"][:8], row["name"], row["created_at"])

    console.print(table)
    console.print(f"\n共 [bold]{len(rows)}[/bold] 位成员。")


def members_add_command(name: str, db_path: Optional[str] = None) -> None:
    """Add a new family member."""
    conn = init_db(path=db_path)

    # Check for duplicate name
    existing = conn.execute(
        "SELECT id FROM members WHERE name = ?", (name,)
    ).fetchone()
    if existing:
        console.print(f"[yellow]成员 '{name}' 已存在。[/yellow]")
        return

    now = datetime.now(timezone.utc).isoformat()
    member_id = str(uuid.uuid4())
    conn.execute(
        "INSERT INTO members (id, name, created_at) VALUES (?, ?, ?)",
        (member_id, name, now),
    )
    conn.commit()

    console.print(f"[green]✓ 已添加成员: {name}[/green]")
