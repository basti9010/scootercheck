"""Minimal OAuth 2.1 authorization server for ScooterCheck MCP (single-owner).

Supports authorization-code + PKCE S256 and public clients (token auth method
``none``), matching ChatGPT custom MCP expectations when CIMD/predefined clients
use PKCE. Not a full IdP product — suitable for owner-operated bridge.

Secrets never appear in tool results. Access tokens are opaque and mapped to
roles via TokenRegistry.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlencode

from fastapi import APIRouter, Form, HTTPException, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse

from .auth import Principal, TokenRegistry
from .roles import Role, parse_role

router = APIRouter()

# In-memory stores (process-local). Persist across restarts via optional JSON file.
_codes: dict[str, dict[str, Any]] = {}
_refresh: dict[str, dict[str, Any]] = {}


def _issuer() -> str:
    return os.environ.get("AIBRIDGE_AUTH_SERVER", "").rstrip("/") or "http://127.0.0.1:8787"


def _resource() -> str:
    return os.environ.get("AIBRIDGE_MCP_RESOURCE", "").rstrip("/") or f"{_issuer()}/mcp"


def _owner_gate_ok(request: Request) -> bool:
    """Owner proves identity with AIBRIDGE_OWNER_APPROVE_TOKEN (query/header/form)."""
    expected = os.environ.get("AIBRIDGE_OWNER_APPROVE_TOKEN", "").strip()
    if not expected:
        return False
    q = request.query_params.get("owner_token") or ""
    h = request.headers.get("X-Owner-Token") or ""
    return hmac.compare_digest(q, expected) or hmac.compare_digest(h, expected)


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def verify_pkce(method: str, challenge: str, verifier: str) -> bool:
    if method != "S256":
        return False
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return hmac.compare_digest(_b64url(digest), challenge)


def issue_access_token(registry: TokenRegistry, *, subject: str, role: Role) -> str:
    token = "mcp_" + secrets.token_urlsafe(32)
    registry.register(token, Principal(subject=subject, role=role))
    return token


@dataclass
class OAuthDeps:
    registry: TokenRegistry


_deps: OAuthDeps | None = None


def bind_oauth(registry: TokenRegistry) -> None:
    global _deps
    _deps = OAuthDeps(registry=registry)


def _require_deps() -> OAuthDeps:
    if _deps is None:
        raise RuntimeError("OAuth not bound")
    return _deps


@router.get("/.well-known/oauth-authorization-server")
def oauth_authorization_server_metadata() -> dict[str, Any]:
    iss = _issuer()
    return {
        "issuer": iss,
        "authorization_endpoint": f"{iss}/oauth/authorize",
        "token_endpoint": f"{iss}/oauth/token",
        "registration_endpoint": f"{iss}/oauth/register",
        "response_types_supported": ["code"],
        "grant_types_supported": ["authorization_code", "refresh_token"],
        "code_challenge_methods_supported": ["S256"],
        "token_endpoint_auth_methods_supported": ["none"],
        "client_id_metadata_document_supported": True,
        "scopes_supported": [
            "scootercheck:read",
            "scootercheck:task_write",
            "scootercheck:approval",
            "scootercheck:admin",
        ],
        "authorization_response_iss_parameter_supported": True,
    }


@router.get("/.well-known/openid-configuration")
def openid_configuration() -> dict[str, Any]:
    # Alias for clients that probe OIDC discovery first.
    return oauth_authorization_server_metadata()


@router.post("/oauth/register")
async def dynamic_client_registration(request: Request) -> JSONResponse:
    """Minimal DCR — accepts any redirect_uris; issues a public client_id."""
    try:
        body = await request.json()
    except Exception:  # noqa: BLE001
        body = {}
    client_id = "dcr_" + secrets.token_urlsafe(16)
    redirect_uris = body.get("redirect_uris") or [
        "https://chatgpt.com/connector_platform_oauth_redirect"
    ]
    return JSONResponse(
        {
            "client_id": client_id,
            "client_id_issued_at": int(time.time()),
            "token_endpoint_auth_method": "none",
            "redirect_uris": redirect_uris,
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "code_challenge_methods": ["S256"],
        },
        status_code=201,
    )


@router.get("/oauth/authorize", response_model=None)
def authorize(
    request: Request,
    response_type: str = Query(...),
    client_id: str = Query(...),
    redirect_uri: str = Query(...),
    scope: str = Query(default="scootercheck:admin"),
    state: str = Query(default=""),
    code_challenge: str = Query(...),
    code_challenge_method: str = Query(default="S256"),
    resource: str = Query(default=""),
):
    if response_type != "code":
        raise HTTPException(400, "unsupported response_type")
    if code_challenge_method != "S256":
        raise HTTPException(400, "code_challenge_method must be S256")
    # Only allow documented ChatGPT redirect or localhost test redirects.
    allowed_prefixes = (
        "https://chatgpt.com/connector_platform_oauth_redirect",
        "http://127.0.0.1",
        "http://localhost",
    )
    if not any(redirect_uri.startswith(p) for p in allowed_prefixes):
        raise HTTPException(400, "redirect_uri not allowed")

    if _owner_gate_ok(request):
        return _issue_code_redirect(
            client_id=client_id,
            redirect_uri=redirect_uri,
            scope=scope,
            state=state,
            code_challenge=code_challenge,
            resource=resource or _resource(),
        )

    # Interactive consent page — owner must paste approve token.
    html = f"""<!doctype html>
