"""Cycle 12 — post-deploy smoke / rollback decision helpers (no network, no SSH).

Pure functions for CI and unit tests. Scripts (Agent A) may import these; they
must never open sockets or invoke ssh from this module.

Epistemic ladder (deploy):
  DEPLOYED ≠ AVAILABLE ≠ TESTED ≠ END_TO_END_VERIFIED

Diagnostics grades (health / status):
  CONFIGURED ≠ AVAILABLE ≠ VERIFIED ≠ FAILED ≠ UNKNOWN
  Flags alone (decryptConfigured, ghidraConfigured, …) never equal VERIFIED.
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Mapping, Optional, Sequence


class DiagnosticGrade(str, Enum):
    CONFIGURED = "CONFIGURED"
    AVAILABLE = "AVAILABLE"
    VERIFIED = "VERIFIED"
    FAILED = "FAILED"
    UNKNOWN = "UNKNOWN"
    END_TO_END_VERIFIED = "END_TO_END_VERIFIED"
    NOT_CONFIGURED = "NOT_CONFIGURED"


# /health boolean flags that indicate configuration only — never VERIFIED.
HEALTH_CONFIG_FLAGS: tuple[str, ...] = (
    "decryptConfigured",
    "ghidraConfigured",
    "ghidraEnabled",
    "jwtConfigured",
    "apiTokenConfigured",
    "adminApiTokenConfigured",
    "llmConfigured",
    "r2Configured",
    "capstoneConfigured",
    "yaraConfigured",
    "unicornConfigured",
    "angrLiteConfigured",
    "angrEngineConfigured",
)

# Claimed grade keys that must not be inferred from flags alone.
FORBIDDEN_FLAG_ONLY_GRADES: frozenset[str] = frozenset(
    {
        DiagnosticGrade.VERIFIED.value,
        DiagnosticGrade.END_TO_END_VERIFIED.value,
    }
)


class SmokeLogicError(ValueError):
    """Invalid health payload or epistemic grade abuse."""


@dataclass(frozen=True)
class HealthSnapshot:
    """Normalized view of GET /health JSON (fixture-friendly)."""

    ok: bool
    service: str = ""
    raw: Mapping[str, Any] = field(default_factory=dict)
    config_flags: Mapping[str, bool] = field(default_factory=dict)
    auth_mode: Optional[str] = None
    auth_security_ok: Optional[bool] = None
    auth_security_critical: Optional[bool] = None


@dataclass(frozen=True)
class PostDeploySmokeEnv:
    """Env contract for `deploy/post-deploy-smoke.sh` (fixture / unit tests).

    The shell script reads these variables; this dataclass mirrors them so CI
    can assert parsing without SSH or curl.
    """

    health_url: str = "http://127.0.0.1:8088/health"
    service_name: str = "scootercheck-fw"
    smoke_admin_token: str = ""
    remote_smoke: bool = True
    public_smoke: bool = True
    require_diagnostics: bool = False


@dataclass(frozen=True)
class ComponentGradeClaim:
    """A component row claiming an epistemic grade (diagnostics status shape)."""

    component_id: str
    grade: str
    evidence: str = "flags"  # flags | probe | unknown


@dataclass(frozen=True)
class RollbackDecision:
    should_rollback: bool
    reasons: tuple[str, ...] = ()


@dataclass(frozen=True)
class SmokeCliArgs:
    """Expected interface for post-deploy smoke entrypoints (Agent A scripts).

    No network is performed by parse_smoke_argv itself. Callers that actually
    hit HEALTH_URL must do so outside this module and only with Freigabe.
    """

    health_url: str = "http://127.0.0.1:8088/health"
    health_json_path: Optional[str] = None
    timeout_sec: float = 10.0
    require_ok: bool = True
    require_auth_security_ok: bool = False
    forbid_verified_from_flags: bool = True
    dry_run: bool = True
    json_out: Optional[str] = None
    no_ssh: bool = True
    service_name: str = "scootercheck-fw"


def parse_health_json(payload: str | bytes | Mapping[str, Any]) -> HealthSnapshot:
    """Parse /health JSON into a HealthSnapshot. Raises SmokeLogicError on bad input."""
    if isinstance(payload, (str, bytes)):
        try:
            data = json.loads(payload)
        except json.JSONDecodeError as exc:
            raise SmokeLogicError(f"health JSON decode failed: {exc}") from exc
    else:
        data = dict(payload)

    if not isinstance(data, dict):
        raise SmokeLogicError("health payload must be a JSON object")

    ok = data.get("ok")
    if not isinstance(ok, bool):
        raise SmokeLogicError('health payload missing boolean "ok"')

    flags: dict[str, bool] = {}
    for key in HEALTH_CONFIG_FLAGS:
        if key in data:
            val = data[key]
            if not isinstance(val, bool):
                raise SmokeLogicError(f'health flag "{key}" must be boolean')
            flags[key] = val

    auth_ok = data.get("authSecurityOk")
    auth_crit = data.get("authSecurityCritical")
    if auth_ok is not None and not isinstance(auth_ok, bool):
        raise SmokeLogicError("authSecurityOk must be boolean when present")
    if auth_crit is not None and not isinstance(auth_crit, bool):
        raise SmokeLogicError("authSecurityCritical must be boolean when present")

    auth_mode = data.get("authMode")
    if auth_mode is not None and not isinstance(auth_mode, str):
        raise SmokeLogicError("authMode must be a string when present")

    service = data.get("service") or ""
    if service is not None and not isinstance(service, str):
        raise SmokeLogicError("service must be a string when present")

    return HealthSnapshot(
        ok=ok,
        service=str(service),
        raw=data,
        config_flags=flags,
        auth_mode=auth_mode if isinstance(auth_mode, str) else None,
        auth_security_ok=auth_ok if isinstance(auth_ok, bool) else None,
        auth_security_critical=auth_crit if isinstance(auth_crit, bool) else None,
    )


def grade_from_configured_flag(configured: bool) -> DiagnosticGrade:
    """Map a boolean /health config flag alone — never VERIFIED."""
    return DiagnosticGrade.CONFIGURED if configured else DiagnosticGrade.NOT_CONFIGURED


def max_grade_from_health_flags(snapshot: HealthSnapshot) -> DiagnosticGrade:
    """Highest grade justifiable from /health flags alone (≤ CONFIGURED)."""
    if any(snapshot.config_flags.values()):
        return DiagnosticGrade.CONFIGURED
    return DiagnosticGrade.UNKNOWN


def validate_grade_claims(
    claims: Sequence[ComponentGradeClaim],
    *,
    health: Optional[HealthSnapshot] = None,
) -> list[str]:
    """Return error strings for epistemic abuse.

    Fails when VERIFIED / END_TO_END_VERIFIED is claimed with evidence=flags
    or when only CONFIGURED-level health flags are present.
    """
    errors: list[str] = []
    flag_ceiling = max_grade_from_health_flags(health) if health is not None else None

    for claim in claims:
        grade = (claim.grade or "").strip().upper()
        evidence = (claim.evidence or "unknown").strip().lower()

        if grade in FORBIDDEN_FLAG_ONLY_GRADES and evidence in ("flags", "flag", "health", "configured"):
            errors.append(
                f"{claim.component_id}: grade {grade} claimed from {evidence} "
                "(flags alone never equal VERIFIED)"
            )
            continue

        if (
            health is not None
            and grade in FORBIDDEN_FLAG_ONLY_GRADES
            and evidence in ("flags", "flag", "health", "configured", "unknown", "")
        ):
            # Only CONFIGURED (or less) is available from this health snapshot.
            if flag_ceiling in (DiagnosticGrade.CONFIGURED, DiagnosticGrade.UNKNOWN):
                errors.append(
                    f"{claim.component_id}: grade {grade} claimed but health flags "
                    f"only justify {flag_ceiling.value}"
                )
    return errors


def assert_no_verified_from_configured_only(
    claims: Sequence[ComponentGradeClaim],
    *,
    health: Optional[HealthSnapshot] = None,
) -> None:
    """Raise SmokeLogicError if VERIFIED is claimed from CONFIGURED-only evidence."""
    errors = validate_grade_claims(claims, health=health)
    if errors:
        raise SmokeLogicError("; ".join(errors))


def evaluate_rollback(
    *,
    restart_ok: bool,
    health_curl_ok: bool,
    health: Optional[HealthSnapshot] = None,
    import_tests_ok: bool = True,
    live_deploy: bool = True,
) -> RollbackDecision:
    """Mirror phase1-rollout.sh rollback triggers without SSH/network.

    Triggers (live deploy):
      - restart failed
      - health curl failed
      - health payload missing ok=true
      - remote import/tests failed (pre-restart path also rolls back)
    """
    reasons: list[str] = []
    if not live_deploy:
        return RollbackDecision(should_rollback=False, reasons=("dry-run: no rollback",))

    if not import_tests_ok:
        reasons.append("post-sync import/tests failed")
    if not restart_ok:
        reasons.append("service restart failed")
    if not health_curl_ok:
        reasons.append("healthcheck curl failed")
    elif health is None:
        reasons.append("health payload missing")
    elif not health.ok:
        reasons.append('health payload ok!=true')

    return RollbackDecision(should_rollback=bool(reasons), reasons=tuple(reasons))


def health_flag_grade_lines(health: HealthSnapshot) -> dict[str, str]:
    """Mirror post-deploy-smoke.sh: decrypt/ghidra flags → at most CONFIGURED."""
    lines: dict[str, str] = {}
    for key in ("decryptConfigured", "ghidraConfigured"):
        val = health.config_flags.get(key)
        if val is True:
            lines[key] = DiagnosticGrade.CONFIGURED.value
        elif val is False:
            lines[key] = DiagnosticGrade.NOT_CONFIGURED.value
        else:
            lines[key] = DiagnosticGrade.UNKNOWN.value
    return lines


def evaluate_smoke_pass(
    health: HealthSnapshot,
    *,
    require_ok: bool = True,
    require_auth_security_ok: bool = False,
    reject_open_auth: bool = True,
    grade_claims: Sequence[ComponentGradeClaim] = (),
    forbid_verified_from_flags: bool = True,
) -> tuple[bool, tuple[str, ...]]:
    """Decide whether a post-deploy smoke check passes (fixture / parsed health)."""
    failures: list[str] = []
    if require_ok and not health.ok:
        failures.append("health.ok is false")
    if reject_open_auth and (health.auth_mode or "").lower() == "open":
        failures.append("authMode=open unsafe")
    if require_auth_security_ok:
        if health.auth_security_ok is not True:
            failures.append("authSecurityOk is not true")
        if health.auth_security_critical is True:
            failures.append("authSecurityCritical is true")
    if forbid_verified_from_flags and grade_claims:
        failures.extend(validate_grade_claims(grade_claims, health=health))
    return (not failures, tuple(failures))


def parse_post_deploy_smoke_env(environ: Mapping[str, str]) -> PostDeploySmokeEnv:
    """Parse env vars used by `deploy/post-deploy-smoke.sh` (no network)."""

    def _flag(name: str, default: str = "1") -> bool:
        return environ.get(name, default).strip() in ("1", "true", "True", "yes", "YES")

    return PostDeploySmokeEnv(
        health_url=environ.get("HEALTH_URL", "http://127.0.0.1:8088/health"),
        service_name=environ.get("SERVICE_NAME", "scootercheck-fw"),
        smoke_admin_token=environ.get("SMOKE_ADMIN_TOKEN")
        or environ.get("ADMIN_API_TOKEN")
        or "",
        remote_smoke=_flag("REMOTE_SMOKE", "1"),
        public_smoke=_flag("PUBLIC_SMOKE", "1"),
        require_diagnostics=_flag("REQUIRE_DIAGNOSTICS", "0"),
    )


def should_rollback_after_release(*, smoke_passed: bool, release_succeeded: bool) -> bool:
    """Simple CD gate: rollback when release flipped but smoke failed."""
    return bool(release_succeeded and not smoke_passed)


def build_smoke_arg_parser() -> argparse.ArgumentParser:
    """Canonical CLI for post-deploy smoke scripts (expected Agent A interface)."""
    p = argparse.ArgumentParser(
        prog="post-deploy-smoke",
        description=(
            "ScooterCheck post-deploy smoke (Cycle 12). "
            "Prefer --health-json for offline/CI; live --health-url requires Freigabe."
        ),
    )
    p.add_argument(
        "--health-url",
        default="http://127.0.0.1:8088/health",
        help="Health endpoint URL (live probe — not used by parse helpers)",
    )
    p.add_argument(
        "--health-json",
        dest="health_json_path",
        default=None,
        help="Path to fixture /health JSON (offline; preferred in CI)",
    )
    p.add_argument("--timeout-sec", type=float, default=10.0)
    p.add_argument("--require-ok", action=argparse.BooleanOptionalAction, default=True)
    p.add_argument(
        "--require-auth-security-ok",
        action=argparse.BooleanOptionalAction,
        default=False,
    )
    p.add_argument(
        "--forbid-verified-from-flags",
        action=argparse.BooleanOptionalAction,
        default=True,
    )
    dry = p.add_mutually_exclusive_group()
    dry.add_argument(
        "--dry-run",
        dest="dry_run",
        action="store_true",
        default=True,
        help="Default: never SSH / never mutate production",
    )
    dry.add_argument(
        "--live",
        dest="dry_run",
        action="store_false",
        help="Allow live health URL probe (still no deploy; requires Freigabe)",
    )
    ssh = p.add_mutually_exclusive_group()
    ssh.add_argument(
        "--no-ssh",
        dest="no_ssh",
        action="store_true",
        default=True,
        help="Refuse SSH (default for CI / Agent D tests)",
    )
    ssh.add_argument(
        "--allow-ssh",
        dest="no_ssh",
        action="store_false",
        help="Permit SSH from caller script (not used by this pure module)",
    )
    p.add_argument("--json-out", default=None, help="Optional path to write smoke result JSON")
    p.add_argument("--service-name", default="scootercheck-fw")
    return p


def parse_smoke_argv(argv: Optional[Sequence[str]] = None) -> SmokeCliArgs:
    """Parse argv into SmokeCliArgs. Does not touch the network."""
    ns = build_smoke_arg_parser().parse_args(list(argv) if argv is not None else [])
    return SmokeCliArgs(
        health_url=ns.health_url,
        health_json_path=ns.health_json_path,
        timeout_sec=float(ns.timeout_sec),
        require_ok=bool(ns.require_ok),
        require_auth_security_ok=bool(ns.require_auth_security_ok),
        forbid_verified_from_flags=bool(ns.forbid_verified_from_flags),
        dry_run=bool(ns.dry_run),
        json_out=ns.json_out,
        no_ssh=bool(ns.no_ssh),
        service_name=ns.service_name,
    )


def load_health_fixture(path: str) -> HealthSnapshot:
    """Load a health JSON fixture from disk (for tests / offline smoke)."""
    with open(path, encoding="utf-8") as fh:
        return parse_health_json(fh.read())
