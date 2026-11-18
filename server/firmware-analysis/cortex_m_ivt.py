"""Parse Cortex-M vector table (IVT) from a bare flash image.

Used to pick a real Reset handler for Unicorn / angr instead of guessing
from packed immediates alone. Heuristic — many Ninebot VCU images are
Thumb Cortex-M with SP in SRAM and Reset in flash.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

BASE = int(os.environ.get("GHIDRA_BASE_ADDR", "0x08000000"), 0)

# Common STM32 / GD32 SRAM windows seen on scooter VCUs
_SRAM_RANGES = (
    (0x20000000, 0x20100000),
    (0x10000000, 0x10080000),  # CCM / alternate
)
_FLASH_RANGES = (
    (0x08000000, 0x08200000),
    (0x00000000, 0x00200000),  # aliased / remapped
)

_VECTOR_NAMES = (
    "initialSP",
    "reset",
    "nmi",
    "hardFault",
    "memManage",
    "busFault",
    "usageFault",
    "reserved7",
    "reserved8",
    "reserved9",
    "reserved10",
    "svCall",
    "debugMonitor",
    "reserved13",
    "pendSV",
    "sysTick",
)


def parse_ivt(data: bytes, *, base: int | None = None, max_vectors: int = 48) -> dict[str, Any]:
    """Return IVT summary. `ok` True when SP+Reset look like Cortex-M."""
    flash_base = BASE if base is None else base
    if len(data) < 8:
        return {
            "ok": False,
            "likely": False,
            "notes": ["ivt=too_small"],
            "vectors": [],
        }

    vectors: list[dict[str, Any]] = []
    n = min(max_vectors, len(data) // 4)
    for i in range(n):
        off = i * 4
        val = int.from_bytes(data[off : off + 4], "little")
        name = _VECTOR_NAMES[i] if i < len(_VECTOR_NAMES) else f"irq{i - 16}" if i >= 16 else f"vec{i}"
        entry: dict[str, Any] = {
            "index": i,
            "name": name,
            "offset": off,
            "value": f"{val:#010x}",
            "valueInt": val,
        }
        if i == 0:
            entry["role"] = "sp"
            entry["inSram"] = _in_ranges(val, _SRAM_RANGES)
        elif i == 1:
            thumb = (val & 1) == 1
            dest = val & ~1
            entry["role"] = "reset"
            entry["thumb"] = thumb
            entry["handler"] = f"{dest:#010x}"
            entry["handlerInt"] = dest
            entry["inFlash"] = _in_ranges(dest, _FLASH_RANGES) or (
                flash_base <= dest < flash_base + max(len(data), 1)
            )
            # File offset relative to mapped flash base
            if flash_base <= dest < flash_base + len(data):
                entry["fileOffset"] = dest - flash_base
            elif dest < len(data):
                entry["fileOffset"] = dest
        vectors.append(entry)

    sp = vectors[0]
    reset = vectors[1] if len(vectors) > 1 else {}
    likely = bool(sp.get("inSram")) and bool(reset.get("thumb")) and bool(reset.get("inFlash"))

    notes = [
        f"ivt={'ok' if likely else 'unlikely'} sp={sp.get('value')} reset={reset.get('handler', reset.get('value'))}"
    ]
    if likely:
        notes.append(
            f"Cortex-M IVT: Reset @{reset.get('handler')} "
            f"(fileOff={reset.get('fileOffset')}, thumb={reset.get('thumb')})"
        )

    return {
        "ok": True,
        "likely": likely,
        "flashBase": f"{flash_base:#010x}",
        "initialSP": sp.get("value"),
        "initialSPInt": sp.get("valueInt"),
        "resetHandler": reset.get("handler"),
        "resetHandlerInt": reset.get("handlerInt"),
        "resetFileOffset": reset.get("fileOffset"),
        "resetThumb": reset.get("thumb"),
        "vectors": vectors[:16],
        "notes": notes,
    }


def analyze_firmware(bin_path: Path) -> dict[str, Any]:
    data = bin_path.read_bytes()
    return parse_ivt(data)


def merge_ivt_into_result(result: dict[str, Any], ivt: dict[str, Any]) -> dict[str, Any]:
    notes = list(result.get("notes") or [])
    notes.extend(ivt.get("notes") or [])
    result["notes"] = notes
    if not ivt.get("ok"):
        return result
    result["cortexMIvt"] = {
        "likely": bool(ivt.get("likely")),
        "flashBase": ivt.get("flashBase"),
        "initialSP": ivt.get("initialSP"),
        "resetHandler": ivt.get("resetHandler"),
        "resetFileOffset": ivt.get("resetFileOffset"),
        "resetThumb": ivt.get("resetThumb"),
        "vectors": ivt.get("vectors") or [],
    }
    if ivt.get("likely"):
        # Do not append a new sources[] enum value — older app builds fail JSON
        # decode on unknown FirmwareDeepAnalysisSource cases. cortexMIvt field is enough.
        quality = dict(result.get("quality") or {})
        quality["summary"] = ((quality.get("summary") or "").rstrip() + " + IVT.").strip()
        result["quality"] = quality
    return result


def _in_ranges(addr: int, ranges: tuple[tuple[int, int], ...]) -> bool:
    return any(lo <= addr < hi for lo, hi in ranges)
