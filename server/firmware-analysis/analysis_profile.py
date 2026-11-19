"""Versioned Ghidra analysis profile (Phase 2.2G / 2.2H.2).

Canonical, secret-free configuration used for reproducibility and catalog compat.

Phase 2.2H.2: ``analysisProfileHash`` covers only *semantic* analysis parameters.
Runtime / resource fields (timeout, heap, detected Ghidra install string) live in
``runtimeConfig`` and must not flip the catalog-compat hash when the analysis
semantics are identical.
"""
from __future__ import annotations

import hashlib
import json
import os
from typing import Any

ANALYSIS_PROFILE_VERSION = "2.2G.1"
# Bump only when fingerprint / CFG semantics change incompatibly.
ANALYZER_COMPAT = "2"
ANALYZER_ID = "ghidra-export-function-analysis"
FINGERPRINT_VERSION = "2"
CALLGRAPH_SCHEMA_VERSION = 2
FEATURES_VERSION = 1

DEFAULT_PROCESSOR = "ARM:LE:32:Cortex"
DEFAULT_LOADER_BASE = "0x08000000"
DEFAULT_MAX_FUNCTIONS = 2500
DEFAULT_TIMEOUT_SEC = 600
DEFAULT_JAVA_XMX = "2g"

# Fields that affect *how long / where* analysis runs, not the semantic fingerprint.
RUNTIME_SOFT_KEYS = frozenset({"analysisTimeoutSec", "memoryLimit", "ghidraVersion"})
# Volatile / derived keys never enter the hash.
NON_HASH_KEYS = frozenset(
    {
        "analysisProfileHash",
        "analyzedAt",
        "jobId",
        "notes",
        "elapsedSec",
        "wallClock",
        "runtimeConfig",
        "ghidraExecuted",
        "note",
        *RUNTIME_SOFT_KEYS,
    }
)


def _env_bool(name: str, default: bool = True) -> bool:
    raw = os.environ.get(name)
    if raw is None or raw.strip() == "":
        return default
    return raw.strip() not in ("0", "false", "False", "no", "NO")


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None or str(raw).strip() == "":
        return default
    try:
        return int(str(raw).strip())
    except ValueError:
        return default


def detect_ghidra_version() -> str | None:
    """Best-effort Ghidra version from GHIDRA_HOME path or env."""
    explicit = os.environ.get("GHIDRA_VERSION", "").strip()
    if explicit:
        return explicit
    home = os.environ.get("GHIDRA_HOME", "").strip()
    if home:
        name = os.path.basename(os.path.normpath(home))
        if name.startswith("ghidra_"):
            return name.replace("ghidra_", "").replace("_PUBLIC", "")
        # nested install
        try:
            from pathlib import Path

            for child in sorted(Path(home).glob("ghidra_*")):
                n = child.name.replace("ghidra_", "").replace("_PUBLIC", "")
                if n:
                    return n
        except Exception:
            pass
    # Common Hetzner layout
    try:
        from pathlib import Path

        for child in sorted(Path("/opt/ghidra").glob("ghidra_*")):
            n = child.name.replace("ghidra_", "").replace("_PUBLIC", "")
            if n:
                return n
    except Exception:
        pass
    return None


