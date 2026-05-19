"""TransactionRepository — CRUD + filter operations on the transactions table.

Depends on scripts/db.py (TES-36) for the SQLite connection and schema.
All SQL uses parameterized queries; no string interpolation of user data.
"""

from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional

from our_family_ledger.models import Transaction


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class TransactionRepository:
    """CRUD operations for the transactions table."""

    def __init__(self, conn: sqlite3.Connection) -> None:
        self._conn = conn

    # ------------------------------------------------------------------
    # Create
    # ------------------------------------------------------------------

    def insert(self, tx: Transaction) -> Transaction:
        """Insert a new transaction. Returns the same transaction."""
        self._conn.execute(
            """
            INSERT INTO transactions
                (id, created_at, updated_at, date, amount, type, category,
                 payer, participants, note, merchant, source, ocr_text, currency)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                tx.id, tx.created_at, tx.updated_at, tx.date,
                str(tx.amount_decimal), tx.type, tx.category,
                tx.payer, tx.participants, tx.note, tx.merchant,
                tx.source, tx.ocr_text, tx.currency,
            ),
        )
        self._conn.commit()
        return tx

    # ------------------------------------------------------------------
    # Read
    # ------------------------------------------------------------------

    def find_by_prefix(self, id_prefix: str) -> list[Transaction]:
        """Return transactions whose id starts with id_prefix."""
        rows = self._conn.execute(
            "SELECT * FROM transactions WHERE id LIKE ?",
            (id_prefix + "%",),
        ).fetchall()
        return [Transaction.from_row(r) for r in rows]

    def query(
        self,
        month: Optional[str] = None,
        category: Optional[str] = None,
        payer: Optional[str] = None,
        member: Optional[str] = None,
        min_amount: Optional[Decimal] = None,
        max_amount: Optional[Decimal] = None,
        tx_type: Optional[str] = None,
        limit: int = 50,
    ) -> list[Transaction]:
        """Return transactions matching the given filters."""
        conditions: list[str] = []
        params: list = []

        if month:
            conditions.append("date LIKE ?")
            params.append(f"{month}%")
        if category:
            conditions.append("category = ?")
            params.append(category)
        if payer:
            conditions.append("payer = ?")
            params.append(payer)
        if member:
            # match payer OR participants
            conditions.append("(payer = ? OR participants LIKE ?)")
            params.extend([member, f"%{member}%"])
        if tx_type:
            conditions.append("type = ?")
            params.append(tx_type)
        if min_amount is not None:
            conditions.append("CAST(amount AS REAL) >= ?")
            params.append(float(min_amount))
        if max_amount is not None:
            conditions.append("CAST(amount AS REAL) <= ?")
            params.append(float(max_amount))

        where = " AND ".join(conditions) if conditions else "1"
        sql = (
            f"SELECT * FROM transactions WHERE {where} "
            f"ORDER BY date DESC, created_at DESC LIMIT ?"
        )
        params.append(limit)

        rows = self._conn.execute(sql, params).fetchall()
        return [Transaction.from_row(r) for r in rows]

    # ------------------------------------------------------------------
    # Update
    # ------------------------------------------------------------------

    def update(self, tx_id: str, **fields) -> None:
        """Update arbitrary fields on a transaction. Sets updated_at = now."""
        if not fields:
            return
        fields["updated_at"] = _now_iso()
        set_clause = ", ".join(f"{k} = ?" for k in fields)
        values = list(fields.values()) + [tx_id]
        self._conn.execute(
            f"UPDATE transactions SET {set_clause} WHERE id = ?",  # noqa: S608
            values,
        )
        self._conn.commit()

    # ------------------------------------------------------------------
    # Delete
    # ------------------------------------------------------------------

    def delete(self, tx_id: str) -> None:
        """Delete a transaction by full ID."""
        self._conn.execute("DELETE FROM transactions WHERE id = ?", (tx_id,))
        self._conn.commit()
