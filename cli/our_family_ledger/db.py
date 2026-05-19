"""OurFamilyLedger SQLite database infrastructure.

Provides init_db() and get_db() for creating and opening the family ledger database.
Database path: ~/.our-family-ledger/data.db (overridable via path parameter).

Schema is CSV-compatible with the original iOS OurFamilyLedger project:
  - transactions: 14 columns matching TransactionCSV.headers
  - members:      3 columns matching MemberCSV.headers (minimal set for this story)
  - categories:   9 columns matching CategoryCSV.headers + extras
"""

import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Default paths
# ---------------------------------------------------------------------------

DEFAULT_DB_DIR = Path("~/.our-family-ledger").expanduser()
DEFAULT_DB_PATH = DEFAULT_DB_DIR / "data.db"

# ---------------------------------------------------------------------------
# Seed data — migrated from Swift enums (DefaultExpenseCategory / DefaultIncomeCategory)
# ---------------------------------------------------------------------------

# (name, icon, color, type, sort_order)
_DEFAULT_EXPENSE_CATEGORIES = [
    ("餐饮", "fork.knife", "gray", "支出", 0),
    ("购物", "bag", "gray", "支出", 1),
    ("日用", "toilet.fill", "gray", "支出", 2),
    ("交通", "bus", "gray", "支出", 3),
    ("蔬菜", "carrot", "gray", "支出", 4),
    ("水果", "leaf", "gray", "支出", 5),
    ("零食", "birthday.cake", "gray", "支出", 6),
    ("运动", "bicycle", "gray", "支出", 7),
    ("娱乐", "music.mic", "gray", "支出", 8),
    ("通讯", "phone", "gray", "支出", 9),
    ("服饰", "tshirt", "gray", "支出", 10),
    ("美容", "paintbrush", "gray", "支出", 11),
    ("住房", "house", "gray", "支出", 12),
    ("居家", "sofa", "gray", "支出", 13),
    ("孩子", "figure.2.and.child.holdinghands", "gray", "支出", 14),
    ("长辈", "figure.walk", "gray", "支出", 15),
    ("社交", "bubble.left.and.bubble.right", "gray", "支出", 16),
    ("旅行", "airplane", "gray", "支出", 17),
    ("烟酒", "wineglass", "gray", "支出", 18),
    ("数码", "cable.connector", "gray", "支出", 19),
    ("汽车", "car", "gray", "支出", 20),
    ("医疗", "cross.case", "gray", "支出", 21),
    ("书籍", "book", "gray", "支出", 22),
    ("学习", "graduationcap", "gray", "支出", 23),
    ("宠物", "pawprint", "gray", "支出", 24),
    ("礼金", "yensign.circle", "gray", "支出", 25),
    ("礼物", "gift", "gray", "支出", 26),
    ("办公", "briefcase", "gray", "支出", 27),
    ("维修", "wrench", "gray", "支出", 28),
    ("捐赠", "heart", "gray", "支出", 29),
    ("彩票", "ticket", "gray", "支出", 30),
    ("亲友", "person.3", "gray", "支出", 31),
]

_DEFAULT_INCOME_CATEGORIES = [
    ("工资", "yensign.square", "gray", "收入", 0),
    ("兼职", "clock.badge.checkmark", "gray", "收入", 1),
    ("理财", "chart.line.uptrend.xyaxis", "gray", "收入", 2),
    ("礼金", "dollarsign.square", "gray", "收入", 3),
    ("其它", "bag", "gray", "收入", 4),
]

# Stable UUID5 namespace for deterministic category IDs
_CATEGORY_NS = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")  # uuid.NAMESPACE_DNS


def _category_id(name: str, type_: str) -> str:
    """Return a deterministic UUID5 for a category (idempotent across calls)."""
    return str(uuid.uuid5(_CATEGORY_NS, f"{type_}:{name}"))


# ---------------------------------------------------------------------------
# DDL
# ---------------------------------------------------------------------------

