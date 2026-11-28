"""Server-side session / bearer auth for AI Bridge HTTP API (v2).

Prototype: opaque bearer tokens mapped to subjects+roles via AIBRIDGE_TOKENS
or AIBRIDGE_SESSION_SECRET + signed cookies later. No Cursor keys here.
"""

from __future__ import annotations

import hmac
import hashlib
import json
import os
import secrets
import time
from dataclasses import dataclass
from typing import Mapping

from mcp.roles import Role, can_invoke, parse_role


class SessionAuthError(Exception):
    def __init__(self, status_code: int, detail: str) -> None:
        self.status_code = status_code
        self.detail = detail
        super().__init__(detail)


@dataclass(frozen=True)
class Principal:
    subject: str
    role: Role


class SessionRegistry:
    def __init__(self, mapping: Mapping[str, Principal] | None = None) -> None:
        self._tokens: dict[str, Principal] = dict(mapping or {})

    @classmethod
    def from_env(cls) -> "SessionRegistry":
        raw = os.environ.get("AIBRIDGE_TOKENS", "").strip()
        if not raw:
            # Dev-only empty registry — all requests 401 until configured
            return cls()
        data = json.loads(raw)
        mapping: dict[str, Principal] = {}
        for token, meta in data.items():
            mapping[str(token)] = Principal(
                subject=str(meta["sub"]),
                role=parse_role(str(meta["role"])),
            )
        return cls(mapping)

    def resolve(self, authorization: str | None) -> Principal:
        if not authorization or not str(authorization).strip():
            raise SessionAuthError(401, "missing authorization")
        value = str(authorization).strip()
        token = value[7:].strip() if value.lower().startswith("bearer ") else value
        if not token:
            raise SessionAuthError(401, "missing bearer token")
        principal = self._tokens.get(token)
        if principal is None:
            raise SessionAuthError(401, "invalid token")
        return principal

    def require(self, authorization: str | None, need: Role) -> Principal:
        principal = self.resolve(authorization)
        if not can_invoke(principal.role, need):
            raise SessionAuthError(
                403,
                f"role {principal.role.value} cannot invoke requires={need.value}",
            )
        return principal


def issue_dev_token() -> str:
    """Generate a random opaque token (for tests / local provisioning only)."""
    return "tok_" + secrets.token_urlsafe(24)


def csrf_token_for_session(session_id: str, secret: str) -> str:
    """HMAC CSRF token for cookie-based UIs (optional path)."""
    return hmac.new(secret.encode("utf-8"), session_id.encode("utf-8"), hashlib.sha256).hexdigest()


def rate_limit_bucket(key: str, *, window_s: int = 60, limit: int = 60, store: dict | None = None) -> bool:
    """Simple in-process rate limiter. Returns True if allowed."""
    bucket = store if store is not None else _RATE
    now = int(time.time())
    window = now // window_s
    entry = bucket.get(key)
    if entry is None or entry[0] != window:
        bucket[key] = (window, 1)
        return True
    if entry[1] >= limit:
        return False
    bucket[key] = (window, entry[1] + 1)
    return True


_RATE: dict[str, tuple[int, int]] = {}
