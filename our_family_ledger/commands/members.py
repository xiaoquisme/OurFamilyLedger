"""ledger members — add / list / remove family members."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

import typer
from rich import print as rprint
from rich.table import Table

from our_family_ledger.config import get_connection

app = typer.Typer(no_args_is_help=True)

VALID_ROLES = ("admin", "member")
VALID_COLORS = ("blue", "green", "orange", "purple", "pink", "red", "yellow", "teal")

ROLE_DISPLAY = {
    "admin": "管理员",
    "member": "成员",
}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


@app.command("add")
def members_add(
    name: str = typer.Argument(..., help="成员姓名"),
    nickname: str = typer.Option("", "--nickname", "-n", help="昵称（默认同姓名）"),
    role: str = typer.Option(
        "member", "--role", "-r", help="角色: admin 或 member"
    ),
    color: str = typer.Option(
        "blue", "--color", "-c", help="头像颜色 (blue/green/orange/...)"
    ),
    current_user: bool = typer.Option(
        False, "--current-user", help="标记为当前用户"
    ),
) -> None:
    """添加家庭成员。"""
    if role not in VALID_ROLES:
        rprint(f"[red]Error:[/red] role 必须是 {VALID_ROLES} 之一")
        raise typer.Exit(code=1)
    if color not in VALID_COLORS:
        rprint(f"[red]Error:[/red] color 必须是 {VALID_COLORS} 之一")
        raise typer.Exit(code=1)

    member_id = str(uuid.uuid4())
    now = _now()
    nick = nickname if nickname else name

    with get_connection() as conn:
        conn.execute(
            """
            INSERT INTO members (id, name, nickname, role, avatar_color, is_current_user, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (member_id, name, nick, role, color, int(current_user), now, now),
        )
        conn.commit()

    rprint(f"[green]✓[/green] 成员 [bold]{name}[/bold] 已添加 (id: {member_id[:8]}...)")


@app.command("list")
def members_list() -> None:
    """列出所有家庭成员。"""
    with get_connection() as conn:
        rows = conn.execute(
            "SELECT id, name, nickname, role, avatar_color, is_current_user, created_at FROM members ORDER BY created_at"
        ).fetchall()

    if not rows:
        rprint("[yellow]暂无成员。使用 ledger members add <name> 添加。[/yellow]")
        return

    table = Table(title="家庭成员", show_lines=True)
    table.add_column("ID (前8位)", style="dim")
    table.add_column("姓名", style="bold")
    table.add_column("昵称")
    table.add_column("角色")
    table.add_column("头像色")
    table.add_column("当前用户")
    table.add_column("创建时间", style="dim")

    for row in rows:
        table.add_row(
            row["id"][:8],
            row["name"],
            row["nickname"],
            ROLE_DISPLAY.get(row["role"], row["role"]),
            row["avatar_color"],
            "✓" if row["is_current_user"] else "",
            row["created_at"][:10],
        )

    from rich.console import Console
    Console().print(table)


@app.command("remove")
def members_remove(
    name_or_id: str = typer.Argument(..., help="成员姓名或 UUID 前缀"),
) -> None:
    """移除家庭成员（按姓名精确匹配或 UUID 前缀）。"""
    with get_connection() as conn:
        # Try exact name match first
        row = conn.execute(
            "SELECT id, name FROM members WHERE name = ?", (name_or_id,)
        ).fetchone()
        if row is None:
            # Try UUID prefix match
            row = conn.execute(
                "SELECT id, name FROM members WHERE id LIKE ?",
                (name_or_id + "%",),
            ).fetchone()
        if row is None:
            rprint(f"[red]Error:[/red] 找不到成员 '{name_or_id}'")
            raise typer.Exit(code=1)

        conn.execute("DELETE FROM members WHERE id = ?", (row["id"],))
        conn.commit()

    rprint(f"[green]✓[/green] 成员 [bold]{row['name']}[/bold] 已移除")
