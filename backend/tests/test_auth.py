"""ScooterCheck Auth API — P0 recovery tests (error codes, JWT, refresh absence)."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
import pytest
from fastapi.testclient import TestClient

from app.errors import (
    ACCOUNT_NOT_ACTIVE,
    DOMAIN_NOT_ALLOWED,
    EMAIL_TAKEN,
    INVALID_CREDENTIALS,
    NOT_AUTHENTICATED,
    REGISTRATION_LOCKED,
    TOKEN_EXPIRED,
    TOKEN_INVALID,
)


def _settings():
    """Use reloaded settings from the client fixture (env applied at reload)."""
    import app.settings as settings_mod

    return settings_mod.settings


def _login(client: TestClient, email: str, password: str):
    return client.post("/auth/login", json={"email": email, "password": password})


def test_health(client: TestClient) -> None:
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["service"] == "scootercheck-auth"


def test_login_invalid_credentials_has_code(client: TestClient) -> None:
    r = _login(client, "admin@example.com", "totally-wrong-password")
    assert r.status_code == 401
    body = r.json()
    assert body["detail"] == "E-Mail oder Passwort falsch"
    assert body["code"] == INVALID_CREDENTIALS


def test_login_unknown_user_same_shape(client: TestClient) -> None:
    r = _login(client, "nobody@example.com", "whatever-pass")
    assert r.status_code == 401
    assert r.json()["code"] == INVALID_CREDENTIALS


def test_login_validation_error_is_422_not_401(client: TestClient) -> None:
    r = client.post("/auth/login", json={"email": "not-an-email", "password": "x"})
    assert r.status_code == 422
    assert "detail" in r.json()
    # Pydantic validation — distinguishable from invalid_credentials (401+code).
    assert "code" not in r.json() or r.json().get("code") != INVALID_CREDENTIALS


def test_login_success_admin_seed(client: TestClient) -> None:
    r = _login(client, "admin@example.com", "AdminPass123!")
    assert r.status_code == 200
    body = r.json()
    assert body["token_type"] == "bearer"
    assert isinstance(body["access_token"], str) and len(body["access_token"]) > 20
    assert body["user"]["email"] == "admin@example.com"
    assert body["user"]["role"] == "admin"
    assert body["user"]["status"] == "active"
    # Token must not be echoed in error paths; success payload is expected.


def test_me_requires_bearer(client: TestClient) -> None:
    r = client.get("/auth/me")
    assert r.status_code == 401
    body = r.json()
    assert body["code"] == NOT_AUTHENTICATED
    assert body["detail"] == "Nicht angemeldet"


def test_me_invalid_token(client: TestClient) -> None:
    r = client.get("/auth/me", headers={"Authorization": "Bearer not.a.jwt"})
    assert r.status_code == 401
    assert r.json()["code"] == TOKEN_INVALID


def test_me_expired_token(client: TestClient) -> None:
    cfg = _settings()
    now = datetime.now(timezone.utc)
    payload = {
        "sub": "does-not-matter",
        "email": "admin@example.com",
        "role": "admin",
        "status": "active",
        "iat": int((now - timedelta(hours=2)).timestamp()),
        "exp": int((now - timedelta(hours=1)).timestamp()),
    }
    token = jwt.encode(payload, cfg.jwt_secret, algorithm=cfg.jwt_algorithm)
    r = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 401
    body = r.json()
    assert body["code"] == TOKEN_EXPIRED
    assert body["detail"] == "Token abgelaufen"


def test_me_with_valid_token(client: TestClient) -> None:
    login = _login(client, "admin@example.com", "AdminPass123!")
    token = login.json()["access_token"]
    r = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200
    assert r.json()["email"] == "admin@example.com"


def test_jwt_claims_compatible_with_firmware_worker(client: TestClient) -> None:
    """scootercheck-fw reuses HS256 JWT with sub/email/role/status (+ exp)."""
    cfg = _settings()
    login = _login(client, "admin@example.com", "AdminPass123!")
    token = login.json()["access_token"]
    payload = jwt.decode(token, cfg.jwt_secret, algorithms=[cfg.jwt_algorithm])
    assert payload["sub"]
    assert payload["email"] == "admin@example.com"
    assert payload["role"] == "admin"
    assert payload["status"] == "active"
    assert "exp" in payload and "iat" in payload


def test_refresh_endpoint_absent(client: TestClient) -> None:
    """CONFIRMED: no /auth/refresh — clients must re-login after JWT expiry."""
    r = client.post("/auth/refresh", json={})
    assert r.status_code == 404


def test_register_locked_without_domains(client: TestClient) -> None:
    r = client.post(
        "/auth/register",
        json={
            "email": "officer@polizei.example.com",
            "password": "SecurePass1",
            "display_name": "Officer",
        },
    )
    assert r.status_code == 403
    assert r.json()["code"] == REGISTRATION_LOCKED


def test_register_domain_gate_and_pending(client: TestClient) -> None:
    admin = _login(client, "admin@example.com", "AdminPass123!")
    admin_token = admin.json()["access_token"]
    add = client.post(
        "/admin/domains",
        json={"domain": "polizei.example.com"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert add.status_code == 200

    denied = client.post(
        "/auth/register",
        json={"email": "x@other.example.com", "password": "SecurePass1"},
    )
    assert denied.status_code == 403
    assert denied.json()["code"] == DOMAIN_NOT_ALLOWED

    ok = client.post(
        "/auth/register",
        json={
            "email": "officer@polizei.example.com",
            "password": "SecurePass1",
            "display_name": "Officer",
        },
    )
    assert ok.status_code == 200
    body = ok.json()
    assert body["user"]["status"] == "pending"
    assert body["token_type"] == "bearer"

    dup = client.post(
        "/auth/register",
        json={"email": "officer@polizei.example.com", "password": "SecurePass1"},
    )
    assert dup.status_code == 409
    assert dup.json()["code"] == EMAIL_TAKEN


def test_pending_user_blocked_from_session_check(client: TestClient) -> None:
    admin = _login(client, "admin@example.com", "AdminPass123!")
    admin_token = admin.json()["access_token"]
    client.post(
        "/admin/domains",
        json={"domain": "polizei.example.com"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    reg = client.post(
        "/auth/register",
        json={"email": "wait@polizei.example.com", "password": "SecurePass1"},
    )
    token = reg.json()["access_token"]
    # /auth/me allows any authenticated user (pending OK for gate UI).
    me = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["status"] == "pending"
    # Active-only routes reject pending with account_not_active.
    check = client.get("/session/check", headers={"Authorization": f"Bearer {token}"})
    assert check.status_code == 403
    assert check.json()["code"] == ACCOUNT_NOT_ACTIVE


def test_change_password_wrong_current(client: TestClient) -> None:
    login = _login(client, "admin@example.com", "AdminPass123!")
    token = login.json()["access_token"]
    r = client.post(
        "/auth/change-password",
        json={"current_password": "wrong", "new_password": "NewSecure9"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 401
    assert r.json()["code"] == INVALID_CREDENTIALS
