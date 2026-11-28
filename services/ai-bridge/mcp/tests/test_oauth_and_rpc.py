"""OAuth PKCE + streamable HTTP MCP JSON-RPC tests."""

from __future__ import annotations

import base64
import hashlib
import re

import pytest
from fastapi.testclient import TestClient

from mcp.auth import Principal, TokenRegistry
from mcp.orchestrator_stubs import MockOrchestrator
from mcp.roles import Role
from mcp.server import configure
from mcp.tools import ToolDispatcher
from mcp.oauth_as import verify_pkce


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def test_pkce_s256() -> None:
    verifier = "test-verifier-abcdefghijklmnopqrstuvwxyz012345"
    challenge = _b64url(hashlib.sha256(verifier.encode("ascii")).digest())
    assert verify_pkce("S256", challenge, verifier)
    assert not verify_pkce("S256", challenge, "wrong")


@pytest.fixture()
def client(monkeypatch: pytest.MonkeyPatch) -> TestClient:
    monkeypatch.setenv("AIBRIDGE_OWNER_APPROVE_TOKEN", "owner-secret")
    monkeypatch.setenv("AIBRIDGE_AUTH_SERVER", "http://testserver")
    monkeypatch.setenv("AIBRIDGE_MCP_RESOURCE", "http://testserver/mcp")
    monkeypatch.setenv("AI_BRIDGE_MCP_USE_BRIDGE", "0")
    reg = TokenRegistry()
    reg.register("tok_read", Principal("reader", Role.READ))
    disp = ToolDispatcher(reg, MockOrchestrator())
    configure(reg, disp)
    from mcp import server as srv

    return TestClient(srv.app)


def test_oauth_metadata(client: TestClient) -> None:
    r = client.get("/.well-known/oauth-authorization-server")
    assert r.status_code == 200
    body = r.json()
    assert "S256" in body["code_challenge_methods_supported"]
    assert "none" in body["token_endpoint_auth_methods_supported"]
    assert body["client_id_metadata_document_supported"] is True


def test_protected_resource_metadata(client: TestClient) -> None:
    r = client.get("/.well-known/oauth-protected-resource")
    assert r.status_code == 200
    assert r.json()["resource"].endswith("/mcp")


def test_oauth_code_flow_and_tool_call(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    verifier = "abcdefghijklmnopqrstuvwxyz0123456789abcdef"
    challenge = _b64url(hashlib.sha256(verifier.encode("ascii")).digest())
    auth = client.get(
        "/oauth/authorize",
        params={
            "response_type": "code",
            "client_id": "chatgpt-test",
            "redirect_uri": "http://127.0.0.1/cb",
            "scope": "scootercheck:admin",
            "state": "xyz",
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "resource": "http://testserver/mcp",
            "owner_token": "owner-secret",
        },
        follow_redirects=False,
    )
    assert auth.status_code == 302
    loc = auth.headers["location"]
    m = re.search(r"[?&]code=([^&]+)", loc)
    assert m
    code = m.group(1)
    tok = client.post(
        "/oauth/token",
        data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": "http://127.0.0.1/cb",
            "client_id": "chatgpt-test",
            "code_verifier": verifier,
            "resource": "http://testserver/mcp",
        },
    )
    assert tok.status_code == 200
    access = tok.json()["access_token"]
    assert access.startswith("mcp_")

    init = client.post(
        "/mcp",
        json={"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
    )
    assert init.status_code == 200
    assert init.json()["result"]["serverInfo"]["name"] == "scootercheck-ai-bridge"

    listed = client.post(
        "/mcp",
        json={"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    )
    assert listed.status_code == 200
    names = {t["name"] for t in listed.json()["result"]["tools"]}
    assert "scootercheck_status" in names
    assert "scootercheck_start_task" in names

    call = client.post(
        "/mcp",
        headers={"Authorization": f"Bearer {access}"},
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "scootercheck_status", "arguments": {}},
        },
    )
    assert call.status_code == 200
    result = call.json()["result"]
    assert result["isError"] is False
    assert "chatgpt_connection_verified" in result["structuredContent"]["result"]


def test_tools_call_requires_auth(client: TestClient) -> None:
    call = client.post(
        "/mcp",
        json={
            "jsonrpc": "2.0",
            "id": 9,
            "method": "tools/call",
            "params": {"name": "scootercheck_status", "arguments": {}},
        },
    )
    assert call.status_code == 401
