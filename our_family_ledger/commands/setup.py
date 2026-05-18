"""ledger setup — interactive AI provider configuration wizard."""

from __future__ import annotations

import os
from typing import Optional

import typer
from rich import print as rprint
from rich.panel import Panel

from our_family_ledger.config import CONFIG_FILE, read_config, write_config


def setup(
    non_interactive: bool = typer.Option(
        False,
        "--non-interactive",
        help="Read values from env vars instead of prompting.",
    ),
) -> None:
    """Configure AI provider, model, and API key for the ledger assistant."""

    if non_interactive:
        provider = os.environ.get("LEDGER_PROVIDER", "openai")
        endpoint = os.environ.get(
            "LEDGER_ENDPOINT", "https://api.openai.com/v1"
        )
        model = os.environ.get("LEDGER_MODEL", "gpt-4o-mini")
        api_key = os.environ.get("LEDGER_API_KEY", "")
        currency = os.environ.get("LEDGER_CURRENCY", "CNY")
        default_split_all_str = os.environ.get("LEDGER_DEFAULT_SPLIT_ALL", "true")
        default_split_all = default_split_all_str.lower() in ("1", "true", "yes")
    else:
        existing = read_config()
        ai_cfg = existing.get("ai", {})
        ledger_cfg = existing.get("ledger", {})

        rprint(Panel("[bold]OurFamilyLedger — 配置向导[/bold]", expand=False))
        rprint("[dim]直接回车使用括号内的默认值[/dim]\n")

        provider = typer.prompt(
            "AI provider (openai / anthropic / openrouter)",
            default=ai_cfg.get("provider", "openai"),
        )
        endpoint = typer.prompt(
            "API endpoint",
            default=ai_cfg.get("endpoint", "https://api.openai.com/v1"),
        )
        model = typer.prompt(
            "Model name",
            default=ai_cfg.get("model", "gpt-4o-mini"),
        )
        api_key = typer.prompt(
            "API key",
            default=ai_cfg.get("api_key", ""),
            hide_input=True,
        )
        currency = typer.prompt(
            "Default currency",
            default=ledger_cfg.get("currency", "CNY"),
        )
        default_split_all = typer.confirm(
            "Split all members by default?",
            default=ledger_cfg.get("default_split_all", True),
        )

    config = {
        "ai": {
            "provider": provider,
            "endpoint": endpoint,
            "model": model,
            "api_key": api_key,
        },
        "ledger": {
            "currency": currency,
            "default_split_all": default_split_all,
        },
    }

    write_config(config)

    masked_key = (api_key[:8] + "..." + api_key[-4:]) if len(api_key) > 12 else "***"
    rprint(
        Panel(
            f"[green]✓ 配置已保存[/green] → {CONFIG_FILE}\n\n"
            f"  provider  : {provider}\n"
            f"  endpoint  : {endpoint}\n"
            f"  model     : {model}\n"
            f"  api_key   : {masked_key}\n"
            f"  currency  : {currency}\n"
            f"  split_all : {default_split_all}",
            title="配置摘要",
            expand=False,
        )
    )