def build_analysis_profile(
    *,
    processor: str | None = None,
    loader_base: str | None = None,
    seed_ivt: bool | None = None,
    max_functions: int | None = None,
    timeout_sec: int | None = None,
    memory_limit: str | None = None,
    ghidra_version: str | None = None,
    enabled_post_scripts: list[str] | None = None,
) -> dict[str, Any]:
    """Build the canonical analysis profile dict (no secrets / timestamps / job ids)."""
    do_seed = _env_bool("GHIDRA_SEED_IVT", True) if seed_ivt is None else bool(seed_ivt)
    pre = ["SeedCortexMEntryPoints.java"] if do_seed else []
    post = enabled_post_scripts or [
        "ExportAllDecompiled.java",
        "ExportSpeedXrefs.java",
        "ExportLimitFunctions.java",
        "ExportFunctionAnalysis.java",
        "ExportCallGraph.java",
    ]
    timeout = (
        timeout_sec if timeout_sec is not None else _env_int("GHIDRA_TIMEOUT_SEC", DEFAULT_TIMEOUT_SEC)
    )
    mem = memory_limit or os.environ.get("GHIDRA_JAVA_XMX") or DEFAULT_JAVA_XMX
    ghidra_ver = ghidra_version or detect_ghidra_version()
    profile: dict[str, Any] = {
        "analysisProfileVersion": ANALYSIS_PROFILE_VERSION,
        "analyzerId": ANALYZER_ID,
        "analyzerCompat": ANALYZER_COMPAT,
        # Still exposed at top-level for poll/UI compatibility; excluded from hash.
        "ghidraVersion": ghidra_ver,
        "processorArchitecture": processor or os.environ.get("GHIDRA_PROCESSOR") or DEFAULT_PROCESSOR,
        "requestedLoaderBase": loader_base
        or os.environ.get("GHIDRA_BASE_ADDR")
        or DEFAULT_LOADER_BASE,
        "thumbMode": True,
        "loader": "BinaryLoader",
        "compilerSpec": "default",
        "enabledPreScripts": pre,
        "enabledPostScripts": post,
        "autoAnalysisOptions": {
            "autoIdentifyFirmware": _env_bool("GHIDRA_AUTO_IDENTIFY", True),
            "seedCortexMEntryPoints": do_seed,
        },
        "maximumFunctions": max_functions
        if max_functions is not None
        else _env_int("GHIDRA_MAX_FUNCTIONS", DEFAULT_MAX_FUNCTIONS),
        "analysisTimeoutSec": timeout,
        "memoryLimit": mem,
        "fingerprintVersion": FINGERPRINT_VERSION,
        "callGraphSchemaVersion": CALLGRAPH_SCHEMA_VERSION,
        "featuresVersion": FEATURES_VERSION,
        "runtimeConfig": {
            "ghidraVersion": ghidra_ver,
            "analysisTimeoutSec": timeout,
            "memoryLimit": mem,
        },
    }
    profile["analysisProfileHash"] = profile_hash(profile)
    return profile


def profile_canonical_bytes(profile: dict[str, Any]) -> bytes:
    """Canonical JSON of *semantic* fields only (no runtime / volatile keys)."""
    payload = {k: v for k, v in profile.items() if k not in NON_HASH_KEYS}
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode(
        "utf-8"
    )


def profile_hash(profile: dict[str, Any]) -> str:
    return hashlib.sha256(profile_canonical_bytes(profile)).hexdigest()


def semantic_profile_hash(profile: dict[str, Any] | None) -> str | None:
    """Recompute semantic hash from a (possibly legacy) profile payload."""
    if not profile:
        return None
    return profile_hash(profile)


