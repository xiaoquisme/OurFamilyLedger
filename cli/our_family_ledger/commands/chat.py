"""ledger chat command — natural-language REPL for transaction entry.

Implements:
  AC-1  REPL loop with quit support
  AC-3  Draft preview as rich table
  AC-4  Multi-round correction (y/n/correction input)
  AC-5  config.toml [ai] section — first-run setup wizard
"""

from __future__ import annotations

import sys
from decimal import Decimal
from pathlib import Path

import typer
from rich.console import Console
from rich.table import Table

from our_family_ledger.ai.openai_client import OpenAIClient, OpenAIClientError
from our_family_ledger.config import AIConfig, load_ai_config, save_ai_config

console = Console()


def _run_setup_wizard(config_path: Path | None = None) -> AIConfig:
    """Interactive first-run wizard to collect and save AI configuration."""
    console.print("\n[bold yellow]首次运行 ledger chat，需要配置 AI 服务。[/bold yellow]")
    console.print("(配置将保存到 ~/.our-family-ledger/config.toml)\n")

    provider = _prompt("AI 提供商", default="openai")
    endpoint = _prompt("API Endpoint", default="https://api.openai.com/v1")
    model = _prompt("模型", default="gpt-4o-mini")
    api_key = _prompt("API Key")

    cfg = AIConfig(provider=provider, endpoint=endpoint, model=model, api_key=api_key)
    save_ai_config(cfg, path=config_path)
    console.print("[green]✓ 配置已保存。[/green]\n")
    return cfg


def _prompt(label: str, default: str = "") -> str:
    """Simple stdin prompt with optional default."""
    if default:
        console.print(f"{label} [dim](默认: {default})[/dim]: ", end="")
    else:
        console.print(f"{label}: ", end="")
    value = sys.stdin.readline().strip()
    return value if value else default


def _render_draft(draft: "TransactionDraft") -> None:
    """Render a TransactionDraft as a two-column rich table."""
    table = Table(show_header=False, show_edge=True, padding=(0, 1))
    table.add_column("字段", style="bold", width=10)
    table.add_column("值")

    participants_display = ", ".join(draft.participants) if draft.participants else "—"
    amount_str = f"¥{draft.amount:.2f}"

    table.add_row("金额", amount_str)
    table.add_row("类型", draft.type)
    table.add_row("分类", draft.category or "—")
    table.add_row("付款人", draft.payer or "—")
    table.add_row("参与人", participants_display)
    table.add_row("备注", draft.note or "—")
    table.add_row("日期", draft.date)

    console.print(table)


def _draft_to_transaction(draft: "TransactionDraft") -> "Transaction":
    """Convert a TransactionDraft into a Transaction for DB insertion."""
    from our_family_ledger.models import Transaction

    participants_db = ";".join(draft.participants) if draft.participants else ""
    return Transaction(
        date=draft.date,
        amount=str(Decimal(str(draft.amount)).quantize(Decimal("0.01"))),
        type=draft.type,
        category=draft.category,
        payer=draft.payer,
        participants=participants_db,
        note=draft.note,
        merchant=draft.merchant,
        source="chat",
    )


def chat_command(
    config_path: Path | None = None,
    db_path: Path | None = None,
) -> None:
    """Run the ledger chat REPL."""
    from our_family_ledger.db import init_db
    from our_family_ledger.repo import TransactionRepository

    # Load or create AI config
    ai_config = load_ai_config(path=config_path)
    if ai_config is None or not ai_config.api_key:
        ai_config = _run_setup_wizard(config_path=config_path)

    client = OpenAIClient(ai_config)

    # Initialize DB
    if db_path is not None:
        conn = init_db(path=str(db_path))
    else:
        conn = init_db()

    repo = TransactionRepository(conn)

    console.print("\n[bold cyan]💬 家庭记账助手[/bold cyan]（输入 quit 退出）\n")

    conversation: list[dict] = []

    while True:
        console.print("[bold]💬 >[/bold] ", end="")
        try:
            user_input = sys.stdin.readline()
        except (EOFError, KeyboardInterrupt):
            break

        if user_input == "":  # EOF
            break

        user_input = user_input.strip()
        if not user_input:
            continue
        if user_input.lower() in ("quit", "exit", "退出", "q"):
            break

        conversation.append({"role": "user", "content": user_input})

        console.print("[dim]⏳ 解析中...[/dim]")
        try:
            drafts = client.parse_transaction(conversation)
        except OpenAIClientError as exc:
            console.print(f"[red]❌ {exc}[/red]")
            conversation.pop()
            continue

        if not drafts:
            console.print("[yellow]⚠️ 无法解析交易信息，请重新描述。[/yellow]")
            conversation.pop()
            continue

        draft = drafts[0]

        console.print()
        _render_draft(draft)

        while True:
            console.print("\n[bold]确认入账? [y/n/修正][/bold] > ", end="")
            try:
                answer = sys.stdin.readline()
            except (EOFError, KeyboardInterrupt):
                return

            if answer == "":
                return

            answer = answer.strip()

            if answer.lower() in ("y", "yes", "是", "确认"):
                tx = _draft_to_transaction(draft)
                repo.insert(tx)
                console.print(
                    f"[green]✅ 已入账 ¥{draft.amount:.2f} {draft.category}[/green]\n"
                )
                conversation.clear()
                break

            elif answer.lower() in ("n", "no", "否", "取消", "跳过"):
                console.print("[yellow]已跳过。[/yellow]\n")
                conversation.clear()
                break

            elif answer:
                conversation.append(
                    {
                        "role": "assistant",
                        "content": (
                            f"我解析到：金额 {draft.amount}，类型 {draft.type}，"
                            f"分类 {draft.category}，付款人 {draft.payer}，"
                            f"参与人 {', '.join(draft.participants)}，备注 {draft.note}"
                        ),
                    }
                )
                conversation.append({"role": "user", "content": answer})

                console.print("[dim]⏳ 重新解析中...[/dim]")
                try:
                    drafts = client.parse_transaction(conversation)
                except OpenAIClientError as exc:
                    console.print(f"[red]❌ {exc}[/red]")
                    break

                if not drafts:
                    console.print("[yellow]⚠️ 无法解析，请重新描述。[/yellow]")
                    break

                draft = drafts[0]
                console.print()
                _render_draft(draft)
