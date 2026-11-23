"""Assemble Cycle 11 diagnostics status from safe probes.

Rules:
- Existence / configured checks only — no secret values, no env dumps, no shell API.
- Never claim VERIFIED for TEA/Ghidra from flags alone (Agents B/C own verification).
- Reuses /health-style helpers where possible without importing app.py at module load
  (avoids circular imports when PM wires routes).
"""
from __future__ import annotations

import os
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from diagnostics_models import (
    AuthGateStatus,
    ComponentStatus,
    DiagnosticGrade,
    DiagnosticsStatusResponse,
)
from job_auth import api_token_grants_admin, trust_api_token_client_id


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _env_set(name: str) -> bool:
    return bool(os.environ.get(name, "").strip())


def _path_exists_or_which(raw: str) -> bool:
    raw = (raw or "").strip()
    if not raw:
        return False
    p = Path(raw)
    if p.exists():
        return True
    # Allow "cmd" or "cmd with spaces as path" — first token for which().
    return bool(shutil.which(raw.split()[0]))


def auth_mode_from_env() -> str:
    """Mirror app._auth_mode() without importing app (no secrets)."""
    api = _env_set("API_TOKEN")
    admin = _env_set("ADMIN_API_TOKEN")
    jwt = _env_set("JWT_SECRET")
    if not api and not admin and not jwt:
        return "open"
    if api_token_grants_admin():
        return "shared_token_admin"
    return "separated"


def auth_security_warnings() -> list[str]:
    """Mirror app._auth_security_warnings() — CRITICAL/INSECURE/ADVISORY text only."""
    warnings: list[str] = []
    api = _env_set("API_TOKEN")
    admin = _env_set("ADMIN_API_TOKEN")
    jwt = _env_set("JWT_SECRET")
    if not api and not admin and not jwt:
        warnings.append(
            "CRITICAL: API_TOKEN, ADMIN_API_TOKEN, and JWT_SECRET are all unset — "
            "auth=open (unauthenticated access). Configure secrets before any public bind."
        )
    if api_token_grants_admin():
        warnings.append(
            "CRITICAL: API_TOKEN_GRANTS_ADMIN=1 — shared API_TOKEN grants admin "
            "(user vs admin separation broken). "
            "Set API_TOKEN_GRANTS_ADMIN=0 and use ADMIN_API_TOKEN / JWT role=admin."
        )
    if trust_api_token_client_id():
        warnings.append(
            "INSECURE: TRUST_API_TOKEN_CLIENT_ID=1 — Client-Id can own/access jobs under "
            "shared API_TOKEN (spoofable). Set TRUST_API_TOKEN_CLIENT_ID=0; prefer Bearer JWT."
        )
    if api and not admin and api_token_grants_admin():
        warnings.append(
            "CRITICAL: shared API_TOKEN is the only admin credential (no ADMIN_API_TOKEN). "
            "Set ADMIN_API_TOKEN and API_TOKEN_GRANTS_ADMIN=0 before relying on authSecurityOk."
        )
    if api and not admin and not api_token_grants_admin():
        warnings.append(
            "ADVISORY: ADMIN_API_TOKEN unset — admin endpoints require JWT role=admin only."
        )
    if not jwt:
        warnings.append(
            "ADVISORY: JWT_SECRET unset — user-owned firmware jobs via Bearer JWT are unavailable."
        )
    return warnings


def auth_security_ok(warnings: list[str] | None = None) -> bool:
    warnings = auth_security_warnings() if warnings is None else warnings
    return not any(w.startswith(("CRITICAL:", "INSECURE:")) for w in warnings)


def diagnostics_auth_allowed() -> tuple[bool, str]:
    """Whether the diagnostics surface may run under current server posture.

    Refuse when auth=open or shared-token-admin CRITICAL path still grants via
    apiTokenGrantsAdmin. Diagnostics must use true admin JWT or ADMIN_API_TOKEN only
    after auth is separated.
    """
    mode = auth_mode_from_env()
    if mode == "open":
        return False, "refused: auth=open (configure JWT_SECRET / ADMIN_API_TOKEN first)"
    if mode == "shared_token_admin":
        return (
            False,
            "refused: shared-token-admin CRITICAL (API_TOKEN_GRANTS_ADMIN=1) — "
            "set API_TOKEN_GRANTS_ADMIN=0; use ADMIN_API_TOKEN or JWT role=admin only",
        )
    if not _env_set("ADMIN_API_TOKEN") and not _env_set("JWT_SECRET"):
        return False, "refused: neither ADMIN_API_TOKEN nor JWT_SECRET configured"
    return True, "separated auth posture — true admin JWT or ADMIN_API_TOKEN required"


