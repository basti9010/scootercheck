"""Authorization roles for MCP / Dev Center tool dispatch."""

from __future__ import annotations

from enum import Enum


class Role(str, Enum):
    READ = "READ"
    TASK_WRITE = "TASK_WRITE"
    APPROVAL = "APPROVAL"
    ADMIN = "ADMIN"


# Each role may invoke tools whose required role is in this set.
_GRANTS: dict[Role, frozenset[Role]] = {
    Role.READ: frozenset({Role.READ}),
    Role.TASK_WRITE: frozenset({Role.READ, Role.TASK_WRITE}),
    Role.APPROVAL: frozenset({Role.READ, Role.APPROVAL}),
    Role.ADMIN: frozenset({Role.READ, Role.TASK_WRITE, Role.APPROVAL, Role.ADMIN}),
}


def parse_role(name: str) -> Role:
    key = (name or "").strip().upper()
    try:
        return Role(key)
    except ValueError as exc:
        raise ValueError(f"unknown role: {name!r}") from exc


def can_invoke(have: Role, need: Role) -> bool:
    """Return True if holder role may invoke a tool requiring ``need``."""
    return need in _GRANTS[have]
