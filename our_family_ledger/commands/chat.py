"""ledger chat — AI-assisted REPL for natural-language expense entry."""

from __future__ import annotations

from typing import Callable

import typer
from rich import print as rprint
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

from our_family_ledger.ai.openai_client import AIConfig, OpenAIClient, OpenAIError
from our_family_ledger.ai.prompts import TransactionDraft
from our_family_ledger.config import load_ai_config, save_ai_config

console = Console()

# ---------------------------------------------------------------------------
# Draft display
# ---------------------------------------------------------------------------

TYPE_LABELS = {"expense": "支出", "income": "收入"}
CURRENCY_SYMBOL = "¥"


def _display_draft(draft: TransactionDraft) -> None:
    """Render a TransactionDraft as a rich Table."""
    table = Table(show_header=False, box=None, padding=(0, 1))
    table.add_column("field", style="dim", no_wrap=True)
    table.add_column("value", style="bold")

    amount_str = f"{CURRENCY_SYMBOL}{draft.amount:.2f}"
    type_str = TYPE_LABELS.get(draft.type, draft.type)
    participants_str = ", ".join(draft.participants) if draft.participants else "—"

    table.add_row("金额", amount_str)
    table.add_row("类型", type_str)
    table.add_row("分类", draft.category)
    table.add_row("付款人", draft.payer)
    table.add_row("参与人", participants_str)
    table.add_row("备注", draft.note or "—")
    if draft.merchant:
        table.add_row("商家", draft.merchant)
    table.add_row("日期", draft.date)

    console.print(table)


# ---------------------------------------------------------------------------
# Config wizard
# ---------------------------------------------------------------------------

def _run_config_wizard() -> AIConfig:
    """Interactive wizard to collect AI config and persist it."""
    rprint(Panel("[bold]首次配置 AI 记账助手[/bold]", expand=False))
    rprint("[dim]直接回车使用括号内的默认值[/dim]\n")

    provider = typer.prompt("AI provider", default="openai")
    endpoint = typer.prompt("API endpoint", default="https://api.openai.com/v1")
    model = typer.prompt("Model name", default="gpt-4o-mini")
    api_key = typer.prompt("API key", hide_input=True)

    cfg = AIConfig(provider=provider, endpoint=endpoint, model=model, api_key=api_key)
    save_ai_config(cfg)
    rprint("[green]✓ 配置已保存[/green]\n")
    return cfg


# ---------------------------------------------------------------------------
# REPL
# ---------------------------------------------------------------------------

def _run_chat_loop(
    client: OpenAIClient,
    save_fn: Callable[[TransactionDraft], None],
) -> None:
    """Core REPL loop — extracted for testability."""

    rprint("[bold]💬 家庭记账助手[/bold] [dim]（输入 quit 退出）[/dim]")

    conversation: list[dict] = []

    while True:
        try:
            user_input = typer.prompt("\n💬 >", prompt_suffix=" ")
        except (EOFError, KeyboardInterrupt):
            rprint("\n[dim]再见！[/dim]")
            break

        if user_input.strip().lower() in ("quit", "exit", "q", "退出"):
            rprint("[dim]再见！[/dim]")
            break

        if not user_input.strip():
            continue

        conversation.append({"role": "user", "content": user_input.strip()})

        rprint("[dim]⏳ 解析中...[/dim]")

        try:
            drafts = client.parse_transaction(list(conversation))
        except OpenAIError as exc:
            rprint(f"[red]错误：{exc}[/red]")
            # Remove last user message from history to allow retry
            conversation.pop()
            continue

        if not drafts:
            rprint("[yellow]无法解析交易信息，请换个说法再试。[/yellow]")
            conversation.pop()
            continue

        # For multi-draft responses, process each one
        for draft in drafts:
            _display_draft(draft)
            rprint("")

            confirmed = False
            while True:
                try:
                    answer = typer.prompt(
                        "确认入账? [y/n/修正]", prompt_suffix=" "
                    ).strip().lower()
                except (EOFError, KeyboardInterrupt):
                    rprint("\n[dim]已取消[/dim]")
                    break

                if answer in ("y", "yes", "是", "确认", "ok"):
                    save_fn(draft)
                    rprint(
                        f"[green]✅ 已入账 {CURRENCY_SYMBOL}{draft.amount:.2f} {draft.category}[/green]"
                    )
                    confirmed = True
                    break
                elif answer in ("n", "no", "否", "取消"):
                    rprint("[yellow]已跳过[/yellow]")
                    confirmed = True
                    break
                else:
                    # User typed a correction — add as new user message and re-parse
                    correction = answer if len(answer) > 2 else None
                    if correction is None:
                        try:
                            correction = typer.prompt(
                                "请输入修正内容", prompt_suffix=" "
                            ).strip()
                        except (EOFError, KeyboardInterrupt):
                            rprint("\n[dim]已取消[/dim]")
                            confirmed = True
                            break

                    conversation.append({"role": "user", "content": correction})
                    rprint("[dim]⏳ 重新解析...[/dim]")

                    try:
                        new_drafts = client.parse_transaction(list(conversation))
                    except OpenAIError as exc:
                        rprint(f"[red]错误：{exc}[/red]")
                        conversation.pop()
                        continue

                    if not new_drafts:
                        rprint("[yellow]仍无法解析，请重新描述。[/yellow]")
                        conversation.pop()
                        continue

                    # Show updated draft and loop again
                    draft = new_drafts[0]
                    _display_draft(draft)
                    rprint("")
                    continue

            if not confirmed:
                break

        # Add assistant acknowledgment to history for context continuity
        conversation.append(
            {"role": "assistant", "content": f"已处理 {len(drafts)} 笔交易"}
        )


# ---------------------------------------------------------------------------
# Click / Typer command
# ---------------------------------------------------------------------------

def chat() -> None:
    """AI 自然语言记账：对话输入，自动解析并确认入账。"""
    # Load or wizard-configure AI settings
    try:
        ai_config = load_ai_config()
    except Exception:
        ai_config = AIConfig()

    if not ai_config.api_key:
        ai_config = _run_config_wizard()

    client = OpenAIClient(ai_config)

    def _save(draft: TransactionDraft) -> None:
        """Persist a confirmed draft. (TransactionRepository integration point.)"""
        # TODO: integrate with TransactionRepository.create() (TES-38)
        # For now, we simply acknowledge — storage will be wired in a follow-up.
        pass

    _run_chat_loop(client, _save)
