"""Job ownership / authorization for firmware-analysis API (Phase 2.1 / 2.2B).

Rules:
- JWT jobs are owned by `user:<sub>` (stable).
- Shared API tokens alone are NOT a unique owner; require X-ScooterCheck-Client-Id.
- Admins: JWT role=admin, or API token when admin grant is enabled.
- Client-Id is an ownership binder only — never proof of identity.
- Legacy jobs without ownerPrincipal: JWT may access if createdByUserId/email matches;
  otherwise deny (no open access via job id alone).
- Unauthorized → 404 (no job metadata leak).

Migration (API_TOKEN_GRANTS_ADMIN):
- Phase 2.2H default is "0" (shared API_TOKEN is NOT admin).
- Ops that still need shared-token admin must set API_TOKEN_GRANTS_ADMIN=1 explicitly
  OR use ADMIN_API_TOKEN / JWT role=admin.
- Staging and new deploys should keep API_TOKEN_GRANTS_ADMIN=0.
"""
from __future__ import annotations

import os
import re
from typing import Any

from fastapi import Header, HTTPException

_CLIENT_ID_RE = re.compile(r"^[A-Za-z0-9._:@-]{1,128}$")


def _env_truthy(name: str, default: str = "0") -> bool:
    return os.environ.get(name, default).strip().lower() in {"1", "true", "yes", "on"}


def api_token_grants_admin() -> bool:
    """Whether the shared API_TOKEN authenticates as admin (secure default: no)."""
    return _env_truthy("API_TOKEN_GRANTS_ADMIN", "0")


def is_admin(auth: dict[str, Any]) -> bool:
    if auth.get("role") == "admin":
        return True
    if auth.get("auth") == "api_token":
        if auth.get("adminToken"):
            return True
        return api_token_grants_admin()
    return False


def resolve_owner_principal(auth: dict[str, Any]) -> str | None:
    """Return stable owner principal for *new* jobs, or None if not assignable."""
    kind = auth.get("auth")
    if kind == "jwt":
        uid = auth.get("userId")
        if uid:
            return f"user:{uid}"
        return None
    if kind == "api_token":
        client = str(auth.get("clientId") or "").strip()
        if client and _CLIENT_ID_RE.match(client):
            return f"apitoken-client:{client}"
        # Shared token without client id → no unique owner (admin-only jobs).
        return None
    if kind == "open":
        return "dev:open"
    return None


def enrich_auth_with_client_id(
    auth: dict[str, Any],
    x_scootercheck_client_id: str | None,
) -> dict[str, Any]:
    out = dict(auth)
    if x_scootercheck_client_id and str(x_scootercheck_client_id).strip():
        cid = str(x_scootercheck_client_id).strip()
        if not _CLIENT_ID_RE.match(cid):
            raise HTTPException(status_code=400, detail="invalid client id")
        out["clientId"] = cid
    return out


def ownership_fields_for_new_job(auth: dict[str, Any]) -> dict[str, Any]:
    principal = resolve_owner_principal(auth)
    fields: dict[str, Any] = {
        "ownerPrincipal": principal,
        "ownerAuthKind": auth.get("auth"),
        "createdBy": auth.get("email") or auth.get("userId") or auth.get("clientId") or auth.get("auth"),
        "createdByUserId": auth.get("userId"),
        "createdByClientId": auth.get("clientId"),
    }
    if principal is None and auth.get("auth") == "api_token":
        # Document that this job is only reachable by admin until claimed/migrated.
        fields["ownerLegacyNote"] = "apitoken-without-client-id; admin-only access"
    return fields


def can_access_job(job: dict[str, Any], auth: dict[str, Any]) -> bool:
    if is_admin(auth):
        return True

    principal = resolve_owner_principal(auth)
    job_owner = job.get("ownerPrincipal")

    if job_owner:
        return bool(principal) and principal == job_owner

    # --- Legacy jobs (no ownerPrincipal) ---
    kind = auth.get("auth")
    if kind == "open":
        return True
    if kind == "jwt":
        uid = auth.get("userId")
        email = str(auth.get("email") or "").strip().lower()
        if uid and job.get("createdByUserId") and str(job.get("createdByUserId")) == str(uid):
            return True
        created_by = str(job.get("createdBy") or "").strip().lower()
        if email and created_by and email == created_by:
            return True
        return False
    if kind == "api_token":
        # Without stored ownerPrincipal, shared token must not open arbitrary legacy jobs.
        # Matching client id on legacy jobs that stored createdByClientId is allowed.
        client = str(auth.get("clientId") or "").strip()
        legacy_client = str(job.get("createdByClientId") or "").strip()
        if client and legacy_client and client == legacy_client:
            return True
        return False
    return False


def require_job_access(job: dict[str, Any] | None, auth: dict[str, Any]) -> dict[str, Any]:
    """Load-guard: missing or forbidden jobs both yield opaque 404."""
    if not job or not can_access_job(job, auth):
        raise HTTPException(status_code=404, detail="job not found")
    return job


def client_id_header(
    x_scootercheck_client_id: str | None = Header(default=None, alias="X-ScooterCheck-Client-Id"),
) -> str | None:
    return x_scootercheck_client_id
