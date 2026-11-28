"""HTTP API auth gates for /api/v1 (no anonymous writes)."""

from __future__ import annotations

import json
import os

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv(
        "AIBRIDGE_TOKENS",
        json.dumps(
            {
                "tok_read": {"sub": "reader", "role": "READ"},
                "tok_write": {"sub": "writer", "role": "TASK_WRITE"},
                "tok_admin": {"sub": "admin", "role": "ADMIN"},
            }
        ),
    )
    monkeypatch.setenv("AI_BRIDGE_DB_PATH", str(tmp_path / "api.sqlite3"))
    monkeypatch.setenv("AI_BRIDGE_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("AI_BRIDGE_USE_SQLITE", "1")
    monkeypatch.delenv("CURSOR_API_KEY", raising=False)
    # Fresh import of app with env applied
    import importlib
    import ai_bridge.app as appmod

    importlib.reload(appmod)
    return TestClient(appmod.app)


def test_status_requires_auth(client: TestClient) -> None:
    r = client.get("/api/v1/status")
    assert r.status_code == 401


def test_status_with_read(client: TestClient) -> None:
    r = client.get("/api/v1/status", headers={"Authorization": "Bearer tok_read"})
    assert r.status_code == 200
    body = r.json()
    assert body["chatgpt_connection_verified"] is False
    assert body["cursor"]["CURSOR_API_LIVE_VERIFIED"] is False
    assert body["cursor"]["status"] == "BLOCKED_MISSING_CREDENTIAL"


def test_create_requires_write(client: TestClient) -> None:
    r = client.post(
        "/api/v1/tasks",
        headers={"Authorization": "Bearer tok_read"},
        json={
            "title": "x",
            "description": "y",
            "idempotency_key": "k-read",
        },
    )
    assert r.status_code == 403


def test_create_and_list_owned(client: TestClient) -> None:
    created = client.post(
        "/api/v1/tasks",
        headers={"Authorization": "Bearer tok_write"},
        json={
            "title": "Improve Investigation Hub",
            "description": "Fix back animations",
            "idempotency_key": "k-write-1",
            "approval_required": True,
        },
    )
    assert created.status_code == 200
    task_id = created.json()["task"]["task_id"]
    listed = client.get("/api/v1/tasks", headers={"Authorization": "Bearer tok_write"})
    assert listed.status_code == 200
    assert any(t["task_id"] == task_id for t in listed.json()["tasks"])


def test_health_public(client: TestClient) -> None:
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["anonymous_write"] is False


def test_foreign_task_denied(client: TestClient, monkeypatch) -> None:
    created = client.post(
        "/api/v1/tasks",
        headers={"Authorization": "Bearer tok_write"},
        json={
            "title": "owner task",
            "description": "secret work",
            "idempotency_key": "k-foreign-1",
        },
    )
    assert created.status_code == 200
    task_id = created.json()["task"]["task_id"]
    import ai_bridge.app as appmod
    from ai_bridge.session_auth import Principal, SessionRegistry
    from mcp.roles import Role

    # Inject another principal into the live registry without reloading the store.
    appmod._registry = SessionRegistry(
        {
            "tok_write": Principal("writer", Role.TASK_WRITE),
            "tok_other": Principal("other", Role.TASK_WRITE),
            "tok_read": Principal("reader", Role.READ),
            "tok_admin": Principal("admin", Role.ADMIN),
        }
    )
    r = client.get(f"/api/v1/tasks/{task_id}", headers={"Authorization": "Bearer tok_other"})
    assert r.status_code == 403
    admin = client.get(f"/api/v1/tasks/{task_id}", headers={"Authorization": "Bearer tok_admin"})
    assert admin.status_code == 200
