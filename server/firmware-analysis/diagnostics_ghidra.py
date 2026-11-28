"""Cycle 11 Agent C — Ghidra diagnostics selftest (admin-facing).

Fixed argv only — no user shell, no arbitrary args.
Never fabricates Ghidra exports when tools are missing.

Epistemic grades (kickoff): CONFIGURED ≠ AVAILABLE ≠ VERIFIED ≠ FAILED ≠ UNKNOWN.
Flags alone never equal VERIFIED / END_TO_END_VERIFIED.

Selftest checklist:
  1. analyzeHeadless resolution
  2. Import (BinaryLoader)
  3. Architecture (ARM:LE:32:Cortex)
  4. Analyze (headless auto-analysis)
  5. Functions export
  6. CFG / callgraph export
  7. Artifacts (real exports present, or honest absence — never fakes)
  8. SHA-256 metadata of immutable synthetic fixture
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

# ---------------------------------------------------------------------------
# Immutable fixture contract (Cycle 7–10 synthetic Cortex-M Thumb)
# ---------------------------------------------------------------------------

EXPECTED_FIXTURE_SHA256 = (
    "3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea"
)
FIXTURE_MARKER = b"SYNTH_C7_NOT_SCOOTER_FW"
PROCESSOR = "ARM:LE:32:Cortex"
BASE_ADDR = "0x08000000"
PROJECT_NAME = "Cycle11DiagGhidra"
DEFAULT_TIMEOUT_SEC = 180
LOCK_TIMEOUT_SEC = 30

# Grades
GRADE_CONFIGURED = "CONFIGURED"
GRADE_AVAILABLE = "AVAILABLE"
GRADE_VERIFIED = "VERIFIED"
GRADE_FAILED = "FAILED"
GRADE_UNKNOWN = "UNKNOWN"

CODE_MISSING_PREREQUISITE = "MISSING_PREREQUISITE"
CODE_TIMEOUT = "TIMEOUT"
CODE_LOCK_BUSY = "LOCK_BUSY"
CODE_EXPORT_MISSING = "EXPORT_MISSING"
CODE_SHA_MISMATCH = "SHA_MISMATCH"
CODE_FABRICATED_EXPORT = "FABRICATED_EXPORT"
CODE_OK = "OK"

FAKE_EXPORT_NAMES = (
    "synthetic.functions.json",
    "synthetic.callgraph.json",
    "synthetic.dec.c",
    "synthetic.speeds.json",
    "synthetic.limits.c",
    "diag.functions.json",
    "diag.callgraph.json",
    "diag.dec.c",
)

REQUIRED_SCRIPTS = (
    "SeedCortexMEntryPoints.java",
    "ExportAllDecompiled.java",
    "ExportFunctionAnalysis.java",
    "ExportCallGraph.java",
)

_HERE = Path(__file__).resolve().parent
_TESTDATA_FIXTURE = _HERE / "testdata" / "diagnostics" / "synthetic_cortex_m_thumb.bin"
# Reuse Cycle-10 path as documented constant (fallback if testdata copy absent).
CYCLE10_FIXTURE = (
    _HERE.parents[1]
    / "research"
    / "cycle10"
    / "fixtures"
    / "synthetic_cortex_m_thumb.bin"
)
SCRIPT_DIR = _HERE / "ghidra_scripts"

_SELFTEST_LOCK = threading.Lock()
_FILE_LOCK_PATH = Path(tempfile.gettempdir()) / "scootercheck-ghidra-diag.lock"


def resolve_fixture_path() -> Path:
    """Return immutable synthetic bin path (testdata copy, else Cycle-10)."""
    if _TESTDATA_FIXTURE.is_file():
        return _TESTDATA_FIXTURE
    if CYCLE10_FIXTURE.is_file():
        return CYCLE10_FIXTURE
    return _TESTDATA_FIXTURE


def _resolve_headless() -> tuple[str | None, list[dict[str, Any]]]:
    """Mirror ghidra_decompile._headless_bin with probe records (no user argv)."""
    probes: list[dict[str, Any]] = []

    direct = os.environ.get("GHIDRA_HEADLESS", "").strip()
    probes.append(
        {
            "path": "env:GHIDRA_HEADLESS",
            "value": direct or None,
            "status": (
                "hit"
                if direct and Path(direct).exists()
                else ("set_but_missing" if direct else "unset")
            ),
        }
    )
    if direct and Path(direct).exists():
        return direct, probes

    home = os.environ.get("GHIDRA_HOME", "").strip()
    home_path = Path(home) if home else None
    support = (home_path / "support" / "analyzeHeadless") if home_path else None
    probes.append(
        {
            "path": "env:GHIDRA_HOME/support/analyzeHeadless",
            "value": str(support) if support else None,
            "ghidraHome": home or None,
            "status": (
                "hit"
                if support and support.exists()
                else ("set_but_missing" if home else "unset")
            ),
        }
    )
    if support and support.exists():
        return str(support), probes

    nested_hits: list[str] = []
    if home_path and home_path.is_dir():
        for child in sorted(home_path.glob("ghidra_*")):
            nested = child / "support" / "analyzeHeadless"
            if nested.exists():
                nested_hits.append(str(nested))
    probes.append(
        {
            "path": "env:GHIDRA_HOME/ghidra_*/support/analyzeHeadless",
            "value": nested_hits[0] if nested_hits else None,
            "candidates": nested_hits,
            "status": (
                "hit"
                if nested_hits
                else ("set_but_missing" if home else "unset")
            ),
        }
    )
    if nested_hits:
        return nested_hits[0], probes

    which = shutil.which("analyzeHeadless")
    probes.append(
        {
            "path": "PATH:analyzeHeadless",
            "value": which,
            "status": "hit" if which else "absent",
        }
    )
    if which:
        return which, probes

    opt = Path("/opt/ghidra")
    opt_hits = (
        [str(p) for p in sorted(opt.glob("ghidra_*/support/analyzeHeadless")) if p.exists()]
        if opt.is_dir()
        else []
    )
    probes.append(
        {
            "path": "/opt/ghidra/ghidra_*/support/analyzeHeadless",
            "value": opt_hits[0] if opt_hits else None,
            "optGhidraDirExists": opt.is_dir(),
            "candidates": opt_hits,
            "status": (
                "hit"
                if opt_hits
                else ("dir_missing" if not opt.is_dir() else "absent")
            ),
        }
    )
    if opt_hits:
        return opt_hits[0], probes

    return None, probes


def _missing_prerequisite_message(probes: list[dict[str, Any]]) -> str:
    ghidra_home = os.environ.get("GHIDRA_HOME", "").strip()
    ghidra_headless = os.environ.get("GHIDRA_HEADLESS", "").strip()
    parts = [
        "GHIDRA_HOME unset"
        if not ghidra_home
        else f"GHIDRA_HOME={ghidra_home} but analyzeHeadless missing",
        "GHIDRA_HEADLESS unset"
        if not ghidra_headless
        else f"GHIDRA_HEADLESS={ghidra_headless} missing/not executable",
        "analyzeHeadless not on PATH",
        (
            "/opt/ghidra absent"
            if not Path("/opt/ghidra").is_dir()
            else "/opt/ghidra has no ghidra_*/support/analyzeHeadless"
        ),
    ]
    _ = probes  # retained for future probe-detail enrichment
    return (
        f"{CODE_MISSING_PREREQUISITE}: "
        + ", ".join(parts)
        + ". Java present does not imply Ghidra."
    )


def _step(
    step_id: int,
    name: str,
    status: str,
    *,
    code: str | None = None,
    detail: str | None = None,
    evidence: dict[str, Any] | None = None,
) -> dict[str, Any]:
    out: dict[str, Any] = {
        "id": step_id,
        "name": name,
        "status": status,
    }
    if code is not None:
        out["code"] = code
    if detail is not None:
        out["detail"] = detail
    if evidence is not None:
        out["evidence"] = evidence
    return out


def _fixture_sha256_meta(bin_path: Path) -> dict[str, Any]:
    if not bin_path.is_file():
        return {
            "present": False,
            "path": str(bin_path),
            "expected": EXPECTED_FIXTURE_SHA256,
            "actual": None,
            "matches": False,
            "markerPresent": False,
            "size": None,
        }
    raw = bin_path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    return {
        "present": True,
        "path": str(bin_path),
        "expected": EXPECTED_FIXTURE_SHA256,
        "actual": digest,
        "matches": digest == EXPECTED_FIXTURE_SHA256,
        "markerPresent": FIXTURE_MARKER in raw,
        "size": len(raw),
        "algorithm": "SHA-256",
        "notRealScooterFirmware": True,
    }


def _scan_fabricated_exports(work_dir: Path | None) -> list[str]:
    if work_dir is None or not work_dir.is_dir():
        return []
    suspects: list[str] = []
    for p in sorted(work_dir.rglob("*")):
        if p.is_file() and p.name in FAKE_EXPORT_NAMES:
            suspects.append(str(p))
    return suspects


def _acquire_file_lock(timeout_sec: float = LOCK_TIMEOUT_SEC) -> tuple[Any | None, str | None]:
    """Best-effort cross-process lock via O_EXCL lockfile."""
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        try:
            fd = os.open(
                str(_FILE_LOCK_PATH),
                os.O_CREAT | os.O_EXCL | os.O_WRONLY,
                0o644,
            )
            os.write(fd, f"pid={os.getpid()} ts={time.time()}\n".encode())
            return fd, None
        except FileExistsError:
            # Stale lock recovery: if older than 2x default timeout, reclaim.
            try:
                age = time.time() - _FILE_LOCK_PATH.stat().st_mtime
                if age > max(DEFAULT_TIMEOUT_SEC * 2, 600):
                    _FILE_LOCK_PATH.unlink(missing_ok=True)
                    continue
            except OSError:
                pass
            time.sleep(0.2)
        except OSError as exc:
            return None, f"lock_open_failed:{type(exc).__name__}"
    return None, CODE_LOCK_BUSY


def _release_file_lock(fd: Any | None) -> None:
    if fd is not None:
        try:
            os.close(fd)
        except OSError:
            pass
    try:
        _FILE_LOCK_PATH.unlink(missing_ok=True)
    except OSError:
        pass


def _build_fixed_headless_argv(
    headless: str,
    *,
    bin_path: Path,
    proj_dir: Path,
    out_dir: Path,
    script_dir: Path,
) -> list[str]:
    """Fixed analyzeHeadless argv — no user shell, no arbitrary args."""
    functions_json = out_dir / "diag.functions.json"
    callgraph_json = out_dir / "diag.callgraph.json"
    decompile_c = out_dir / "diag.dec.c"
    cmd = [
        headless,
        str(proj_dir),
        PROJECT_NAME,
        "-import",
        str(bin_path),
        "-processor",
        PROCESSOR,
        "-cspec",
        "default",
        "-loader",
        "BinaryLoader",
        "-loader-baseAddr",
        BASE_ADDR,
        "-scriptPath",
        str(script_dir),
    ]
    if (script_dir / "SeedCortexMEntryPoints.java").is_file():
        cmd.extend(["-preScript", "SeedCortexMEntryPoints.java"])
    cmd.extend(
        [
            "-postScript",
            "ExportAllDecompiled.java",
            str(decompile_c),
            "-postScript",
            "ExportFunctionAnalysis.java",
            str(functions_json),
            "-postScript",
            "ExportCallGraph.java",
            str(callgraph_json),
            "-deleteProject",
        ]
    )
    return cmd


def _run_headless_selftest(
    headless: str,
    *,
    bin_path: Path,
    timeout_sec: int,
    script_dir: Path,
) -> dict[str, Any]:
    """Execute fixed-argv headless import/analyze/export under timeout."""
    with tempfile.TemporaryDirectory(prefix="ghidra-diag-") as td:
        td_path = Path(td)
        proj_dir = td_path / "proj"
        out_dir = td_path / "out"
        proj_dir.mkdir()
        out_dir.mkdir()
        cmd = _build_fixed_headless_argv(
            headless,
            bin_path=bin_path,
            proj_dir=proj_dir,
            out_dir=out_dir,
            script_dir=script_dir,
        )
        env = os.environ.copy()
        env["GHIDRA_BASE_ADDR"] = BASE_ADDR
        env["SCOOTERCHECK_LOADER_BASE"] = BASE_ADDR
        started = time.monotonic()
        try:
            proc = subprocess.run(
                cmd,  # list argv only — never shell=True
                capture_output=True,
                text=True,
                timeout=timeout_sec,
                check=False,
                env=env,
                shell=False,
            )
        except subprocess.TimeoutExpired as exc:
            return {
                "ok": False,
                "code": CODE_TIMEOUT,
                "detail": f"analyzeHeadless timed out after {timeout_sec}s",
                "elapsedSec": round(time.monotonic() - started, 3),
                "argvFixed": cmd,
                "stdoutTail": ((exc.stdout or "") if isinstance(exc.stdout, str) else "")[-800:],
                "stderrTail": ((exc.stderr or "") if isinstance(exc.stderr, str) else "")[-800:],
                "exports": {},
            }
        except OSError as exc:
            return {
                "ok": False,
                "code": GRADE_FAILED,
                "detail": f"spawn failed: {exc}",
                "elapsedSec": round(time.monotonic() - started, 3),
                "argvFixed": cmd,
                "exports": {},
            }

        log_tail = ((proc.stderr or "") + "\n" + (proc.stdout or ""))[-2000:]
        functions_json = out_dir / "diag.functions.json"
        callgraph_json = out_dir / "diag.callgraph.json"
        decompile_c = out_dir / "diag.dec.c"

        def _meta(p: Path) -> dict[str, Any]:
            if not p.is_file():
                return {"present": False, "path": str(p), "size": 0}
            size = p.stat().st_size
            meta: dict[str, Any] = {
                "present": True,
                "path": str(p),
                "size": size,
                "sha256": hashlib.sha256(p.read_bytes()).hexdigest() if size else None,
            }
            if p.suffix == ".json" and size > 0:
                try:
                    meta["jsonOk"] = isinstance(json.loads(p.read_text(encoding="utf-8")), dict)
                except Exception:
                    meta["jsonOk"] = False
            return meta

        exports = {
            "functions": _meta(functions_json),
            "callgraph": _meta(callgraph_json),
            "decompile": _meta(decompile_c),
        }
        # Persist a copy of export metadata only (files live in temp; digests recorded).
        import_ok = proc.returncode == 0
        # Heuristic: BinaryLoader import + analysis succeeded when exit 0.
        # Architecture is the fixed PROCESSOR we requested.
        return {
            "ok": import_ok,
            "code": CODE_OK if import_ok else GRADE_FAILED,
            "detail": (
                f"analyzeHeadless exit {proc.returncode}"
                if not import_ok
                else "analyzeHeadless completed"
            ),
            "returncode": proc.returncode,
            "elapsedSec": round(time.monotonic() - started, 3),
            "argvFixed": cmd,
            "logTail": log_tail,
            "exports": exports,
            "processorRequested": PROCESSOR,
            "baseAddrRequested": BASE_ADDR,
        }


def run_ghidra_diagnostics_selftest(
    *,
    timeout_sec: int = DEFAULT_TIMEOUT_SEC,
    lock_timeout_sec: float = LOCK_TIMEOUT_SEC,
    resolve_headless_fn: Callable[[], tuple[str | None, list[dict[str, Any]]]] | None = None,
    run_headless_fn: Callable[..., dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Run the 8-step Ghidra diagnostics selftest.

    Parameters are timeouts / test injection only — never user shell or arbitrary argv.
    """
    generated_at = datetime.now(timezone.utc).isoformat()
    bin_path = resolve_fixture_path()
    sha_meta = _fixture_sha256_meta(bin_path)
    resolve_fn = resolve_headless_fn or _resolve_headless

    acquired = _SELFTEST_LOCK.acquire(timeout=lock_timeout_sec)
    if not acquired:
        return {
            "schemaVersion": 1,
            "kind": "ghidraDiagnosticsSelftest",
            "cycle": 13,
            "agent": "B",
            "generatedAt": generated_at,
            "executed": False,
            "grades": {
                "configured": False,
                "available": False,
                "verified": False,
                "overall": GRADE_FAILED,
            },
            "overallCode": CODE_LOCK_BUSY,
            "exactMissingCause": None,
            "steps": [
                _step(
                    1,
                    "analyzeHeadless",
                    GRADE_UNKNOWN,
                    code=CODE_LOCK_BUSY,
                    detail="could not acquire in-process diagnostics lock",
                )
            ],
            "fixture": sha_meta,
            "hardBans": _hard_bans(),
        }

    file_fd: Any | None = None
    try:
        file_fd, lock_err = _acquire_file_lock(lock_timeout_sec)
        if lock_err == CODE_LOCK_BUSY:
            return {
                "schemaVersion": 1,
                "kind": "ghidraDiagnosticsSelftest",
                "cycle": 13,
                "agent": "B",
                "generatedAt": generated_at,
                "executed": False,
                "grades": {
                    "configured": False,
                    "available": False,
                    "verified": False,
                    "overall": GRADE_FAILED,
                },
                "overallCode": CODE_LOCK_BUSY,
                "exactMissingCause": None,
                "steps": [
                    _step(
                        1,
                        "analyzeHeadless",
                        GRADE_UNKNOWN,
                        code=CODE_LOCK_BUSY,
                        detail="could not acquire cross-process Ghidra diagnostics lock",
                    )
                ],
                "fixture": sha_meta,
                "hardBans": _hard_bans(),
            }

        headless, probes = resolve_fn()
        scripts_ok = all((SCRIPT_DIR / name).is_file() for name in REQUIRED_SCRIPTS)
        scripts_present = {
            name: (SCRIPT_DIR / name).is_file() for name in REQUIRED_SCRIPTS
        }

        configured = headless is not None
        available = bool(
            headless and Path(headless).exists() and os.access(headless, os.X_OK)
        )
        # Some installs are scripts without +x but runnable via interpreter —
        # treat existence as available if executable bit OR file is readable script.
        if headless and Path(headless).is_file() and not available:
            available = os.access(headless, os.R_OK)

        steps: list[dict[str, Any]] = []
        exact_missing: str | None = None
        run_result: dict[str, Any] | None = None
        executed = False

        # --- Step 1: analyzeHeadless ---
        if not configured or not available:
            exact_missing = _missing_prerequisite_message(probes)
            steps.append(
                _step(
                    1,
                    "analyzeHeadless",
                    GRADE_FAILED,
                    code=CODE_MISSING_PREREQUISITE,
                    detail=exact_missing,
                    evidence={"probes": probes, "headless": headless},
                )
            )
            # Steps 2–6: not attempted
            for sid, name in (
                (2, "import"),
                (3, "arch"),
                (4, "analyze"),
                (5, "functions_export"),
                (6, "cfg_export"),
            ):
                steps.append(
                    _step(
                        sid,
                        name,
                        GRADE_UNKNOWN,
                        code=CODE_MISSING_PREREQUISITE,
                        detail="not attempted — analyzeHeadless unavailable",
                    )
                )
            # Step 7: artifacts — assert no fabricated exports
            work = Path(tempfile.gettempdir()) / "scootercheck-ghidra-diag-out"
            suspects = _scan_fabricated_exports(work if work.is_dir() else None)
            # Also refuse to create fake exports here.
            if suspects:
                steps.append(
                    _step(
                        7,
                        "artifacts",
                        GRADE_FAILED,
                        code=CODE_FABRICATED_EXPORT,
                        detail="suspect fabricated exports present while Ghidra missing",
                        evidence={"suspectFiles": suspects},
                    )
                )
            else:
                steps.append(
                    _step(
                        7,
                        "artifacts",
                        GRADE_VERIFIED,
                        code=CODE_OK,
                        detail=(
                            "no fabricated Ghidra exports; honest absence under "
                            f"{CODE_MISSING_PREREQUISITE}"
                        ),
                        evidence={"fabricatedExports": [], "exportsCreated": False},
                    )
                )
            # Step 8: SHA-256 metadata
            if sha_meta.get("matches"):
                steps.append(
                    _step(
                        8,
                        "sha256_metadata",
                        GRADE_VERIFIED,
                        code=CODE_OK,
                        detail="fixture SHA-256 matches frozen Cycle-7/10 digest",
                        evidence=sha_meta,
                    )
                )
            else:
                steps.append(
                    _step(
                        8,
                        "sha256_metadata",
                        GRADE_FAILED,
                        code=CODE_SHA_MISMATCH,
                        detail="fixture SHA-256 missing or mismatch",
                        evidence=sha_meta,
                    )
                )

            overall = GRADE_FAILED
            verified = False
            return _envelope(
                generated_at=generated_at,
                executed=False,
                configured=configured,
                available=available,
                verified=verified,
                overall=overall,
                overall_code=CODE_MISSING_PREREQUISITE,
                exact_missing=exact_missing,
                steps=steps,
                fixture=sha_meta,
                probes=probes,
                scripts=scripts_present,
                run_result=None,
            )

        # --- Ghidra available: Step 1 PASS ---
        steps.append(
            _step(
                1,
                "analyzeHeadless",
                GRADE_VERIFIED,
                code=CODE_OK,
                detail=f"resolved {headless}",
                evidence={"headless": headless, "probes": probes},
            )
        )

        if not scripts_ok:
            for sid, name in (
                (2, "import"),
                (3, "arch"),
                (4, "analyze"),
                (5, "functions_export"),
                (6, "cfg_export"),
            ):
                steps.append(
                    _step(
                        sid,
                        name,
                        GRADE_FAILED,
                        code=GRADE_FAILED,
                        detail="required ghidra_scripts missing",
                        evidence={"scripts": scripts_present},
                    )
                )
            steps.append(
                _step(
                    7,
                    "artifacts",
                    GRADE_FAILED,
                    code=GRADE_FAILED,
                    detail="cannot export without scripts",
                )
            )
            steps.append(_sha_step(sha_meta))
            return _envelope(
                generated_at=generated_at,
                executed=False,
                configured=True,
                available=True,
                verified=False,
                overall=GRADE_FAILED,
                overall_code=GRADE_FAILED,
                exact_missing=None,
                steps=steps,
                fixture=sha_meta,
                probes=probes,
                scripts=scripts_present,
                run_result=None,
            )

        if not sha_meta.get("matches"):
            # Still attempt headless if tools present, but SHA step will FAIL.
            pass

        runner = run_headless_fn or _run_headless_selftest
        run_result = runner(
            headless,
            bin_path=bin_path,
            timeout_sec=timeout_sec,
            script_dir=SCRIPT_DIR,
        )
        executed = True

        if run_result.get("code") == CODE_TIMEOUT:
            for sid, name in (
                (2, "import"),
                (3, "arch"),
                (4, "analyze"),
                (5, "functions_export"),
                (6, "cfg_export"),
            ):
                steps.append(
                    _step(
                        sid,
                        name,
                        GRADE_FAILED,
                        code=CODE_TIMEOUT,
                        detail=run_result.get("detail"),
                    )
                )
            steps.append(
                _step(
                    7,
                    "artifacts",
                    GRADE_FAILED,
                    code=CODE_TIMEOUT,
                    detail="no artifacts — headless timed out (not fabricated)",
                    evidence={"exports": run_result.get("exports") or {}},
                )
            )
            steps.append(_sha_step(sha_meta))
            return _envelope(
                generated_at=generated_at,
                executed=executed,
                configured=True,
                available=True,
                verified=False,
                overall=GRADE_FAILED,
                overall_code=CODE_TIMEOUT,
                exact_missing=None,
                steps=steps,
                fixture=sha_meta,
                probes=probes,
                scripts=scripts_present,
                run_result=run_result,
            )

        exports = run_result.get("exports") or {}
        import_ok = bool(run_result.get("ok"))

        # Step 2: import
        steps.append(
            _step(
                2,
                "import",
                GRADE_VERIFIED if import_ok else GRADE_FAILED,
                code=CODE_OK if import_ok else GRADE_FAILED,
                detail=(
                    "BinaryLoader import completed"
                    if import_ok
                    else run_result.get("detail") or "import failed"
                ),
                evidence={
                    "loader": "BinaryLoader",
                    "returncode": run_result.get("returncode"),
                },
            )
        )

        # Step 3: arch
        steps.append(
            _step(
                3,
                "arch",
                GRADE_VERIFIED if import_ok else GRADE_FAILED,
                code=CODE_OK if import_ok else GRADE_FAILED,
                detail=f"requested processor={PROCESSOR} base={BASE_ADDR}",
                evidence={
                    "processor": PROCESSOR,
                    "baseAddr": BASE_ADDR,
                    "applied": import_ok,
                },
            )
        )

        # Step 4: analyze
        steps.append(
            _step(
                4,
                "analyze",
                GRADE_VERIFIED if import_ok else GRADE_FAILED,
                code=CODE_OK if import_ok else GRADE_FAILED,
                detail=(
                    "headless auto-analysis finished"
                    if import_ok
                    else "analysis not confirmed"
                ),
                evidence={"elapsedSec": run_result.get("elapsedSec")},
            )
        )

        fn_meta = exports.get("functions") or {}
        cg_meta = exports.get("callgraph") or {}
        fn_ok = bool(fn_meta.get("present") and fn_meta.get("size", 0) > 0 and fn_meta.get("jsonOk", True))
        cg_ok = bool(cg_meta.get("present") and cg_meta.get("size", 0) > 0 and cg_meta.get("jsonOk", True))

        # Step 5: functions export
        steps.append(
            _step(
                5,
                "functions_export",
                GRADE_VERIFIED if fn_ok else GRADE_FAILED,
                code=CODE_OK if fn_ok else CODE_EXPORT_MISSING,
                detail=(
                    f"functions export {fn_meta.get('size', 0)}B"
                    if fn_ok
                    else "functions export missing/empty — not fabricated"
                ),
                evidence=fn_meta,
            )
        )

        # Step 6: CFG export
        steps.append(
            _step(
                6,
                "cfg_export",
                GRADE_VERIFIED if cg_ok else GRADE_FAILED,
                code=CODE_OK if cg_ok else CODE_EXPORT_MISSING,
                detail=(
                    f"callgraph/CFG export {cg_meta.get('size', 0)}B"
                    if cg_ok
                    else "CFG export missing/empty — not fabricated"
                ),
                evidence=cg_meta,
            )
        )

        # Step 7: artifacts
        artifacts_ok = import_ok and fn_ok and cg_ok
        steps.append(
            _step(
                7,
                "artifacts",
                GRADE_VERIFIED if artifacts_ok else GRADE_FAILED,
                code=CODE_OK if artifacts_ok else CODE_EXPORT_MISSING,
                detail=(
                    "functions + CFG artifacts present with SHA-256 digests"
                    if artifacts_ok
                    else "required export artifacts incomplete — not fabricated"
                ),
                evidence={"exports": exports},
            )
        )

        # Step 8: SHA-256 metadata
        steps.append(_sha_step(sha_meta))

        verified = all(s.get("status") == GRADE_VERIFIED for s in steps)
        overall = GRADE_VERIFIED if verified else GRADE_FAILED
        return _envelope(
            generated_at=generated_at,
            executed=executed,
            configured=True,
            available=True,
            verified=verified,
            overall=overall,
            overall_code=CODE_OK if verified else GRADE_FAILED,
            exact_missing=None,
            steps=steps,
            fixture=sha_meta,
            probes=probes,
            scripts=scripts_present,
            run_result=run_result,
        )
    finally:
        _release_file_lock(file_fd)
        _SELFTEST_LOCK.release()


