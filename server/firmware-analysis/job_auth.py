"""Job ownership / authorization for firmware-analysis API (Phase 2.1 / 2.2B / 2.2H.1).

Rules:
- JWT jobs are owned by `user:<sub>` (stable, preferred identity).
- Shared API_TOKEN alone is NOT a unique owner.
- Phase 2.2H.1: X-ScooterCheck-Client-Id is metadata only by default and MUST NOT
  grant job ownership for shared API_TOKEN (spoofable). Set
  TRUST_API_TOKEN_CLIENT_ID=1 only for temporary legacy compat.
- Admins: JWT role=admin, or ADMIN_API_TOKEN.
  Shared API_TOKEN as admin (API_TOKEN_GRANTS_ADMIN=1) is legacy opt-in only and
  CRITICAL-warned on /health — do not enable in prod/staging defaults or tests.
- Legacy jobs without ownerPrincipal: JWT may access if createdByUserId/email matches;
  otherwise deny (no open access via job id alone).
- Unauthorized → 404 (no job metadata leak).

Migration:
- App should authenticate with Bearer JWT for user-owned firmware jobs.
- Shared API_TOKEN may still authenticate requests but cannot claim client-id ownership
  unless TRUST_API_TOKEN_CLIENT_ID=1.
- API_TOKEN_GRANTS_ADMIN default remains "0" (secure). Prefer ADMIN_API_TOKEN.
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
    """Whether the shared API_TOKEN authenticates as admin.

    Secure default is false. Enabling collapses user vs admin separation and is
    surfaced as CRITICAL on /health (authMode=shared_token_admin).
    """
    return _env_truthy("API_TOKEN_GRANTS_ADMIN", "0")


def trust_api_token_client_id() -> bool:
    """Legacy opt-in: bind jobs to X-ScooterCheck-Client-Id under shared API_TOKEN.

    Default false — client ids are spoofable by anyone who knows the shared token.
    """
    return _env_truthy("TRUST_API_TOKEN_CLIENT_ID", "0")


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
        # Phase 2.2H.1: do not treat client-id as cryptographic identity.
        if not trust_api_token_client_id():
            return None
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
        # Matching client id on legacy jobs is only allowed under explicit legacy trust.
        if not trust_api_token_client_id():
            return False
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
