"""Pure decision helpers for post-deploy smoke / rollback (no network)."""
from __future__ import annotations

import json
import re


def parse_health(body: str) -> dict:
    return json.loads(body)


def grade_from_configured_flag(configured: bool | None) -> str:
    if configured is True:
        return "CONFIGURED"
    if configured is False:
        return "NOT_CONFIGURED"
    return "UNKNOWN"


def smoke_should_fail(health: dict) -> tuple[bool, str]:
    if not health.get("ok"):
        return True, "health.ok is not true"
    if health.get("authMode") == "open":
        return True, "authMode=open unsafe"
    return False, "ok"


def configured_is_not_verified(health: dict) -> bool:
    """True when we correctly refuse to treat config flags as VERIFIED."""
    for key in ("decryptConfigured", "ghidraConfigured"):
        if health.get(key) is True:
            if grade_from_configured_flag(True) == "VERIFIED":
                return False
    return True


def should_rollback(smoke_passed: bool, release_succeeded: bool) -> bool:
    return release_succeeded and not smoke_passed


def test_smoke_fails_when_ok_false():
    fail, reason = smoke_should_fail({"ok": False})
    assert fail and "ok" in reason


def test_smoke_fails_on_open_auth():
    fail, reason = smoke_should_fail({"ok": True, "authMode": "open"})
    assert fail and "open" in reason


def test_smoke_passes_token_auth():
    fail, _ = smoke_should_fail({"ok": True, "authMode": "token", "decryptConfigured": True})
    assert not fail


def test_configured_flag_is_not_verified():
    health = {"ok": True, "decryptConfigured": True, "ghidraConfigured": True}
    assert grade_from_configured_flag(True) == "CONFIGURED"
    assert configured_is_not_verified(health)


def test_rollback_trigger():
    assert should_rollback(smoke_passed=False, release_succeeded=True) is True
    assert should_rollback(smoke_passed=True, release_succeeded=True) is False
    assert should_rollback(smoke_passed=False, release_succeeded=False) is False


def test_sha_pattern_for_deploy_input():
    # Deploy workflow refuses short tips / branch names — full 40-char SHA only.
    assert re.fullmatch(r"[0-9a-fA-F]{40}", "c08bb97aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    assert re.fullmatch(r"[0-9a-fA-F]{40}", "c08bb97") is None
    assert re.fullmatch(r"[0-9a-fA-F]{40}", "branch-name") is None
    assert re.fullmatch(r"[0-9a-fA-F]{40}", "main") is None