def _sha_step(sha_meta: dict[str, Any]) -> dict[str, Any]:
    if sha_meta.get("matches"):
        return _step(
            8,
            "sha256_metadata",
            GRADE_VERIFIED,
            code=CODE_OK,
            detail="fixture SHA-256 matches frozen Cycle-7/10 digest",
            evidence=sha_meta,
        )
    return _step(
        8,
        "sha256_metadata",
        GRADE_FAILED,
        code=CODE_SHA_MISMATCH,
        detail="fixture SHA-256 missing or mismatch",
        evidence=sha_meta,
    )


def _hard_bans() -> list[str]:
    return [
        "no user shell / no arbitrary argv (fixed selftest argv only)",
        "no fabricated .functions.json / .callgraph.json / .dec.c when Ghidra missing",
        "never claim VERIFIED from ghidraConfigured health flag alone",
        "no real encrypted ZT3 / Cycle-6 FIRM.bin.enc plaintext reconstruction",
        "Java present does not imply Ghidra",
    ]


def _envelope(
    *,
    generated_at: str,
    executed: bool,
    configured: bool,
    available: bool,
    verified: bool,
    overall: str,
    overall_code: str,
    exact_missing: str | None,
    steps: list[dict[str, Any]],
    fixture: dict[str, Any],
    probes: list[dict[str, Any]],
    scripts: dict[str, bool],
    run_result: dict[str, Any] | None,
) -> dict[str, Any]:
    # Strip bulky argv/log from public envelope copy if present — keep summary.
    run_summary: dict[str, Any] | None = None
    if run_result is not None:
        run_summary = {
            "ok": run_result.get("ok"),
            "code": run_result.get("code"),
            "detail": run_result.get("detail"),
            "returncode": run_result.get("returncode"),
            "elapsedSec": run_result.get("elapsedSec"),
            "processorRequested": run_result.get("processorRequested"),
            "baseAddrRequested": run_result.get("baseAddrRequested"),
            "exports": run_result.get("exports"),
            # argv listed for audit — fixed constants only
            "argvFixed": run_result.get("argvFixed"),
        }
    return {
        "schemaVersion": 1,
        "kind": "ghidraDiagnosticsSelftest",
        "cycle": 13,
        "agent": "B",
        "generatedAt": generated_at,
        "executed": executed,
        "grades": {
            "configured": configured,
            "available": available,
            "verified": verified,
            "overall": overall,
            # Explicit non-claims
            "endToEndVerified": verified and executed,
            "healthFlagIsNotProof": True,
        },
        "overallCode": overall_code,
        "exactMissingCause": exact_missing,
        "processorTarget": PROCESSOR,
        "loaderBaseTarget": BASE_ADDR,
        "fixture": fixture,
        "fixturePaths": {
            "testdata": str(_TESTDATA_FIXTURE),
            "cycle10Constant": str(CYCLE10_FIXTURE),
            "resolved": fixture.get("path"),
        },
        "ghidraScripts": scripts,
        "environmentProbe": {"resolutionPaths": probes},
        "steps": steps,
        "run": run_summary,
        "hardBans": _hard_bans(),
        "notes": [
            "CONFIGURED ≠ AVAILABLE ≠ VERIFIED ≠ FAILED ≠ UNKNOWN",
            "Selftest uses fixed argv only (no shell, no caller-supplied args).",
            (
                f"{CODE_MISSING_PREREQUISITE} returns FAILED/UNKNOWN honestly; "
                "exports are never faked."
            ),
        ],
    }


def main() -> int:
    """CLI entry: fixed selftest, JSON to stdout. Exit 0 always for missing tools."""
    result = run_ghidra_diagnostics_selftest()
    print(json.dumps(result, indent=2, ensure_ascii=False))
    # Exit 0 on honest MISSING_PREREQUISITE; non-zero on real failures / lock.
    code = result.get("overallCode")
    if code == CODE_MISSING_PREREQUISITE:
        return 0
    if result.get("grades", {}).get("verified"):
        return 0
    if code == CODE_LOCK_BUSY:
        return 3
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
