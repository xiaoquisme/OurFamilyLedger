"""CLI entry point for Our Family Ledger."""

from __future__ import annotations

import typer

app = typer.Typer(
    name="ledger",
    help="Our Family Ledger — family bookkeeping CLI.",
    no_args_is_help=True,
)

# Register sub-commands
from our_family_ledger.commands import report  # noqa: E402

app.add_typer(report.app, name="report")


def main() -> None:
    app()


if __name__ == "__main__":
    main()
