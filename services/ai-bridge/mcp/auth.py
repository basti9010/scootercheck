"""Bearer-token auth for MCP tool calls.

No anonymous write (and Phase A: no anonymous tool dispatch at all).
Tokens are mapped to roles via env ``AIBRIDGE_TOKENS`` JSON or an in-memory
registry (tests). Token values must never appear in tool results.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Mapping

from .roles import Role, can_invoke, parse_role


class AuthError(Exception):
    def __init__(self, status_code: int, detail: str) -> None:
        self.status_code = status_code
        self.detail = detail
        super().__init__(detail)


@dataclass(frozen=True)
class Principal:
    subject: str
    role: Role


class TokenRegistry:
    """Maps opaque bearer tokens → Principal.

    Env format (optional):
      AIBRIDGE_TOKENS='{"tok_read":{"sub":"reader","role":"READ"},...}'
    """

    def __init__(self, mapping: Mapping[str, Principal] | None = None) -> None:
        self._tokens: dict[str, Principal] = dict(mapping or {})

    @classmethod
    def from_env(cls) -> TokenRegistry:
        raw = os.environ.get("AIBRIDGE_TOKENS", "").strip()
        if not raw:
            return cls()
        data = json.loads(raw)
        mapping: dict[str, Principal] = {}
        for token, meta in data.items():
            mapping[str(token)] = Principal(
                subject=str(meta["sub"]),
                role=parse_role(str(meta["role"])),
            )
        return cls(mapping)

    def register(self, token: str, principal: Principal) -> None:
        if not token or not token.strip():
            raise ValueError("empty token")
        self._tokens[token] = principal

    def resolve(self, authorization: str | None) -> Principal:
        if authorization is None or not str(authorization).strip():
            raise AuthError(401, "missing authorization")
        value = str(authorization).strip()
        if value.lower().startswith("bearer "):
            token = value[7:].strip()
        else:
            token = value
        if not token:
            raise AuthError(401, "missing bearer token")
        principal = self._tokens.get(token)
        if principal is None:
            raise AuthError(401, "invalid token")
        return principal

    def require_role(self, authorization: str | None, need: Role) -> Principal:
        principal = self.resolve(authorization)
        if not can_invoke(principal.role, need):
            raise AuthError(
                403,
                f"role {principal.role.value} cannot invoke requires={need.value}",
            )
        return principal
