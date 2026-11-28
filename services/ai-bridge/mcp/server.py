"""HTTP tool surface integrable with ChatGPT MCP (streaming HTTP / SSE later).

Phase A: FastAPI JSON dispatch + OAuth protected-resource metadata stub.
Full OAuth IdP / CIMD / DCR is out of scope; bearer role tokens exercise authz.
"""

from __future__ import annotations

import os
from typing import Any

from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from .auth import AuthError, TokenRegistry
from .tools import ToolDispatcher, list_tools_for_mcp

RESOURCE_URL = os.environ.get("AIBRIDGE_MCP_RESOURCE", "https://ai-bridge.example.invalid/mcp")
AUTH_SERVER = os.environ.get("AIBRIDGE_AUTH_SERVER", "https://auth.example.invalid")

app = FastAPI(
    title="ScooterCheck ai-bridge MCP",
    version="0.1.0",
    description=(
        "Development Automation MCP scaffold. "
        "CHATGPT_CONNECTION_VERIFIED must not be assumed from this process alone."
    ),
)

_registry = TokenRegistry.from_env()
_dispatcher = ToolDispatcher(_registry)


class ToolCallBody(BaseModel):
    name: str = Field(..., description="Tool name")
    arguments: dict[str, Any] = Field(default_factory=dict)


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "service": "ai-bridge-mcp",
        "chatgpt_connection_verified": False,
        "anonymous_write": False,
    }


@app.get("/.well-known/oauth-protected-resource")
def oauth_protected_resource() -> dict[str, Any]:
    """MCP auth spec protected-resource metadata (RFC 9728 style).

    ChatGPT discovers authorization servers from this document. PKCE S256 and
    redirect https://chatgpt.com/connector_platform_oauth_redirect are documented
    for the IdP — not implemented here in Phase A.
    """
    return {
        "resource": RESOURCE_URL,
        "authorization_servers": [AUTH_SERVER],
        "scopes_supported": [
            "scootercheck:read",
            "scootercheck:task_write",
            "scootercheck:approval",
            "scootercheck:admin",
        ],
        "bearer_methods_supported": ["header"],
        "resource_documentation": "https://github.com/basti9010/scootercheck/tree/cursor/ai-bridge-v2-b100/services/ai-bridge/mcp",
        "notes": (
            "OAuth 2.1 + PKCE S256 required before ChatGPT Custom Connector. "
            "Redirect URI: https://chatgpt.com/connector_platform_oauth_redirect. "
            "CHATGPT_CONNECTION_VERIFIED stays false until a real ChatGPT client completes OAuth."
        ),
    }


@app.get("/mcp/tools")
def mcp_list_tools(authorization: str | None = Header(default=None)) -> JSONResponse:
    """List tools. Requires any valid token (no anonymous listing in this policy)."""
    try:
        _registry.resolve(authorization)
    except AuthError as exc:
        return _auth_error(exc)
    return JSONResponse({"tools": list_tools_for_mcp()})


@app.post("/mcp/tools/call")
def mcp_call_tool(
    body: ToolCallBody,
    authorization: str | None = Header(default=None),
) -> JSONResponse:
    try:
        result = _dispatcher.invoke(body.name, body.arguments, authorization)
    except AuthError as exc:
        return _auth_error(exc)
    return JSONResponse(result)


@app.post("/tools/{tool_name}")
def rest_call_tool(
    tool_name: str,
    request_body: dict[str, Any] | None = None,
    authorization: str | None = Header(default=None),
) -> JSONResponse:
    """Dev Center friendly alias — same authz as MCP call."""
    try:
        result = _dispatcher.invoke(tool_name, request_body or {}, authorization)
    except AuthError as exc:
        return _auth_error(exc)
    return JSONResponse(result)


@app.middleware("http")
async def add_www_authenticate(request: Request, call_next):  # type: ignore[no-untyped-def]
    response = await call_next(request)
    if response.status_code == 401:
        response.headers["WWW-Authenticate"] = (
            'Bearer resource_metadata='
            '"https://ai-bridge.example.invalid/.well-known/oauth-protected-resource", '
            'scope="scootercheck:read"'
        )
    return response


def _auth_error(exc: AuthError) -> JSONResponse:
    return JSONResponse({"ok": False, "error": exc.detail}, status_code=exc.status_code)


def configure(registry: TokenRegistry, dispatcher: ToolDispatcher | None = None) -> FastAPI:
    """Rebind module globals for tests."""
    global _registry, _dispatcher
    _registry = registry
    _dispatcher = dispatcher or ToolDispatcher(registry)
    return app
