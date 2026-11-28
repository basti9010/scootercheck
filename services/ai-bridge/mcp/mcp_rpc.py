"""Minimal Streamable HTTP MCP JSON-RPC surface (initialize / tools/list / tools/call).

Compatible with ChatGPT custom MCP (streaming HTTP). Auth: Bearer access token
except when AIBRIDGE_MCP_PUBLIC_INIT=1 allows unauthenticated initialize+list
(mixed auth mode per OpenAI docs). Write tools always require OAuth bearer.
"""

from __future__ import annotations

import os
from typing import Any

from fastapi import APIRouter, Header, Request
from fastapi.responses import JSONResponse

from .auth import AuthError, TokenRegistry
from .tools import ToolDispatcher, ToolSpec, list_tools_for_mcp, SPECS_BY_NAME

router = APIRouter()

_registry: TokenRegistry | None = None
_dispatcher: ToolDispatcher | None = None

SERVER_INFO = {
    "name": "scootercheck-ai-bridge",
    "version": "3.0.0",
}

INSTRUCTIONS = (
    "ScooterCheck AI Bridge MCP. Use scootercheck_status for overview. "
    "Create tasks with scootercheck_create_task, wait for approval when required, "
    "then scootercheck_start_task (write — confirm). Never ask for CURSOR_API_KEY. "
    "Production deploy is never available via these tools."
)


def bind_rpc(registry: TokenRegistry, dispatcher: ToolDispatcher) -> None:
    global _registry, _dispatcher
    _registry = registry
    _dispatcher = dispatcher


def _public_init_allowed() -> bool:
    return os.environ.get("AIBRIDGE_MCP_PUBLIC_INIT", "1").lower() in ("1", "true", "yes")


def _auth_header(authorization: str | None) -> str | None:
    return authorization


def _tool_list_mcp() -> list[dict[str, Any]]:
    tools = []
    for item in list_tools_for_mcp():
        tools.append(
            {
                "name": item["name"],
                "description": item["description"],
                "inputSchema": item["inputSchema"],
                "annotations": item.get("annotations") or {},
            }
        )
    return tools


def handle_jsonrpc(body: dict[str, Any], authorization: str | None) -> dict[str, Any]:
    assert _registry is not None and _dispatcher is not None
    req_id = body.get("id")
    method = body.get("method")
    params = body.get("params") or {}

    def ok(result: Any) -> dict[str, Any]:
        return {"jsonrpc": "2.0", "id": req_id, "result": result}

    def err(code: int, message: str) -> dict[str, Any]:
        return {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}

    if method == "initialize":
        return ok(
            {
                "protocolVersion": params.get("protocolVersion") or "2024-11-05",
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": SERVER_INFO,
                "instructions": INSTRUCTIONS,
            }
        )
    if method == "notifications/initialized":
        return ok({})
    if method == "ping":
        return ok({})
    if method == "tools/list":
        if not _public_init_allowed():
            try:
                _registry.resolve(authorization)
            except AuthError as exc:
                return err(-32001, exc.detail)
        return ok({"tools": _tool_list_mcp()})
    if method == "tools/call":
        name = str(params.get("name") or "")
        arguments = params.get("arguments") or {}
        spec: ToolSpec | None = SPECS_BY_NAME.get(name)
        # Mixed auth: still require bearer for every tools/call (safer default).
        try:
            result = _dispatcher.invoke(name, arguments if isinstance(arguments, dict) else {}, authorization)
        except AuthError as exc:
            return err(-32001 if exc.status_code == 401 else -32003, exc.detail)
        # MCP CallToolResult shape
        text = __import__("json").dumps(result, ensure_ascii=False)
        is_error = not result.get("ok", True)
        return ok(
            {
                "content": [{"type": "text", "text": text}],
                "structuredContent": result,
                "isError": is_error,
            }
        )
    return err(-32601, f"method not found: {method}")


@router.post("/mcp")
async def mcp_streamable_http(
    request: Request,
    authorization: str | None = Header(default=None),
) -> JSONResponse:
    try:
        body = await request.json()
    except Exception:  # noqa: BLE001
        return JSONResponse(
            {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}},
            status_code=400,
        )
    if isinstance(body, list):
        # Batch — process sequentially
        out = [handle_jsonrpc(item, authorization) for item in body if isinstance(item, dict)]
        return JSONResponse(out)
    if not isinstance(body, dict):
        return JSONResponse(
            {"jsonrpc": "2.0", "id": None, "error": {"code": -32600, "message": "invalid request"}},
            status_code=400,
        )
    result = handle_jsonrpc(body, authorization)
    status = 200
    if "error" in result and result["error"].get("code") in (-32001,):
        status = 401
    resp = JSONResponse(result, status_code=status)
    if status == 401:
        resource = os.environ.get("AIBRIDGE_MCP_RESOURCE", "https://ai-bridge.example.invalid/mcp")
        meta = resource.rstrip("/")
        if meta.endswith("/mcp"):
            meta = meta[: -len("/mcp")]
        resp.headers["WWW-Authenticate"] = (
            f'Bearer resource_metadata="{meta}/.well-known/oauth-protected-resource", '
            'scope="scootercheck:read"'
        )
    return resp


# import os used above in 401 path
import os  # noqa: E402
