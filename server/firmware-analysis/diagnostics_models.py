"""Cycle 11 diagnostics API models — grades and response shapes.

CONFIGURED ≠ AVAILABLE ≠ VERIFIED ≠ FAILED ≠ UNKNOWN.

Flags alone (env set, /health bools) never equal VERIFIED.
Existence of DECRYPT_CMD / Ghidra headless ⇒ at most AVAILABLE.
VERIFIED requires a successful selftest probe (Agents B/C).
"""
from __future__ import annotations

from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class DiagnosticGrade(str, Enum):
    """Mandatory Cycle 11 grade ladder (kickoff)."""

    CONFIGURED = "CONFIGURED"  # env/flag present; not proven runnable
    AVAILABLE = "AVAILABLE"  # binary/path exists; still not end-to-end
    VERIFIED = "VERIFIED"  # probe succeeded (selftest / fixture run)
    FAILED = "FAILED"  # probe ran and failed
    UNKNOWN = "UNKNOWN"  # cannot determine from safe probes


class ComponentStatus(BaseModel):
    """One subsystem row for GET /v1/diagnostics/status."""

    id: str
    label: str
    grade: DiagnosticGrade = DiagnosticGrade.UNKNOWN
    detail: str = ""
    # Optional structured hints — never secrets or absolute key material.
    meta: dict[str, Any] = Field(default_factory=dict)


class AuthGateStatus(BaseModel):
    """Auth posture for diagnostics (booleans only; no tokens)."""

    authMode: str
    authSecurityOk: bool
    authSecurityCritical: bool
    diagnosticsAllowed: bool
    detail: str = ""
    warnings: list[str] = Field(default_factory=list)


class DiagnosticsStatusResponse(BaseModel):
    ok: bool
    service: str = "scootercheck-fw"
    generatedAt: str
    auth: AuthGateStatus
    components: list[ComponentStatus] = Field(default_factory=list)
    # Pointers for ops — paths as configured names only when safe.
    notes: list[str] = Field(default_factory=list)


class SelftestRequest(BaseModel):
    """POST /v1/diagnostics/selftest body.

    Agents B/C own TEA / Ghidra probe depth. Agent A only schedules a
    lightweight orchestration job and existence-level checks.
    """

    includeTea: bool = True
    includeGhidra: bool = True
    includeWorkers: bool = True
    # Never accept firmware bytes or secret material on this endpoint.


class SelftestJobStatus(BaseModel):
    jobId: str
    state: str  # queued | running | completed | failed | refused
    progressPercent: int = 0
    message: str = ""
    errorCode: str | None = None
    createdAt: str
    updatedAt: str
    result: dict[str, Any] | None = None


class SelftestCreateResponse(BaseModel):
    jobId: str
    state: str
    message: str = ""
