"""Root typer app — registers all sub-commands and runs ensure_initialized."""

from __future__ import annotations

import typer

from our_family_ledger.config import ensure_initialized
from our_family_ledger.commands import members as members_cmd
from our_family_ledger.commands import setup as setup_cmd
from our_family_ledger.commands import report as report_cmd

app = typer.Typer(
    name="ledger",
    help="OurFamilyLedger CLI — family expense tracker backed by SQLite.",
    no_args_is_help=True,
)


@app.callback()
def _callback() -> None:
    """Bootstrap data directory and DB on every invocation."""
    ensure_initialized()


# Register sub-command groups
app.add_typer(members_cmd.app, name="members", help="Manage family members.")
app.add_typer(report_cmd.app, name="report", help="Monthly statistics report.")

# Register standalone commands
app.command("setup")(setup_cmd.setup)


def main() -> None:  # pragma: no cover
    app()
