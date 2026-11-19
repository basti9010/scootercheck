"""Run Ghidra analyzeHeadless on a plaintext firmware BIN and export decompiled C."""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from analysis_profile import build_analysis_profile, summarize_profile_for_poll


def ghidra_configured() -> bool:
    return bool(_headless_bin())


def _headless_bin() -> str | None:
    direct = os.environ.get("GHIDRA_HEADLESS", "").strip()
    if direct and Path(direct).exists():
        return direct
    home = os.environ.get("GHIDRA_HOME", "").strip()
    if home:
        home_path = Path(home)
        cand = home_path / "support" / "analyzeHeadless"
        if cand.exists():
            return str(cand)
        # Allow GHIDRA_HOME=/opt/ghidra when install lives in ghidra_*_PUBLIC/
        if home_path.is_dir():
            for child in sorted(home_path.glob("ghidra_*")):
                nested = child / "support" / "analyzeHeadless"
                if nested.exists():
                    return str(nested)
    which = shutil.which("analyzeHeadless")
    if which:
        return which
    # Common Hetzner layout
    for nested in sorted(Path("/opt/ghidra").glob("ghidra_*/support/analyzeHeadless")):
        if nested.exists():
            return str(nested)
    return None


def run_ghidra_decompile(
    plaintext_bin: Path,
    output_c: Path,
    *,
    processor: str = "ARM:LE:32:Cortex",
    base_addr: str = "0x08000000",
    timeout_sec: int = 600,
    speed_json: Path | None = None,
    limit_c: Path | None = None,
    functions_json: Path | None = None,
    callgraph_json: Path | None = None,
    seed_ivt_entry_points: bool | None = None,
    auto_identify: bool | None = None,
) -> tuple[bool, str]:
    headless = _headless_bin()
    if not headless:
        return False, "Ghidra not configured (set GHIDRA_HOME or GHIDRA_HEADLESS)"

    script_dir = Path(__file__).resolve().parent / "ghidra_scripts"
    if not (script_dir / "ExportAllDecompiled.java").exists():
        return False, f"missing ExportAllDecompiled.java in {script_dir}"

    identify_notes: list[str] = []
    do_identify = auto_identify if auto_identify is not None else (
        os.environ.get("GHIDRA_AUTO_IDENTIFY", "1").strip() not in ("0", "false", "False")
    )
    if do_identify:
        try:
            from firmware_identify import identify_firmware_image

            ident = identify_firmware_image(plaintext_bin)
            identify_notes.extend(ident.get("notes") or [])
            if ident.get("ok") and ident.get("baseAddr"):
                base_addr = str(ident["baseAddr"])
            if ident.get("ok") and ident.get("processor"):
                processor = str(ident["processor"])
            if ident.get("architectureUnknown"):
                identify_notes.append("architecture=uncertain")
        except Exception as e:
            identify_notes.append(f"identify=error:{type(e).__name__}")

    do_seed = seed_ivt_entry_points if seed_ivt_entry_points is not None else (
        os.environ.get("GHIDRA_SEED_IVT", "1").strip() not in ("0", "false", "False")
    )

    profile = build_analysis_profile(
        processor=processor,
        loader_base=base_addr,
        seed_ivt=do_seed,
        timeout_sec=timeout_sec,
    )
    # Keep profile in sync if identify changed processor/base
    profile["processorArchitecture"] = processor
    profile["requestedLoaderBase"] = base_addr
    profile["autoAnalysisOptions"] = {
        **(profile.get("autoAnalysisOptions") or {}),
        "seedCortexMEntryPoints": do_seed,
    }
    profile["enabledPreScripts"] = ["SeedCortexMEntryPoints.java"] if do_seed else []
    from analysis_profile import profile_hash as _ph

    profile["analysisProfileHash"] = _ph(profile)

    output_c.parent.mkdir(parents=True, exist_ok=True)
    if speed_json is None:
        speed_json = output_c.with_suffix(".speeds.json")
    speed_json.parent.mkdir(parents=True, exist_ok=True)
    if limit_c is None:
        limit_c = output_c.with_suffix(".limits.c")
    limit_c.parent.mkdir(parents=True, exist_ok=True)
    if functions_json is None:
        functions_json = output_c.with_suffix(".functions.json")
    functions_json.parent.mkdir(parents=True, exist_ok=True)
    if callgraph_json is None:
        callgraph_json = output_c.with_suffix(".callgraph.json")
    callgraph_json.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="ghidra-proj-") as proj:
        proj_dir = Path(proj)
        # analyzeHeadless <project_location> <project_name> [options]
        cmd = [
            headless,
            str(proj_dir),
            "ScooterCheckFW",
            "-import",
            str(plaintext_bin),
            "-processor",
            processor,
            "-cspec",
            "default",
            "-loader",
            "BinaryLoader",
            "-loader-baseAddr",
            base_addr,
            "-scriptPath",
            str(script_dir),
        ]
        if do_seed and (script_dir / "SeedCortexMEntryPoints.java").exists():
            cmd.extend(["-preScript", "SeedCortexMEntryPoints.java"])
            identify_notes.append("seedIvt=1")
        cmd.extend(
            [
                "-postScript",
                "ExportAllDecompiled.java",
                str(output_c),
                "-postScript",
                "ExportSpeedXrefs.java",
                str(speed_json),
                "-postScript",
                "ExportLimitFunctions.java",
                str(limit_c),
                "-postScript",
                "ExportFunctionAnalysis.java",
                str(functions_json),
                "-postScript",
                "ExportCallGraph.java",
                str(callgraph_json),
                "-deleteProject",
            ]
        )
        # Extra headless timeout buffer for Phase-2 exports (still capped by caller).
        timeout_sec = max(timeout_sec, int(os.environ.get("GHIDRA_TIMEOUT_SEC", str(timeout_sec)) or timeout_sec))
        env = os.environ.copy()
        env["GHIDRA_BASE_ADDR"] = str(base_addr)
        env["SCOOTERCHECK_LOADER_BASE"] = str(base_addr)
        env["GHIDRA_MAX_FUNCTIONS"] = str(profile.get("maximumFunctions") or 2500)
        if profile.get("memoryLimit"):
            env.setdefault("_JAVA_OPTIONS", f"-Xmx{profile['memoryLimit']}")
        # Persist profile next to exports for reproducibility audits
        try:
            import json as _json

            profile_path = functions_json.with_suffix(".analysis_profile.json")
            profile_path.write_text(
                _json.dumps(profile, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
            )
        except Exception:
            profile_path = None
        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout_sec,
                check=False,
                env=env,
            )
        except subprocess.TimeoutExpired:
            return False, "ghidra timed out"
        except OSError as e:
            return False, f"ghidra spawn failed: {e}"

        log_tail = ((proc.stderr or "") + "\n" + (proc.stdout or ""))[-2000:]
        if proc.returncode != 0:
            return False, f"ghidra exit {proc.returncode}: {log_tail}"
        if not output_c.exists() or output_c.stat().st_size == 0:
            return False, f"ghidra produced empty decompile: {log_tail}"
        notes = [
            f"decompiled {output_c.stat().st_size} bytes",
            f"processor={processor}",
            f"base={base_addr}",
            f"analysisProfileHash={profile.get('analysisProfileHash', '')[:16]}",
            f"seedIvt={1 if do_seed else 0}",
        ]
        notes.extend(identify_notes)
        if speed_json.exists() and speed_json.stat().st_size > 0:
            notes.append(f"speedXrefs {speed_json.stat().st_size}B")
        if limit_c.exists() and limit_c.stat().st_size > 0:
            notes.append(f"limits.c {limit_c.stat().st_size}B")
        # Phase-2 exports are best-effort: missing files must not fail the whole decompile.
        if functions_json.exists() and functions_json.stat().st_size > 0:
            notes.append(f"functions.json {functions_json.stat().st_size}B")
            # Embed profile into functions export if possible (non-fatal)
            try:
                import json as _json

                fa = _json.loads(functions_json.read_text(encoding="utf-8"))
                if isinstance(fa, dict):
                    fa["analysisProfile"] = summarize_profile_for_poll(profile)
                    fa["requestedLoaderBase"] = fa.get("requestedLoaderBase") or base_addr
                    functions_json.write_text(
                        _json.dumps(fa, ensure_ascii=False) + "\n", encoding="utf-8"
                    )
            except Exception:
                pass
        else:
            notes.append("functions.json=missing-or-empty")
        if callgraph_json.exists() and callgraph_json.stat().st_size > 0:
            notes.append(f"callgraph.json {callgraph_json.stat().st_size}B")
        else:
            notes.append("callgraph.json=missing-or-empty")
        if profile_path is not None:
            notes.append(f"analysisProfile={profile_path.name}")
        return True, ", ".join(notes)