def _probe_decrypt() -> ComponentStatus:
    """TEA / DECRYPT_CMD — existence only (Agent B owns VERIFIED)."""
    cmd = os.environ.get("DECRYPT_CMD", "").strip()
    if not cmd:
        return ComponentStatus(
            id="decrypt",
            label="NinebotTEA / DECRYPT_CMD",
            grade=DiagnosticGrade.UNKNOWN,
            detail="DECRYPT_CMD unset",
            meta={"decryptConfigured": False},
        )
    if _path_exists_or_which(cmd):
        return ComponentStatus(
            id="decrypt",
            label="NinebotTEA / DECRYPT_CMD",
            grade=DiagnosticGrade.AVAILABLE,
            detail="DECRYPT_CMD path/binary present (not VERIFIED — no decrypt probe here)",
            meta={"decryptConfigured": True, "pathPresent": True},
        )
    return ComponentStatus(
        id="decrypt",
        label="NinebotTEA / DECRYPT_CMD",
        grade=DiagnosticGrade.CONFIGURED,
        detail="DECRYPT_CMD set but path not found on this host",
        meta={"decryptConfigured": True, "pathPresent": False},
    )


def _probe_ghidra() -> ComponentStatus:
    """Ghidra headless — configured/available only (Agent C owns VERIFIED)."""
    enable = os.environ.get("ENABLE_GHIDRA", "1").strip() not in ("0", "false", "False")
    try:
        from ghidra_decompile import ghidra_configured
    except Exception as exc:  # pragma: no cover — import failure is informative
        return ComponentStatus(
            id="ghidra",
            label="Ghidra headless",
            grade=DiagnosticGrade.UNKNOWN,
            detail=f"ghidra_decompile import failed: {type(exc).__name__}",
            meta={"ghidraEnabled": enable},
        )
    configured = bool(ghidra_configured())
    if not enable:
        return ComponentStatus(
            id="ghidra",
            label="Ghidra headless",
            grade=DiagnosticGrade.CONFIGURED if configured else DiagnosticGrade.UNKNOWN,
            detail="ENABLE_GHIDRA=0 (disabled)",
            meta={"ghidraEnabled": False, "ghidraConfigured": configured},
        )
    if configured:
        return ComponentStatus(
            id="ghidra",
            label="Ghidra headless",
            grade=DiagnosticGrade.AVAILABLE,
            detail="analyzeHeadless resolvable (not VERIFIED — no headless run here)",
            meta={"ghidraEnabled": True, "ghidraConfigured": True},
        )
    home_set = _env_set("GHIDRA_HOME") or _env_set("GHIDRA_HEADLESS")
    if home_set:
        return ComponentStatus(
            id="ghidra",
            label="Ghidra headless",
            grade=DiagnosticGrade.CONFIGURED,
            detail="GHIDRA_HOME/GHIDRA_HEADLESS set but headless binary not found",
            meta={"ghidraEnabled": True, "ghidraConfigured": False},
        )
    return ComponentStatus(
        id="ghidra",
        label="Ghidra headless",
        grade=DiagnosticGrade.UNKNOWN,
        detail="Ghidra not configured",
        meta={"ghidraEnabled": True, "ghidraConfigured": False},
    )


def _probe_workers() -> ComponentStatus:
    """In-process BackgroundTasks + heavy-analysis single-flight lock (repo design)."""
    # No separate worker process — uvicorn + FastAPI BackgroundTasks.
    return ComponentStatus(
        id="workers",
        label="Analysis workers",
        grade=DiagnosticGrade.CONFIGURED,
        detail=(
            "In-process BackgroundTasks; Ghidra/angr serialized via _HEAVY_ANALYSIS_LOCK "
            "(single-flight). No external queue process."
        ),
        meta={
            "model": "fastapi_background_tasks",
            "heavyAnalysisSingleFlight": True,
            "systemdUnit": "scootercheck-fw.service",
        },
    )


