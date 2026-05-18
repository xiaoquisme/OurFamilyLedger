"""Data directory, config file management, and DB initialization."""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

try:
    import tomllib
except ImportError:  # Python < 3.11
    try:
        import tomli as tomllib  # type: ignore[no-redef]
    except ImportError:
        tomllib = None  # type: ignore[assignment]

import tomli_w  # only needed for writing

DATA_DIR = Path.home() / ".our-family-ledger"
CONFIG_FILE = DATA_DIR / "config.toml"
DB_FILE = DATA_DIR / "data.db"

# ---------------------------------------------------------------------------
# DB initialisation
# ---------------------------------------------------------------------------

_CREATE_MEMBERS = """
CREATE TABLE IF NOT EXISTS members (
    id               TEXT PRIMARY KEY,
    name             TEXT NOT NULL,
    nickname         TEXT NOT NULL DEFAULT '',
    role             TEXT NOT NULL DEFAULT 'member',
    avatar_color     TEXT NOT NULL DEFAULT 'blue',
    is_current_user  INTEGER NOT NULL DEFAULT 0,
    created_at       TEXT NOT NULL,
    updated_at       TEXT NOT NULL
);
"""


def init_db(db_path: Path | None = None) -> None:
    """Create tables if they don't exist (idempotent)."""
    if db_path is None:
        db_path = DB_FILE
    conn = sqlite3.connect(db_path)
    try:
        conn.execute(_CREATE_MEMBERS)
        conn.commit()
    finally:
        conn.close()


def get_connection(db_path: Path | None = None) -> sqlite3.Connection:
    if db_path is None:
        db_path = DB_FILE
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


# ---------------------------------------------------------------------------
# Directory + DB bootstrap
# ---------------------------------------------------------------------------


def ensure_initialized() -> None:
    """Create ~/.our-family-ledger/ and initialise the DB (idempotent)."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    init_db()


# ---------------------------------------------------------------------------
# Config read/write
# ---------------------------------------------------------------------------


def read_config() -> dict:
    """Return parsed config.toml, or empty dict if not present."""
    if not CONFIG_FILE.exists():
        return {}
    if tomllib is None:
        print(
            "[yellow]Warning:[/yellow] tomllib not available; install tomli for Python < 3.11",
            file=sys.stderr,
        )
        return {}
    with open(CONFIG_FILE, "rb") as f:
        return tomllib.load(f)


def write_config(data: dict) -> None:
    """Serialise *data* to config.toml using tomli-w."""
    try:
        import tomli_w as _tomli_w
    except ImportError:
        # Fallback: write a minimal TOML manually
        lines: list[str] = []
        for section, values in data.items():
            lines.append(f"[{section}]")
            for k, v in values.items():
                if isinstance(v, str):
                    lines.append(f'{k} = "{v}"')
                elif isinstance(v, bool):
                    lines.append(f"{k} = {str(v).lower()}")
                else:
                    lines.append(f"{k} = {v}")
            lines.append("")
        CONFIG_FILE.write_text("\n".join(lines), encoding="utf-8")
        return
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    toml_str = _tomli_w.dumps(data)
    if isinstance(toml_str, str):
        CONFIG_FILE.write_text(toml_str, encoding="utf-8")
    else:
        CONFIG_FILE.write_bytes(toml_str)