def profiles_compatible(
    subject: dict[str, Any] | None,
    reference: dict[str, Any] | None,
) -> tuple[bool, str, list[str]]:
    """Return (ok, status, reasons).

    status: COMPATIBLE | LEGACY_PARTIAL | INCOMPATIBLE | MISSING
    """
    reasons: list[str] = []
    if not reference:
        return False, "MISSING", ["reference profile/catalog missing"]
    if not subject:
        # Subject without embedded profile: allow analyzerCompat-only legacy path
        reasons.append("subject analysisProfile missing — legacy partial compare")
        if str(reference.get("analyzerCompat") or "") != ANALYZER_COMPAT:
            return False, "INCOMPATIBLE", reasons + ["analyzerCompat mismatch"]
        if not reference.get("analysisProfileHash") and not reference.get("analysisProfileVersion"):
            reasons.append("reference catalog lacks analysisProfile — legacy partial")
            return True, "LEGACY_PARTIAL", reasons
        return True, "LEGACY_PARTIAL", reasons

    if str(subject.get("analyzerCompat") or "") != str(reference.get("analyzerCompat") or ""):
        reasons.append("analyzerCompat mismatch")
    if str(subject.get("fingerprintVersion") or "") != str(reference.get("fingerprintVersion") or ""):
        # Older catalogs may omit fingerprintVersion
        if reference.get("fingerprintVersion") is not None and subject.get("fingerprintVersion") is not None:
            reasons.append("fingerprintVersion mismatch")

    # Prefer semantic re-hash so legacy payloads that embedded ghidraVersion in the
    # stored hash still compare as compatible when core params match.
    sub_sem = semantic_profile_hash(subject)
    ref_sem = semantic_profile_hash(reference)
    sub_hash = subject.get("analysisProfileHash")
    ref_hash = reference.get("analysisProfileHash")

    stored_hash_drift = False
    soft_runtime_drift = False
    ref_is_full = bool(
        reference.get("analysisProfileHash")
        or reference.get("analysisProfileVersion")
        or reference.get("analyzerId")
        or reference.get("enabledPreScripts")
    )
    if sub_sem and ref_sem and sub_sem == ref_sem and ref_is_full:
        # Runtime soft fields may still differ — surface for operators.
        for key in sorted(RUNTIME_SOFT_KEYS):
            sv = subject.get(key)
            rv = reference.get(key)
            if sv != rv and (sv is not None or rv is not None):
                soft_runtime_drift = True
                reasons.append(
                    f"soft profile field {key} differs ({sv!r} vs {rv!r}) — still comparable"
                )
                break
        if sub_hash and ref_hash and sub_hash != ref_hash:
            stored_hash_drift = True
            reasons.append(
                "stored analysisProfileHash strings differ but semantic core matches "
                "(Phase 2.2H.2 hash excludes runtime soft fields)"
            )
    elif sub_hash and ref_hash and sub_hash != ref_hash:
        # Both sides claim a stored hash — re-check semantic core before hard-fail.
        if sub_sem and ref_sem and sub_sem == ref_sem:
            stored_hash_drift = True
            reasons.append(
                "stored analysisProfileHash strings differ but semantic core matches "
                "(Phase 2.2H.2 hash excludes runtime soft fields)"
            )
        else:
            reasons.append("analysisProfileHash mismatch (core parameters differ)")
    elif not ref_is_full:
        reasons.append("reference catalog lacks analysisProfile — legacy partial")
    elif sub_sem and ref_sem and sub_sem != ref_sem:
        reasons.append("analysisProfileHash mismatch (core parameters differ)")

    if any("mismatch" in r and "soft" not in r and "stored" not in r for r in reasons):
        return False, "INCOMPATIBLE", reasons
    if any("legacy" in r.lower() for r in reasons) or not ref_hash or stored_hash_drift:
        if not ref_hash:
            reasons.append("reference lacks analysisProfileHash — legacy partial")
        return True, "LEGACY_PARTIAL", reasons
    if soft_runtime_drift:
        # Semantic hash identical; runtime soft drift is informational only.
        return True, "COMPATIBLE", reasons or ["profiles match (runtime soft fields differ)"]
    return True, "COMPATIBLE", reasons or ["profiles match"]


def summarize_profile_for_poll(profile: dict[str, Any] | None) -> dict[str, Any] | None:
    if not profile:
        return None
    runtime = profile.get("runtimeConfig") if isinstance(profile.get("runtimeConfig"), dict) else {}
    return {
        "analysisProfileVersion": profile.get("analysisProfileVersion"),
        "analysisProfileHash": profile.get("analysisProfileHash"),
        "analyzerCompat": profile.get("analyzerCompat"),
        "ghidraVersion": profile.get("ghidraVersion") or runtime.get("ghidraVersion"),
        "processorArchitecture": profile.get("processorArchitecture"),
        "requestedLoaderBase": profile.get("requestedLoaderBase"),
        "enabledPreScripts": profile.get("enabledPreScripts"),
        "maximumFunctions": profile.get("maximumFunctions"),
        "fingerprintVersion": profile.get("fingerprintVersion"),
        "callGraphSchemaVersion": profile.get("callGraphSchemaVersion"),
        "seedCortexMEntryPoints": (profile.get("autoAnalysisOptions") or {}).get(
            "seedCortexMEntryPoints"
        ),
        "runtimeConfig": {
            "ghidraVersion": profile.get("ghidraVersion") or runtime.get("ghidraVersion"),
            "analysisTimeoutSec": profile.get("analysisTimeoutSec")
            or runtime.get("analysisTimeoutSec"),
            "memoryLimit": profile.get("memoryLimit") or runtime.get("memoryLimit"),
        },
    }
