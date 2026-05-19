"""Database initialization and connection management for Our Family Ledger.

This module implements TES-36: SQLite database infrastructure.
"""

from __future__ import annotations

import sqlite3
import uuid
from pathlib import Path
from datetime import datetime, timezone

DEFAULT_DB_PATH = Path.home() / ".our-family-ledger" / "data.db"

EXPENSE_CATEGORIES = [
    ("餐饮", "fork.knife", "orange"),
    ("购物", "cart", "pink"),
    ("交通", "car", "blue"),
    ("娱乐", "gamecontroller", "purple"),
    ("医疗", "heart.text.square", "red"),
    ("居家", "house", "green"),
    ("服装", "bag", "yellow"),
    ("教育", "book", "indigo"),
    ("运动", "figure.run", "green"),
    ("旅行", "airplane", "teal"),
    ("宠物", "pawprint", "brown"),
    ("数码", "laptopcomputer", "gray"),
    ("美容", "scissors", "pink"),
    ("礼物", "gift", "red"),
    ("话费", "phone", "blue"),
    ("水电", "bolt", "yellow"),
    ("房租", "building.2", "orange"),
    ("保险", "shield", "gray"),
    ("贷款", "banknote", "red"),
    ("投资", "chart.line.uptrend.xyaxis", "green"),
    ("公益", "hand.raised.fingers.spread", "teal"),
    ("零食", "cup.and.saucer", "orange"),
    ("酒水", "wineglass", "purple"),
    ("外卖", "bag.fill", "red"),
    ("健身", "dumbbell", "blue"),
    ("书籍", "books.vertical", "brown"),
    ("音乐", "music.note", "purple"),
    ("影视", "film", "orange"),
    ("游戏", "gamecontroller.fill", "indigo"),
    ("社交", "person.2", "blue"),
    ("停车", "parkingsign", "gray"),
    ("其他", "ellipsis.circle", "gray"),
]

INCOME_CATEGORIES = [
    ("工资", "dollarsign.circle", "green"),
    ("奖金", "star", "yellow"),
    ("投资收益", "chart.bar.xaxis", "blue"),
    ("兼职", "briefcase", "orange"),
    ("其他收入", "plus.circle", "gray"),
]


def _namespace_uuid(name: str) -> str:
    """Generate a stable UUID based on name."""
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, name))


def get_db(path: Path | None = None) -> sqlite3.Connection:
    """Open an existing database connection.

    Args:
        path: Path to the database file. Defaults to ~/.our-family-ledger/data.db.

    Returns:
        SQLite connection with row_factory set to sqlite3.Row.
    """
    db_path = Path(path) if path else DEFAULT_DB_PATH
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def init_db(path: Path | None = None) -> sqlite3.Connection:
    """Initialize the database: create tables and seed default data.

    This is idempotent — safe to call multiple times.

    Args:
        path: Path to the database file. Defaults to ~/.our-family-ledger/data.db.

    Returns:
        SQLite connection with row_factory set to sqlite3.Row.
    """
    db_path = Path(path) if path else DEFAULT_DB_PATH
    db_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")

    cursor = conn.cursor()

    # transactions table — columns aligned with iOS TransactionCSV.headers
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            date TEXT NOT NULL,
            amount TEXT NOT NULL,
            type TEXT NOT NULL,
            category_id TEXT NOT NULL DEFAULT '',
            payer_id TEXT NOT NULL DEFAULT '',
            participant_ids TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            merchant TEXT NOT NULL DEFAULT '',
            source TEXT NOT NULL DEFAULT 'manual',
            ocr_text TEXT,
            currency TEXT NOT NULL DEFAULT 'CNY'
        )
    """)

    # members table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS members (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
    """)

    # categories table — columns aligned with iOS CategoryCSV.headers
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            icon TEXT NOT NULL DEFAULT 'tag',
            color TEXT NOT NULL DEFAULT 'gray',
            is_default INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)

    # Seed default expense categories
    now = datetime.now(timezone.utc).isoformat()
    for i, (name, icon, color) in enumerate(EXPENSE_CATEGORIES):
        cat_id = _namespace_uuid(f"expense:{name}")
        cursor.execute("""
            INSERT OR IGNORE INTO categories (id, name, type, icon, color, is_default, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)
        """, (cat_id, name, "支出", icon, color, i, now, now))

    # Seed default income categories
    for i, (name, icon, color) in enumerate(INCOME_CATEGORIES):
        cat_id = _namespace_uuid(f"income:{name}")
        cursor.execute("""
            INSERT OR IGNORE INTO categories (id, name, type, icon, color, is_default, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)
        """, (cat_id, name, "收入", icon, color, i, now, now))

    conn.commit()
    return conn
