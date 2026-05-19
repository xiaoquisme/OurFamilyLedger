---
name: our-family-ledger
description: OurFamilyLedger CLI — SQLite-backed family expense tracker with AI assistant. Use when user mentions family ledger, 家庭账本, 记账, or ledger commands.
triggers:
  - 家庭账本
  - 记账
  - ledger
  - our-family-ledger
  - family ledger
---

# OurFamilyLedger Skill

A Python CLI that replaces the original Swift iOS app, storing data in `~/.our-family-ledger/data.db` (SQLite).

## Installation

```bash
# Clone the repo
git clone https://github.com/xiaoquisme/OurFamilyLedger.git
cd OurFamilyLedger

# Install in editable mode (recommended)
pip install -e .

# OR run without installing via uvx
uvx --from our-family-ledger ledger
```

> Requires Python 3.11+. The `ledger` command is available after installation.

## First-Time Setup

```bash
ledger setup
```

Interactive wizard that writes `~/.our-family-ledger/config.toml`:

```toml
[ai]
provider = "openai"          # openai / anthropic / openrouter
endpoint = "https://api.openai.com/v1"
model    = "gpt-4o-mini"
api_key  = "sk-..."

[ledger]
currency          = "CNY"
default_split_all = true
```

Use `--non-interactive` with env vars for CI/scripted setup:

```bash
LEDGER_PROVIDER=openai \
LEDGER_ENDPOINT=https://api.openai.com/v1 \
LEDGER_MODEL=gpt-4o-mini \
LEDGER_API_KEY=sk-... \
LEDGER_CURRENCY=CNY \
ledger setup --non-interactive
```

## Command Reference

### Members

```bash
# Add a member
ledger members add <name> [--nickname X] [--role admin|member] [--color blue] [--current-user]

# List all members
ledger members list

# Remove a member (by name or UUID prefix)
ledger members remove <name-or-id>
```

**Roles**: `admin` (管理员 — can modify settings, export data) | `member` (成员 — can record and view transactions)

**Colors**: `blue` `green` `orange` `purple` `pink` `red` `yellow` `teal`

### Setup

```bash
ledger setup [--non-interactive]
```

## Data Directory Layout

```
~/.our-family-ledger/
├── config.toml   # AI provider & ledger preferences
└── data.db       # SQLite database
    └── members   # Family member records
```

## Notes for Agent

- `ensure_initialized()` is called automatically on every `ledger` invocation — no manual init needed.
- DB schema is created by `our_family_ledger.config.init_db()` (idempotent `CREATE TABLE IF NOT EXISTS`).
- iCloud sync and OCR are out of scope — do not reference them.
- If `config.toml` is missing and a command requires AI, prompt the user to run `ledger setup` first.