def _probe_jobs_store() -> ComponentStatus:
    work = Path(os.environ.get("WORK_DIR", "/tmp/scootercheck-fw-jobs"))
    try:
        work.mkdir(parents=True, exist_ok=True)
        writable = os.access(work, os.W_OK)
    except OSError as exc:
        return ComponentStatus(
            id="jobs",
            label="Job store (WORK_DIR)",
            grade=DiagnosticGrade.FAILED,
            detail=f"WORK_DIR not usable: {type(exc).__name__}",
            meta={"workDirConfigured": _env_set("WORK_DIR")},
        )
    if writable and work.is_dir():
        grade = DiagnosticGrade.AVAILABLE if _env_set("WORK_DIR") else DiagnosticGrade.CONFIGURED
        return ComponentStatus(
            id="jobs",
            label="Job store (WORK_DIR)",
            grade=grade,
            detail="WORK_DIR exists and is writable (path not echoed)",
            meta={
                "workDirConfigured": _env_set("WORK_DIR"),
                "writable": True,
                "retentionDaysSet": _env_set("JOB_RETENTION_DAYS"),
                "maxStoredJobsSet": _env_set("MAX_STORED_JOBS"),
            },
        )
    return ComponentStatus(
        id="jobs",
        label="Job store (WORK_DIR)",
        grade=DiagnosticGrade.FAILED,
        detail="WORK_DIR not writable",
        meta={"writable": False},
    )


def _probe_auth_component() -> ComponentStatus:
    mode = auth_mode_from_env()
    warnings = auth_security_warnings()
    ok = auth_security_ok(warnings)
    allowed, detail = diagnostics_auth_allowed()
    if mode == "open" or mode == "shared_token_admin":
        grade = DiagnosticGrade.FAILED
    elif ok and allowed:
        grade = DiagnosticGrade.AVAILABLE
    elif _env_set("ADMIN_API_TOKEN") or _env_set("JWT_SECRET"):
        grade = DiagnosticGrade.CONFIGURED
    else:
        grade = DiagnosticGrade.UNKNOWN
    return ComponentStatus(
        id="auth",
        label="Auth gate",
        grade=grade,
        detail=detail,
        meta={
            "authMode": mode,
            "authSecurityOk": ok,
            "authSecurityCritical": any(w.startswith("CRITICAL:") for w in warnings),
            "apiTokenConfigured": _env_set("API_TOKEN"),
            "adminApiTokenConfigured": _env_set("ADMIN_API_TOKEN"),
            "jwtConfigured": _env_set("JWT_SECRET"),
            "apiTokenGrantsAdmin": api_token_grants_admin(),
            "trustApiTokenClientId": trust_api_token_client_id(),
            "diagnosticsAllowed": allowed,
        },
    )


def _probe_tool(id_: str, label: str, checker: Callable[[], bool]) -> ComponentStatus:
    try:
        ok = bool(checker())
    except Exception as exc:
        return ComponentStatus(
            id=id_,
            label=label,
            grade=DiagnosticGrade.UNKNOWN,
            detail=f"probe error: {type(exc).__name__}",
        )
    if ok:
        return ComponentStatus(
            id=id_,
            label=label,
            grade=DiagnosticGrade.AVAILABLE,
            detail="import/binary available (not VERIFIED)",
        )
    return ComponentStatus(
        id=id_,
        label=label,
        grade=DiagnosticGrade.UNKNOWN,
        detail="not available on this host",
    )


def _probe_llm() -> ComponentStatus:
    try:
        from llm_enrich import llm_configured, llm_key_status
    except Exception as exc:
        return ComponentStatus(
            id="llm",
            label="LLM enrich",
            grade=DiagnosticGrade.UNKNOWN,
            detail=f"import failed: {type(exc).__name__}",
        )
    status = llm_key_status()  # never includes secret
    if llm_configured():
        return ComponentStatus(
            id="llm",
            label="LLM enrich",
            grade=DiagnosticGrade.AVAILABLE,
            detail="LLM key present and usable (kind only)",
            meta={"llmKeyStatus": status},
        )
    if status.get("present"):
        return ComponentStatus(
            id="llm",
            label="LLM enrich",
            grade=DiagnosticGrade.CONFIGURED,
            detail="key present but not usable for Console API",
            meta={"llmKeyStatus": status},
        )
    return ComponentStatus(
        id="llm",
        label="LLM enrich",
        grade=DiagnosticGrade.UNKNOWN,
        detail="no LLM key configured",
        meta={"llmKeyStatus": status},
    )


