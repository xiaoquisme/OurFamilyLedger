"""Transaction data model for OurFamilyLedger.

Mirrors the CSV column layout from the original iOS OurFamilyLedger project
(TransactionCSV struct: id, created_at, updated_at, date, amount, type, category,
payer, participants, note, merchant, source, ocr_text, currency).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date as date_type, datetime, timezone
from decimal import Decimal
import uuid


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _today_str() -> str:
    return date_type.today().isoformat()


@dataclass
class Transaction:
    """Represents one ledger transaction, aligned with CSV headers."""

    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    created_at: str = field(default_factory=_now_iso)
    updated_at: str = field(default_factory=_now_iso)
    date: str = field(default_factory=_today_str)
    amount: str = "0"          # stored as decimal string (e.g. "45.00")
    type: str = "支出"          # "支出" | "收入"
    category: str = ""
    payer: str = ""
    participants: str = ""     # semicolon-separated names
    note: str = ""
    merchant: str = ""
    source: str = "manual"
    ocr_text: str = ""
    currency: str = "CNY"

    # ------------------------------------------------------------------
    # Convenience helpers
    # ------------------------------------------------------------------

    @property
    def amount_decimal(self) -> Decimal:
        return Decimal(self.amount)

    @property
    def participants_list(self) -> list[str]:
        return [p for p in self.participants.split(";") if p]

    @classmethod
    def from_row(cls, row) -> "Transaction":
        """Construct from a sqlite3.Row (or any mapping)."""
        return cls(
            id=row["id"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            date=row["date"],
            amount=row["amount"],
            type=row["type"],
            category=row["category"],
            payer=row["payer"],
            participants=row["participants"],
            note=row["note"],
            merchant=row["merchant"],
            source=row["source"],
            ocr_text=row["ocr_text"] or "",
            currency=row["currency"],
        )