<html lang="de"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>ScooterCheck MCP Freigabe</title></head>
<body style="font-family:system-ui;background:#12161C;color:#E8EEF2;padding:1.5rem">
<h1>ScooterCheck AI Bridge</h1>
<p>OAuth-Freigabe für ChatGPT / MCP. Keine Cursor-API-Keys hier.</p>
<p>Client: <code>{client_id}</code><br/>Scope: <code>{scope}</code></p>
<form method="get">
  <input type="hidden" name="response_type" value="code"/>
  <input type="hidden" name="client_id" value="{client_id}"/>
  <input type="hidden" name="redirect_uri" value="{redirect_uri}"/>
  <input type="hidden" name="scope" value="{scope}"/>
  <input type="hidden" name="state" value="{state}"/>
  <input type="hidden" name="code_challenge" value="{code_challenge}"/>
  <input type="hidden" name="code_challenge_method" value="S256"/>
  <input type="hidden" name="resource" value="{resource or _resource()}"/>
  <label>Owner-Token<br/><input name="owner_token" type="password" style="width:100%;padding:0.75rem;margin:0.5rem 0"/></label>
  <button type="submit" style="padding:0.75rem 1.2rem;background:#6BDBC2;border:0;border-radius:8px">Freigeben</button>
</form>
</body></html>"""
    return HTMLResponse(html)


def _issue_code_redirect(
    *,
    client_id: str,
    redirect_uri: str,
    scope: str,
    state: str,
    code_challenge: str,
    resource: str,
) -> RedirectResponse:
    code = secrets.token_urlsafe(24)
    role = Role.ADMIN
    # Map scope string → role (most permissive requested that we allow for owner).
    if "admin" in scope:
        role = Role.ADMIN
    elif "approval" in scope:
        role = Role.APPROVAL
    elif "task_write" in scope:
        role = Role.TASK_WRITE
    else:
        role = Role.READ
    _codes[code] = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "code_challenge": code_challenge,
        "resource": resource,
        "role": role.value,
        "subject": os.environ.get("AIBRIDGE_OWNER_SUBJECT", "owner"),
        "exp": time.time() + 300,
    }
    params = {"code": code, "iss": _issuer()}
    if state:
        params["state"] = state
    sep = "&" if "?" in redirect_uri else "?"
    return RedirectResponse(f"{redirect_uri}{sep}{urlencode(params)}", status_code=302)


@router.post("/oauth/token")
async def token(
    request: Request,
    grant_type: str = Form(...),
    code: str = Form(default=""),
    redirect_uri: str = Form(default=""),
    client_id: str = Form(default=""),
    code_verifier: str = Form(default=""),
    refresh_token: str = Form(default=""),
    resource: str = Form(default=""),
) -> JSONResponse:
    deps = _require_deps()
    if grant_type == "authorization_code":
        entry = _codes.pop(code, None)
        if entry is None:
            raise HTTPException(400, "invalid_grant")
        if entry["exp"] < time.time():
            raise HTTPException(400, "invalid_grant")
        if entry["redirect_uri"] != redirect_uri:
            raise HTTPException(400, "invalid_grant")
        if not verify_pkce("S256", entry["code_challenge"], code_verifier):
            raise HTTPException(400, "invalid_grant")
        # resource echo — if provided must match
        if resource and entry.get("resource") and resource.rstrip("/") != str(entry["resource"]).rstrip("/"):
            raise HTTPException(400, "invalid_target")
        role = parse_role(entry["role"])
        access = issue_access_token(deps.registry, subject=entry["subject"], role=role)
        rtok = "rt_" + secrets.token_urlsafe(24)
        _refresh[rtok] = {
            "subject": entry["subject"],
            "role": role.value,
            "exp": time.time() + 86400 * 30,
        }
        return JSONResponse(
            {
                "access_token": access,
                "token_type": "bearer",
                "expires_in": 3600,
                "refresh_token": rtok,
                "scope": f"scootercheck:{role.value.lower()}",
            }
        )
    if grant_type == "refresh_token":
        entry = _refresh.get(refresh_token)
        if entry is None or entry["exp"] < time.time():
            raise HTTPException(400, "invalid_grant")
        role = parse_role(entry["role"])
        access = issue_access_token(deps.registry, subject=entry["subject"], role=role)
        return JSONResponse(
            {
                "access_token": access,
                "token_type": "bearer",
                "expires_in": 3600,
                "scope": f"scootercheck:{role.value.lower()}",
            }
        )
    raise HTTPException(400, "unsupported_grant_type")