def _probe_deploy_artifacts() -> ComponentStatus:
    """Repo deploy files present next to this package (not live host systemd)."""
    deploy = Path(__file__).resolve().parent / "deploy"
    expected = [
        "scootercheck-fw.service",
        "phase1-rollout.sh",
        "install-on-hetzner.sh",
        "nginx-scootercheck-fw.conf",
    ]
    present = [name for name in expected if (deploy / name).is_file()]
    if len(present) == len(expected):
        return ComponentStatus(
            id="deploy",
            label="Deploy artifacts (repo)",
            grade=DiagnosticGrade.AVAILABLE,
            detail="deploy/ unit + rollout scripts present in tree (host apply not verified)",
            meta={"filesPresent": present},
        )
    if present:
        return ComponentStatus(
            id="deploy",
            label="Deploy artifacts (repo)",
            grade=DiagnosticGrade.CONFIGURED,
            detail="partial deploy/ tree",
            meta={"filesPresent": present, "expected": expected},
        )
    return ComponentStatus(
        id="deploy",
        label="Deploy artifacts (repo)",
        grade=DiagnosticGrade.UNKNOWN,
        detail="deploy/ artifacts missing",
        meta={"expected": expected},
    )


def assemble_diagnostics_status() -> DiagnosticsStatusResponse:
    """Build full status payload from safe probes."""
    warnings = auth_security_warnings()
    allowed, auth_detail = diagnostics_auth_allowed()
    mode = auth_mode_from_env()
    auth = AuthGateStatus(
        authMode=mode,
        authSecurityOk=auth_security_ok(warnings),
        authSecurityCritical=any(w.startswith("CRITICAL:") for w in warnings),
        diagnosticsAllowed=allowed,
        detail=auth_detail,
        warnings=warnings,
    )

    components: list[ComponentStatus] = [
        _probe_auth_component(),
        _probe_decrypt(),
        _probe_ghidra(),
        _probe_workers(),
        _probe_jobs_store(),
        _probe_deploy_artifacts(),
        _probe_llm(),
    ]

    # Optional analysis tools — reuse *_configured() helpers from /health.
    try:
        from r2_extract import r2_configured

        components.append(_probe_tool("r2", "radare2", r2_configured))
    except Exception:
        components.append(
            ComponentStatus(id="r2", label="radare2", grade=DiagnosticGrade.UNKNOWN, detail="import failed")
        )
    try:
        from capstone_extract import capstone_configured

        components.append(_probe_tool("capstone", "Capstone", capstone_configured))
    except Exception:
        components.append(
            ComponentStatus(
                id="capstone", label="Capstone", grade=DiagnosticGrade.UNKNOWN, detail="import failed"
            )
        )
    try:
        from yara_scan import yara_configured

        components.append(_probe_tool("yara", "YARA", yara_configured))
    except Exception:
        components.append(
            ComponentStatus(id="yara", label="YARA", grade=DiagnosticGrade.UNKNOWN, detail="import failed")
        )
    try:
        from unicorn_emulate import unicorn_configured

        components.append(_probe_tool("unicorn", "Unicorn", unicorn_configured))
    except Exception:
        components.append(
            ComponentStatus(
                id="unicorn", label="Unicorn", grade=DiagnosticGrade.UNKNOWN, detail="import failed"
            )
        )
    try:
        from angr_lite import angr_configured, angr_engine_available

        components.append(_probe_tool("angr_lite", "angr lite", angr_configured))
        components.append(_probe_tool("angr_engine", "angr engine", angr_engine_available))
    except Exception:
        components.append(
            ComponentStatus(id="angr", label="angr", grade=DiagnosticGrade.UNKNOWN, detail="import failed")
        )

    notes = [
        "Grades: CONFIGURED ≠ AVAILABLE ≠ VERIFIED. Flags alone never equal VERIFIED.",
        "TEA VERIFIED → Agent B (diagnostics_tea). Ghidra VERIFIED → Agent C (diagnostics_ghidra).",
        "No secrets, no env dump, no shell API on this surface.",
        "Rate limit / single-flight: see diagnostics_routes.py comments.",
    ]
    if not allowed:
        notes.append(f"Diagnostics endpoints must refuse callers until: {auth_detail}")

    return DiagnosticsStatusResponse(
        ok=True,
        generatedAt=_utc_now_iso(),
        auth=auth,
        components=components,
        notes=notes,
    )


def status_as_dict() -> dict[str, Any]:
    return assemble_diagnostics_status().model_dump(mode="json")
