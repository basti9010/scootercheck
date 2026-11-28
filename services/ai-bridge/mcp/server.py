"""ScooterCheck AI Bridge MCP HTTP server (ChatGPT custom MCP ready).

Exposes:
  - Streamable HTTP JSON-RPC at POST /mcp
  - OAuth 2.1 AS (PKCE S256) + protected-resource metadata
  - Legacy JSON helpers at /mcp/tools for tests

CHATGPT_CONNECTION_VERIFIED stays false until a real ChatGPT client completes OAuth.
"""

from __future__ import annotations

import os
from typing import Any

from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from .auth import AuthError, TokenRegistry
from .mcp_rpc import bind_rpc, router as mcp_router
from .oauth_as import bind_oauth, router as oauth_router
from .tools import ToolDispatcher, list_tools_for_mcp

RESOURCE_URL = os.environ.get("AIBRIDGE_MCP_RESOURCE", "https://ai-bridge.example.invalid/mcp")
AUTH_SERVER = os.environ.get("AIBRIDGE_AUTH_SERVER", "https://auth.example.invalid")

app = FastAPI(
    title="ScooterCheck AI Bridge MCP",
    version="3.0.0",
    description=(
        "ChatGPT-compatible MCP resource + OAuth AS for ScooterCheck development automation. "
        "CHATGPT_CONNECTION_VERIFIED must not be assumed from process start alone."
    ),
)

_registry = TokenRegistry.from_env()
_dispatcher = ToolDispatcher(_registry)
bind_oauth(_registry)
bind_rpc(_registry, _dispatcher)

app.include_router(oauth_router)
app.include_router(mcp_router)


class ToolCallBody(BaseModel):
    name: str = Field(..., description="Tool name")
    arguments: dict[str, Any] = Field(default_factory=dict)


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "service": "ai-bridge-mcp",
        "version": "3.0.0",
        "chatgpt_connection_verified": False,
        "anonymous_write": False,
        "transport": "streamable-http",
        "mcp_path": "/mcp",
    }


@app.get("/.well-known/oauth-protected-resource")
def oauth_protected_resource() -> dict[str, Any]:
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
        "resource_documentation": (
            "https://github.com/basti9010/scootercheck/blob/cursor/chatgpt-native-mcp-b100/"
            "research/chatgpt-native/CHATGPT_SETUP.md"
        ),
    }


@app.get("/mcp/tools")
def mcp_list_tools(authorization: str | None = Header(default=None)) -> JSONResponse:
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
    try:
        result = _dispatcher.invoke(tool_name, request_body or {}, authorization)
    except AuthError as exc:
        return _auth_error(exc)
    return JSONResponse(result)


@app.middleware("http")
async def security_headers(request: Request, call_next):  # type: ignore[no-untyped-def]
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    if response.status_code == 401 and "WWW-Authenticate" not in response.headers:
        meta_base = RESOURCE_URL
        if meta_base.endswith("/mcp"):
            meta_base = meta_base[: -len("/mcp")]
        response.headers["WWW-Authenticate"] = (
            f'Bearer resource_metadata="{meta_base}/.well-known/oauth-protected-resource", '
            'scope="scootercheck:read"'
        )
    return response


def _auth_error(exc: AuthError) -> JSONResponse:
    return JSONResponse({"ok": False, "error": exc.detail}, status_code=exc.status_code)


def configure(registry: TokenRegistry, dispatcher: ToolDispatcher | None = None) -> FastAPI:
    global _registry, _dispatcher
    _registry = registry
    _dispatcher = dispatcher or ToolDispatcher(registry)
    bind_oauth(_registry)
    bind_rpc(_registry, _dispatcher)
    return app
