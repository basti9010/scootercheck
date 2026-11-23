"""Safe NinebotTEA / DECRYPT_CMD diagnostics (Cycle 11 Agent B).

Probes configuration and wrapper reachability only. Never decrypts real
firmware packs, never invents keys, and never echoes env secret values
(KEY, tokens, etc.) into the result payload.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any, Mapping, Sequence

# Epistemic grades — CONFIGURED ≠ AVAILABLE ≠ VERIFIED ≠ FAILED ≠ UNKNOWN
GRADE_UNKNOWN = "UNKNOWN"
GRADE_CONFIGURED = "CONFIGURED"
GRADE_AVAILABLE = "AVAILABLE"
GRADE_VERIFIED = "VERIFIED"
GRADE_FAILED = "FAILED"

GRADES = (
    GRADE_UNKNOWN,
    GRADE_CONFIGURED,
    GRADE_AVAILABLE,
    GRADE_VERIFIED,
    GRADE_FAILED,
)

# Documented safe probes only (install script verifies ninebottea with --help).
_SAFE_HELP_FLAGS: tuple[str, ...] = ("--help", "-h")
_SAFE_DRY_FLAGS: tuple[str, ...] = ("--dry-run", "--dry", "--check")

_PROBE_TIMEOUT_SEC = 5.0
_MAX_OUTPUT_CHARS = 240

# Tokens that must never appear in diagnostic output (case-insensitive).
_SECRET_ENV_NAMES = frozenset(
    {
        "KEY",
        "NINEBOTTEA_KEY",
        "DECRYPT_KEY",
        "API_TOKEN",
        "ADMIN_API_TOKEN",
        "JWT_SECRET",
        "LLM_API_KEY",
    }
)


def _env_get(environ: Mapping[str, str] | None, name: str) -> str:
    src: Mapping[str, str] = environ if environ is not None else os.environ
    return (src.get(name) or "").strip()


def _cmd_tokens(decrypt_cmd: str) -> list[str]:
    # DECRYPT_CMD is a single executable path in production; allow a leading
    # token only (no shell). Do not split on spaces inside paths — use first
    # token for which() when the full path is missing, matching app.run_decrypt.
    return decrypt_cmd.split()


def redact_decrypt_cmd(decrypt_cmd: str) -> dict[str, Any]:
    """Describe DECRYPT_CMD without leaking full host paths or secrets."""
    raw = (decrypt_cmd or "").strip()
    if not raw:
        return {
            "set": False,
            "tokenCount": 0,
            "basename": None,
            "looksAbsolute": False,
        }
    tokens = _cmd_tokens(raw)
    first = tokens[0] if tokens else ""
    return {
        "set": True,
        "tokenCount": len(tokens),
        "basename": Path(first).name or None,
        "looksAbsolute": first.startswith("/"),
        # Length only — never the path string itself (host layout / accidental secrets).
        "firstTokenLength": len(first),
    }


def _which_first(decrypt_cmd: str) -> str | None:
    tokens = _cmd_tokens(decrypt_cmd)
    if not tokens:
        return None
    return shutil.which(tokens[0])


def resolve_wrapper(decrypt_cmd: str) -> dict[str, Any]:
    """Resolve wrapper path via Path.exists or shutil.which (same idea as app.py)."""
    raw = (decrypt_cmd or "").strip()
    if not raw:
        return {
            "configured": False,
            "exists": False,
            "via": None,
            "executable": False,
            "resolvedBasename": None,
        }

    tokens = _cmd_tokens(raw)
    first = tokens[0]
    path = Path(first)
    if path.exists():
        return {
            "configured": True,
            "exists": True,
            "via": "path",
            "executable": os.access(first, os.X_OK),
            "resolvedBasename": path.name,
            "isFile": path.is_file(),
        }

    found = shutil.which(first)
    if found:
        return {
            "configured": True,
            "exists": True,
            "via": "which",
            "executable": os.access(found, os.X_OK),
            "resolvedBasename": Path(found).name,
            "isFile": Path(found).is_file(),
        }

    return {
        "configured": True,
        "exists": False,
        "via": None,
        "executable": False,
        "resolvedBasename": Path(first).name,
        "isFile": False,
    }


def _read_text_prefix(path: Path, limit: int = 16_384) -> str | None:
    try:
        if not path.is_file():
            return None
        # Skip obvious binaries
        data = path.read_bytes()[:limit]
        if b"\x00" in data[:1024]:
            return None
        return data.decode("utf-8", errors="replace")
    except OSError:
        return None


def detect_documented_safe_flags(wrapper_path: Path | None, *, basename: str | None) -> list[str]:
    """Return safe probe argv only when help/dry flags are documented for this binary.

    - `ninebottea` console script: install verifies with `--help` (documented).
    - Shell wrappers: only if script text mentions those flags (example decrypt
      wrapper does **not** — no inventing).
    """
    name = (basename or (wrapper_path.name if wrapper_path else "") or "").lower()
    if name == "ninebottea" or name.startswith("ninebottea"):
        return ["--help"]

    if wrapper_path is None:
        return []

    text = _read_text_prefix(wrapper_path)
    if not text:
        return []

    found: list[str] = []
    # Prefer long options; require explicit mention in the wrapper source.
    for flag in _SAFE_HELP_FLAGS + _SAFE_DRY_FLAGS:
        # Word-ish match so comments/getopts documenting the flag count.
        if re.search(rf"(?<![\w-]){re.escape(flag)}(?![\w-])", text):
            found.append(flag)
    # At most one probe: prefer --help, then -h, then dry flags.
    for preferred in _SAFE_HELP_FLAGS + _SAFE_DRY_FLAGS:
        if preferred in found:
            return [preferred]
    return []


def _sanitize_probe_output(text: str) -> str:
    """Truncate and strip lines that look like secret assignments."""
    if not text:
        return ""
    cleaned_lines: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        upper = stripped.upper()
        if any(upper.startswith(f"{secret}=") for secret in _SECRET_ENV_NAMES):
            cleaned_lines.append("<redacted-env-assignment>")
            continue
        if re.search(r"(?i)\b(key|token|secret|password)\s*[:=]\s*\S+", stripped):
            cleaned_lines.append("<redacted-secret-line>")
            continue
        cleaned_lines.append(line)
    out = "\n".join(cleaned_lines).strip()
    if len(out) > _MAX_OUTPUT_CHARS:
        out = out[:_MAX_OUTPUT_CHARS] + "…"
    return out


def run_safe_probe(
    decrypt_cmd: str,
    probe_args: Sequence[str],
    *,
    timeout_sec: float = _PROBE_TIMEOUT_SEC,
) -> dict[str, Any]:
    """Run wrapper with documented help/dry args only — never with enc/out paths."""
    if not probe_args:
        return {
            "attempted": False,
            "skippedReason": "no_documented_safe_flag",
            "ok": False,
            "exitCode": None,
            "stdoutPreview": "",
            "stderrPreview": "",
        }

    tokens = _cmd_tokens(decrypt_cmd)
    if not tokens:
        return {
            "attempted": False,
            "skippedReason": "empty_cmd",
            "ok": False,
            "exitCode": None,
            "stdoutPreview": "",
            "stderrPreview": "",
        }

    argv = [tokens[0], *list(probe_args)]
    try:
        proc = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            check=False,
            env=_scrubbed_child_env(),
        )
    except subprocess.TimeoutExpired:
        return {
            "attempted": True,
            "skippedReason": None,
            "ok": False,
            "exitCode": None,
            "error": "timeout",
            "argvBasename": Path(tokens[0]).name,
            "probeArgs": list(probe_args),
            "stdoutPreview": "",
            "stderrPreview": "",
        }
    except OSError as exc:
        return {
            "attempted": True,
            "skippedReason": None,
            "ok": False,
            "exitCode": None,
            "error": f"spawn_failed:{type(exc).__name__}",
            "argvBasename": Path(tokens[0]).name,
            "probeArgs": list(probe_args),
            "stdoutPreview": "",
            "stderrPreview": "",
        }

    stdout = _sanitize_probe_output(proc.stdout or "")
    stderr = _sanitize_probe_output(proc.stderr or "")
    # Help/dry probes often exit 0; some CLIs exit 0/1/2 with usage — treat any
    # completed spawn without timeout as a soft signal; require exit 0 for VERIFIED.
    ok = proc.returncode == 0
    return {
        "attempted": True,
        "skippedReason": None,
        "ok": ok,
        "exitCode": proc.returncode,
        "argvBasename": Path(tokens[0]).name,
        "probeArgs": list(probe_args),
        "stdoutPreview": stdout,
        "stderrPreview": stderr,
    }


def _scrubbed_child_env() -> dict[str, str]:
    """Pass a minimal env to the child — drop known secret names."""
    child: dict[str, str] = {}
    for key, value in os.environ.items():
        if key.upper() in _SECRET_ENV_NAMES or key.upper().endswith(("_KEY", "_TOKEN", "_SECRET")):
            continue
        child[key] = value
    return child


def _overall_grade(
    *,
    configured: bool,
    available: bool,
    probe: dict[str, Any],
) -> str:
    if not configured:
        # Env unset on this host — not a hard failure; readiness unknown here.
        return GRADE_UNKNOWN
    if not available:
        return GRADE_FAILED
    if probe.get("attempted") and probe.get("ok"):
        return GRADE_VERIFIED
    if probe.get("attempted") and not probe.get("ok"):
        # Path exists but documented help/dry failed → FAILED (broken binary).
        return GRADE_FAILED
    # Available, no documented safe probe to escalate with.
    return GRADE_AVAILABLE


def diagnose_tea(
    *,
    decrypt_cmd: str | None = None,
    environ: Mapping[str, str] | None = None,
    run_probe: bool = True,
    timeout_sec: float = _PROBE_TIMEOUT_SEC,
) -> dict[str, Any]:
    """Run safe TEA diagnostics and return a JSON-serializable report dict.

    Grades:
      UNKNOWN    — DECRYPT_CMD unset on this host
      CONFIGURED — reserved for callers that only checked the flag (see
                   `grade_from_configured_flag`); full diagnose escalates past it
      AVAILABLE  — wrapper path exists / which() hit; no verified probe
      VERIFIED   — documented --help / dry flag ran exit 0
      FAILED     — configured but missing, or probe attempted and failed
    """
    cmd = (decrypt_cmd if decrypt_cmd is not None else _env_get(environ, "DECRYPT_CMD")).strip()
    configured = bool(cmd)
    cmd_meta = redact_decrypt_cmd(cmd)
    resolution = resolve_wrapper(cmd) if configured else {
        "configured": False,
        "exists": False,
        "via": None,
        "executable": False,
        "resolvedBasename": None,
        "isFile": False,
    }
    available = bool(resolution.get("exists"))

    probe: dict[str, Any] = {
        "attempted": False,
        "skippedReason": "not_configured" if not configured else (
            "wrapper_missing" if not available else "probe_disabled"
        ),
        "ok": False,
        "exitCode": None,
        "stdoutPreview": "",
        "stderrPreview": "",
    }

    if configured and available and run_probe:
        basename = resolution.get("resolvedBasename")
        via = resolution.get("via")
        wrapper_path: Path | None = None
        if via == "path":
            wrapper_path = Path(_cmd_tokens(cmd)[0])
        elif via == "which":
            found = _which_first(cmd)
            wrapper_path = Path(found) if found else None

        flags = detect_documented_safe_flags(wrapper_path, basename=basename)
        if flags:
            # Prefer invoking via resolved absolute path when which()-found.
            invoke_cmd = str(wrapper_path) if wrapper_path is not None else cmd
            probe = run_safe_probe(invoke_cmd, flags, timeout_sec=timeout_sec)
        else:
            probe = {
                "attempted": False,
                "skippedReason": "no_documented_safe_flag",
                "ok": False,
                "exitCode": None,
                "stdoutPreview": "",
                "stderrPreview": "",
            }

    grade = _overall_grade(configured=configured, available=available, probe=probe)
    # When configured+available but probe skipped, grade is AVAILABLE.
    # Surface CONFIGURED explicitly in checks for health-flag parity.
    checks = {
        "decryptCmdConfigured": {
            "ok": configured,
            "grade": GRADE_CONFIGURED if configured else GRADE_UNKNOWN,
        },
        "wrapperAvailable": {
            "ok": available,
            "grade": (
                GRADE_AVAILABLE
                if available
                else (GRADE_FAILED if configured else GRADE_UNKNOWN)
            ),
            "via": resolution.get("via"),
            "executable": resolution.get("executable"),
        },
        "safeProbe": {
            "ok": bool(probe.get("ok")),
            "grade": (
                GRADE_VERIFIED
                if probe.get("attempted") and probe.get("ok")
                else (
                    GRADE_FAILED
                    if probe.get("attempted")
                    else (
                        GRADE_AVAILABLE
                        if available
                        else (GRADE_FAILED if configured else GRADE_UNKNOWN)
                    )
                )
            ),
            "attempted": bool(probe.get("attempted")),
            "skippedReason": probe.get("skippedReason"),
        },
    }

    return {
        "component": "ninebottea",
        "grade": grade,
        "grades": {
            "CONFIGURED": configured,
            "AVAILABLE": available,
            "VERIFIED": bool(probe.get("attempted") and probe.get("ok")),
            "FAILED": grade == GRADE_FAILED,
            "UNKNOWN": grade == GRADE_UNKNOWN,
        },
        "decryptCmd": cmd_meta,
        "wrapper": resolution,
        "probe": probe,
        "checks": checks,
        "policy": {
            "decryptRealPacks": False,
            "inventKeys": False,
            "echoEnvSecrets": False,
            "safeFlagsOnly": True,
        },
        "notes": _notes(grade=grade, configured=configured, available=available, probe=probe),
    }


def grade_from_configured_flag(decrypt_configured: bool) -> str:
    """Map a boolean health flag alone — never VERIFIED.

    True  → CONFIGURED
    False → UNKNOWN (flag unset; production state not proven from this signal)
    """
    return GRADE_CONFIGURED if decrypt_configured else GRADE_UNKNOWN


def diagnose_tea_cli(argv: Sequence[str] | None = None) -> int:
    """CLI entry: print JSON report to stdout, exit 0 even when grade is FAILED/UNKNOWN."""
    import argparse
    import json
    import sys

    parser = argparse.ArgumentParser(
        description="Safe NinebotTEA / DECRYPT_CMD diagnostics (no real decrypt)."
    )
    parser.add_argument(
        "--decrypt-cmd",
        default=None,
        help="Override DECRYPT_CMD (path only; never pass keys).",
    )
    parser.add_argument(
        "--no-probe",
        action="store_true",
        help="Skip --help/dry probe even when documented.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=_PROBE_TIMEOUT_SEC,
        help="Probe timeout seconds (default 5).",
    )
    args = parser.parse_args(list(argv) if argv is not None else None)
    report = diagnose_tea(
        decrypt_cmd=args.decrypt_cmd,
        run_probe=not args.no_probe,
        timeout_sec=args.timeout,
    )
    json.dump(report, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


def _notes(
    *,
    grade: str,
    configured: bool,
    available: bool,
    probe: Mapping[str, Any],
) -> list[str]:
    notes: list[str] = []
    if not configured:
        notes.append("DECRYPT_CMD unset on this host — grade UNKNOWN (not FAILED).")
    elif not available:
        notes.append("DECRYPT_CMD set but wrapper path/which() miss — grade FAILED.")
    elif probe.get("attempted") and probe.get("ok"):
        notes.append("Documented safe probe (--help/dry) exited 0 — grade VERIFIED.")
    elif probe.get("attempted"):
        notes.append("Documented safe probe failed — grade FAILED.")
    else:
        reason = probe.get("skippedReason") or "unspecified"
        notes.append(
            f"Wrapper reachable; safe probe skipped ({reason}) — grade AVAILABLE "
            "(flags alone never equal VERIFIED)."
        )
    notes.append("Never decrypts real ZT3/ENC packs; never invents keys.")
    return notes


if __name__ == "__main__":
    raise SystemExit(diagnose_tea_cli())