_DDL_TRANSACTIONS = """
CREATE TABLE IF NOT EXISTS transactions (
    id          TEXT PRIMARY KEY,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    date        TEXT NOT NULL,
    amount      TEXT NOT NULL,
    type        TEXT NOT NULL,
    category    TEXT NOT NULL DEFAULT '',
    payer       TEXT NOT NULL DEFAULT '',
    participants TEXT NOT NULL DEFAULT '',
    note        TEXT NOT NULL DEFAULT '',
    merchant    TEXT NOT NULL DEFAULT '',
    source      TEXT NOT NULL DEFAULT 'manual',
    ocr_text    TEXT,
    currency    TEXT NOT NULL DEFAULT 'CNY'
)
"""

_DDL_MEMBERS = """
CREATE TABLE IF NOT EXISTS members (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    created_at  TEXT NOT NULL
)
"""

_DDL_CATEGORIES = """
CREATE TABLE IF NOT EXISTS categories (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    type        TEXT NOT NULL,
    icon        TEXT NOT NULL DEFAULT 'tag',
    color       TEXT NOT NULL DEFAULT 'gray',
    is_default  INTEGER NOT NULL DEFAULT 1,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
)
"""

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def init_db(path: str | None = None) -> sqlite3.Connection:
    """Initialise the family ledger database.

    Creates ~/.our-family-ledger/ if it does not exist, creates all tables
    (idempotent — safe to call multiple times), and seeds the 37 default
    categories on first run.

    Args:
        path: Optional override for the database file path.
              Defaults to ~/.our-family-ledger/data.db.

    Returns:
        An open sqlite3.Connection with row_factory = sqlite3.Row.
    """
    db_path = Path(path) if path else DEFAULT_DB_PATH
    db_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")

    conn.execute(_DDL_TRANSACTIONS)
    conn.execute(_DDL_MEMBERS)
    conn.execute(_DDL_CATEGORIES)
    conn.commit()

    _migrate_categories(conn)
    _seed_categories(conn)

    return conn


def get_db(path: str | None = None) -> sqlite3.Connection:
    """Open an existing family ledger database without rebuilding schema.

    Args:
        path: Optional override for the database file path.
              Defaults to ~/.our-family-ledger/data.db.

    Returns:
        An open sqlite3.Connection with row_factory = sqlite3.Row.

    Raises:
        FileNotFoundError: If the database file does not exist.
    """
    db_path = Path(path) if path else DEFAULT_DB_PATH
    if not db_path.exists():
        raise FileNotFoundError(
            f"Database not found at {db_path}. Run init_db() first."
        )
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _migrate_categories(conn: sqlite3.Connection) -> None:
    """Add missing columns to categories table (idempotent schema migration)."""
    now = datetime.now(timezone.utc).isoformat()
    existing_cols = {
        row[1]
        for row in conn.execute("PRAGMA table_info(categories)").fetchall()
    }
    migrations = [
        ("color", "TEXT NOT NULL DEFAULT 'gray'"),
        ("is_default", "INTEGER NOT NULL DEFAULT 1"),
        ("sort_order", "INTEGER NOT NULL DEFAULT 0"),
        ("created_at", f"TEXT NOT NULL DEFAULT '{now}'"),
        ("updated_at", f"TEXT NOT NULL DEFAULT '{now}'"),
    ]
    for col_name, col_def in migrations:
        if col_name not in existing_cols:
            conn.execute(f"ALTER TABLE categories ADD COLUMN {col_name} {col_def}")
    conn.commit()


def _seed_categories(conn: sqlite3.Connection) -> None:
    """Insert default categories using INSERT OR IGNORE (idempotent)."""
    now = datetime.now(timezone.utc).isoformat()
    rows = []
    for name, icon, color, type_, sort_order in (
        _DEFAULT_EXPENSE_CATEGORIES + _DEFAULT_INCOME_CATEGORIES
    ):
        rows.append(
            (
                _category_id(name, type_),
                name,
                type_,
                icon,
                color,
                1,          # is_default
                sort_order,
                now,
                now,
            )
        )
    conn.executemany(
        """
        INSERT OR IGNORE INTO categories
            (id, name, type, icon, color, is_default, sort_order, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )
    conn.commit()