def load_speed_xrefs(speed_json: Path) -> dict[str, Any]:
    """Parse ExportSpeedXrefs JSON into deep-analysis speed findings."""
    import json

    from speed_extract import KNOWN_MAP

    if not speed_json.is_file():
        return {"ok": False, "speeds": [], "notes": ["ghidraXrefs=missing"]}
    try:
        data = json.loads(speed_json.read_text(encoding="utf-8"))
    except Exception as e:
        return {"ok": False, "speeds": [], "notes": [f"ghidraXrefs=badjson:{e}"]}

    packed = data.get("packed") or {}
    speeds: list[dict[str, Any]] = []
    for key, hits in packed.items():
        try:
            val = int(str(key).replace("0x", "").replace("0X", ""), 16)
        except ValueError:
            continue
        if val not in KNOWN_MAP:
            continue
        kmh, role = KNOWN_MAP[val]
        hit0 = hits[0] if isinstance(hits, list) and hits else {}
        addr = hit0.get("addr") if isinstance(hit0, dict) else None
        fn = hit0.get("fn") if isinstance(hit0, dict) else None
        evidence = f"Ghidra xref 0x{val:04X}"
        if fn:
            evidence += f" in {fn}"
        if addr:
            evidence += f" @ {addr}"
        if isinstance(hits, list) and len(hits) > 1:
            evidence += f" (+{len(hits) - 1} more)"
        speeds.append(
            {
                "id": f"ghidra-xref-{val:04x}",
                "kmh": kmh,
                "packedU16": val,
                "role": role,
                "evidence": evidence,
                "source": "serverDecompile",
                "confidence": "high",
            }
        )
    return {
        "ok": True,
        "speeds": sorted(speeds, key=lambda x: x["kmh"]),
        "notes": [f"ghidraXrefs=ok packed={len(speeds)} hits={data.get('hits')}"],
    }
