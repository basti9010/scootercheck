"""Versioned Ghidra analysis profile (Phase 2.2G).

Canonical, secret-free configuration used for reproducibility and catalog compat.
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
    profile: dict[str, Any] = {
        "analysisProfileVersion": ANALYSIS_PROFILE_VERSION,
        "analyzerId": ANALYZER_ID,
        "analyzerCompat": ANALYZER_COMPAT,
        "ghidraVersion": ghidra_version or detect_ghidra_version(),
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
        "analysisTimeoutSec": timeout_sec
        if timeout_sec is not None
        else _env_int("GHIDRA_TIMEOUT_SEC", DEFAULT_TIMEOUT_SEC),
        "memoryLimit": memory_limit or os.environ.get("GHIDRA_JAVA_XMX") or DEFAULT_JAVA_XMX,
        "fingerprintVersion": FINGERPRINT_VERSION,
        "callGraphSchemaVersion": CALLGRAPH_SCHEMA_VERSION,
        "featuresVersion": FEATURES_VERSION,
    }
    profile["analysisProfileHash"] = profile_hash(profile)
    return profile


def profile_canonical_bytes(profile: dict[str, Any]) -> bytes:
    """Canonical JSON without hash / volatile fields."""
    payload = {
        k: v
        for k, v in profile.items()
        if k
        not in {
            "analysisProfileHash",
            "analyzedAt",
            "jobId",
            "notes",
            "elapsedSec",
            "wallClock",
        }
    }
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode(
        "utf-8"
    )


def profile_hash(profile: dict[str, Any]) -> str:
    return hashlib.sha256(profile_canonical_bytes(profile)).hexdigest()


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
    sub_hash = subject.get("analysisProfileHash")
    ref_hash = reference.get("analysisProfileHash")
    if sub_hash and ref_hash and sub_hash != ref_hash:
        # Soft factors that may differ without breaking fingerprints
        soft_keys = {"analysisTimeoutSec", "memoryLimit", "ghidraVersion"}
        sub_core = {k: v for k, v in subject.items() if k not in soft_keys | {"analysisProfileHash"}}
        ref_core = {k: v for k, v in reference.items() if k not in soft_keys | {"analysisProfileHash"}}
        if profile_hash(sub_core) != profile_hash(ref_core):
            reasons.append("analysisProfileHash mismatch (core parameters differ)")
        else:
            reasons.append("soft profile fields differ (timeout/memory/ghidraVersion) — still comparable")

    if any("mismatch" in r and "soft" not in r for r in reasons):
        return False, "INCOMPATIBLE", reasons
    if any("legacy" in r.lower() or "soft" in r for r in reasons) or not ref_hash:
        if not ref_hash:
            reasons.append("reference lacks analysisProfileHash — legacy partial")
        return True, "LEGACY_PARTIAL", reasons
    return True, "COMPATIBLE", reasons or ["profiles match"]


def summarize_profile_for_poll(profile: dict[str, Any] | None) -> dict[str, Any] | None:
    if not profile:
        return None
    return {
        "analysisProfileVersion": profile.get("analysisProfileVersion"),
        "analysisProfileHash": profile.get("analysisProfileHash"),
        "analyzerCompat": profile.get("analyzerCompat"),
        "ghidraVersion": profile.get("ghidraVersion"),
        "processorArchitecture": profile.get("processorArchitecture"),
        "requestedLoaderBase": profile.get("requestedLoaderBase"),
        "enabledPreScripts": profile.get("enabledPreScripts"),
        "maximumFunctions": profile.get("maximumFunctions"),
        "fingerprintVersion": profile.get("fingerprintVersion"),
        "callGraphSchemaVersion": profile.get("callGraphSchemaVersion"),
        "seedCortexMEntryPoints": (profile.get("autoAnalysisOptions") or {}).get(
            "seedCortexMEntryPoints"
        ),
    }
