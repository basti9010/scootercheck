"""Admin vs user role separation + residual JWT risks (Agent C)."""

from __future__ import annotations

import jwt
from fastapi.testclient import TestClient

from app.errors import FORBIDDEN, INVALID_CREDENTIALS


def _login(client: TestClient, email: str, password: str):
    return client.post("/auth/login", json={"email": email, "password": password})


def _admin_token(client: TestClient) -> str:
    r = _login(client, "admin@example.com", "AdminPass123!")
    assert r.status_code == 200
    return r.json()["access_token"]


def _register_pending(client: TestClient, admin_token: str, email: str) -> str:
    domain = email.split("@", 1)[1]
    add = client.post(
        "/admin/domains",
        json={"domain": domain},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert add.status_code in (200, 409)
    reg = client.post(
        "/auth/register",
        json={"email": email, "password": "UserPass123!", "display_name": "Officer"},
    )
    assert reg.status_code == 200
    return reg.json()["access_token"]


def test_user_token_forbidden_on_admin_routes(client: TestClient) -> None:
    admin = _admin_token(client)
    pending_token = _register_pending(client, admin, "rolecheck@polizei.example.com")

    # Approve so we have an active *user* (not admin).
    users = client.get("/admin/users", headers={"Authorization": f"Bearer {admin}"})
    assert users.status_code == 200
    target = next(u for u in users.json()["users"] if u["email"] == "rolecheck@polizei.example.com")
    approved = client.post(
        f"/admin/users/{target['id']}/approve",
        headers={"Authorization": f"Bearer {admin}"},
    )
    assert approved.status_code == 200

    login = _login(client, "rolecheck@polizei.example.com", "UserPass123!")
    assert login.status_code == 200
    user_token = login.json()["access_token"]
    assert login.json()["user"]["role"] == "user"

    denied = client.get("/admin/users", headers={"Authorization": f"Bearer {user_token}"})
    assert denied.status_code == 403
    assert denied.json()["code"] == FORBIDDEN


def test_disabled_user_blocked_from_session_check(client: TestClient) -> None:
    admin = _admin_token(client)
    _register_pending(client, admin, "disableme@polizei.example.com")
    users = client.get("/admin/users", headers={"Authorization": f"Bearer {admin}"})
    target = next(u for u in users.json()["users"] if u["email"] == "disableme@polizei.example.com")
    client.post(
        f"/admin/users/{target['id']}/approve",
        headers={"Authorization": f"Bearer {admin}"},
    )
    login = _login(client, "disableme@polizei.example.com", "UserPass123!")
    token = login.json()["access_token"]

    disabled = client.post(
        f"/admin/users/{target['id']}/disable",
        headers={"Authorization": f"Bearer {admin}"},
    )
    assert disabled.status_code == 200

    # JWT still cryptographically valid, but active-only route must deny.
    check = client.get("/session/check", headers={"Authorization": f"Bearer {token}"})
    assert check.status_code == 403
    # /auth/me still returns the disabled profile (gate UI).
    me = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["status"] == "disabled"


def test_password_change_does_not_revoke_existing_jwt(client: TestClient) -> None:
    """CONFIRMED residual risk: no token version / denylist — old JWT works until exp."""
    admin = _admin_token(client)
    login = _login(client, "admin@example.com", "AdminPass123!")
    old_token = login.json()["access_token"]

    changed = client.post(
        "/auth/change-password",
        json={"current_password": "AdminPass123!", "new_password": "AdminPass456!"},
        headers={"Authorization": f"Bearer {old_token}"},
    )
    assert changed.status_code == 200

    still = client.get("/auth/me", headers={"Authorization": f"Bearer {old_token}"})
    assert still.status_code == 200

    # New password works; old password fails.
    bad = _login(client, "admin@example.com", "AdminPass123!")
    assert bad.status_code == 401
    assert bad.json()["code"] == INVALID_CREDENTIALS
    good = _login(client, "admin@example.com", "AdminPass456!")
    assert good.status_code == 200


def test_forged_role_claim_ignored_for_admin(client: TestClient) -> None:
    """Authorization uses DB role via sub — forged JWT role claim must not elevate."""
    from app.settings import settings

    login = _login(client, "admin@example.com", "AdminPass123!")
    real = jwt.decode(
        login.json()["access_token"],
        settings.jwt_secret,
        algorithms=[settings.jwt_algorithm],
    )
    # Register a normal user and forge admin role in a token with their sub.
    admin = login.json()["access_token"]
    _register_pending(client, admin, "forge@polizei.example.com")
    users = client.get("/admin/users", headers={"Authorization": f"Bearer {admin}"})
    target = next(u for u in users.json()["users"] if u["email"] == "forge@polizei.example.com")
    client.post(
        f"/admin/users/{target['id']}/approve",
        headers={"Authorization": f"Bearer {admin}"},
    )
    user_login = _login(client, "forge@polizei.example.com", "UserPass123!")
    user_payload = jwt.decode(
        user_login.json()["access_token"],
        settings.jwt_secret,
        algorithms=[settings.jwt_algorithm],
    )
    forged = {
        **user_payload,
        "role": "admin",
        "status": "active",
    }
    forged_token = jwt.encode(forged, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    denied = client.get(
        "/admin/users",
        headers={"Authorization": f"Bearer {forged_token}"},
    )
    assert denied.status_code == 403
    assert denied.json()["code"] == FORBIDDEN
    # Sanity: real admin still works.
    assert real["role"] == "admin"
