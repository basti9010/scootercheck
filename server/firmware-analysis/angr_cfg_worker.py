#!/usr/bin/env python3
"""Isolated angr CFGFast worker — invoke via subprocess only.

Hard limits (set by parent or env):
  ANGR_MEM_MB       address-space cap (default 1800)
  ANGR_TIMEOUT_SEC  soft hint only; parent kills the process
Never runs symbolic execution — CFGFast only.
"""
from __future__ import annotations

import json
import os
import resource
import sys
from pathlib import Path


def _apply_limits() -> None:
    mem_mb = int(os.environ.get("ANGR_MEM_MB", "1800") or "1800")
    # Cap virtual address space so the OOM killer is less likely to take uvicorn with us.
    bytes_cap = max(512, mem_mb) * 1024 * 1024
    try:
        resource.setrlimit(resource.RLIMIT_AS, (bytes_cap, bytes_cap))
    except (ValueError, OSError):
        pass
    try:
        # One CPU-ish niceness bump if possible
        os.nice(5)
    except OSError:
        pass


def main() -> int:
    if len(sys.argv) < 3:
        print(json.dumps({"ok": False, "error": "usage: angr_cfg_worker.py <bin> <out.json>"}))
        return 2
    bin_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    base = int(os.environ.get("GHIDRA_BASE_ADDR", "0x08000000"), 0)
    max_packed = int(os.environ.get("ANGR_MAX_PACKED", "8") or "8")

    _apply_limits()

    try:
        import angr
    except Exception as e:
        out_path.write_text(json.dumps({"ok": False, "error": f"import:{e}"}), encoding="utf-8")
        return 1

    data = bin_path.read_bytes()
    # Known packed speeds (keep in sync with speed_extract.KNOWN)
    known = {
        0x1400: (20.0, "legalCap"),
        0x1600: (22.0, "legalCap"),
        0x1700: (23.0, "regionOrMode"),
        0x1900: (25.0, "regionOrMode"),
        0x1E00: (30.0, "intermediate"),
        0x2000: (32.0, "intermediate"),
        0x2300: (35.0, "openCap"),
        0x2319: (35.0, "openCap"),
        0x2800: (40.0, "openCap"),
        0x2D00: (45.0, "openCap"),
        0x3200: (50.0, "openCap"),
        0x6300: (99.0, "openCap"),
    }
    packed_offsets: dict[int, list[int]] = {}
    for i in range(0, len(data) - 1):
        packed = data[i] | (data[i + 1] << 8)
        if packed in known:
            packed_offsets.setdefault(packed, []).append(i)

    try:
        # Keep angr quiet and single-threaded-ish
        os.environ.setdefault("OMP_NUM_THREADS", "1")
        os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
        os.environ.setdefault("MKL_NUM_THREADS", "1")

        proj = angr.Project(
            str(bin_path),
            main_opts={
                "backend": "blob",
                "arch": "ARMEL",
                "base_addr": base,
                "entry_point": base,
            },
            auto_load_libs=False,
        )
        cfg = proj.analyses.CFGFast(
            data_references=False,
            normalize=True,
            force_complete_scan=False,
            show_progressbar=False,
        )
    except MemoryError as e:
        out_path.write_text(json.dumps({"ok": False, "error": f"MemoryError:{e}"}), encoding="utf-8")
        return 1
    except Exception as e:
        out_path.write_text(json.dumps({"ok": False, "error": f"{type(e).__name__}:{e}"}), encoding="utf-8")
        return 1

    hints = []
    for packed, offsets in list(packed_offsets.items())[:max_packed]:
        kmh, role = known[packed]
        for off in offsets[:1]:
            addr = base + off
            node = cfg.model.get_any_node(addr, anyaddr=True)
            preds: list[str] = []
            fn_name = None
            if node is not None:
                for pred in cfg.model.get_predecessors(node)[:6]:
                    preds.append(f"{pred.addr:#x}")
                if node.function_address is not None:
                    fn = cfg.functions.get(node.function_address)
                    if fn is not None:
                        fn_name = fn.name
            hints.append(
                {
                    "packed": packed,
                    "kmh": kmh,
                    "role": role,
                    "offset": off,
                    "addr": f"{addr:#x}",
                    "predecessors": preds,
                    "function": fn_name,
                    "engine": "angr-CFGFast",
                }
            )

    payload = {
        "ok": True,
        "hints": hints,
        "nodes": getattr(cfg.model, "graph", None).number_of_nodes() if hasattr(cfg, "model") else None,
        "binBytes": len(data),
    }
    out_path.write_text(json.dumps(payload), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
