#!/usr/bin/env python3
"""Isolated angr CFG worker — invoke via subprocess only.

Hard limits (set by parent or env):
  ANGR_MEM_MB       address-space cap (default 1800)
  ANGR_TIMEOUT_SEC  soft hint only; parent kills the process
  ANGR_CFG_DEPTH    predecessor BFS depth (default 6)
  ANGR_MAX_PACKED   distinct packed immediates (default 12)
  ANGR_SYMBOLIC     0/1 limited local exploration near speed sites (default 0)

Default stays CFG-based (no full-binary symbolic execution). Optional
ANGR_SYMBOLIC=1 runs a short ExplorationTechnique per speed site only.
"""
from __future__ import annotations

import json
import os
import resource
import sys
from collections import deque
from pathlib import Path
from typing import Any


def _apply_limits() -> None:
    mem_mb = int(os.environ.get("ANGR_MEM_MB", "1800") or "1800")
    bytes_cap = max(512, mem_mb) * 1024 * 1024
    try:
        resource.setrlimit(resource.RLIMIT_AS, (bytes_cap, bytes_cap))
    except (ValueError, OSError):
        pass
    try:
        os.nice(5)
    except OSError:
        pass


def _bfs_preds(cfg: Any, start: Any, depth: int, limit: int = 24) -> list[dict[str, Any]]:
    """Multi-hop CFG predecessors with hop distance."""
    if start is None or depth <= 0:
        return []
    out: list[dict[str, Any]] = []
    seen: set[int] = {getattr(start, "addr", -1)}
    q: deque[tuple[Any, int]] = deque([(start, 0)])
    while q and len(out) < limit:
        node, hop = q.popleft()
        if hop >= depth:
            continue
        try:
            preds = list(cfg.model.get_predecessors(node))
        except Exception:
            preds = []
        for pred in preds:
            addr = int(getattr(pred, "addr", 0) or 0)
            if addr in seen:
                continue
            seen.add(addr)
            fn_name = None
            try:
                if pred.function_address is not None:
                    fn = cfg.functions.get(pred.function_address)
                    if fn is not None:
                        fn_name = fn.name
            except Exception:
                pass
            out.append(
                {
                    "addr": f"{addr:#x}",
                    "hop": hop + 1,
                    "function": fn_name,
                }
            )
            q.append((pred, hop + 1))
    return out


def _callers(cfg: Any, fn_addr: int | None, limit: int = 8) -> list[str]:
    if fn_addr is None:
        return []
    try:
        fn = cfg.functions.get(fn_addr)
        if fn is None:
            return []
        cg = cfg.functions.callgraph
        preds = list(cg.predecessors(fn_addr)) if cg is not None else []
    except Exception:
        return []
    names: list[str] = []
    for p in preds[:limit]:
        try:
            caller = cfg.functions.get(p)
            names.append(caller.name if caller is not None else f"{int(p):#x}")
        except Exception:
            names.append(f"{int(p):#x}")
    return names


def _block_snippet(proj: Any, addr: int, max_insns: int = 8) -> list[str]:
    try:
        block = proj.factory.block(addr)
        lines: list[str] = []
        for insn in list(block.capstone.insns)[:max_insns]:
            lines.append(f"{insn.address:#x}: {insn.mnemonic} {insn.op_str}")
        return lines
    except Exception:
        return []


def _xrefs_to(cfg: Any, addr: int, limit: int = 8) -> list[str]:
    try:
        xrefs = cfg.kb.xrefs.get_xrefs_by_dst(addr)  # type: ignore[attr-defined]
    except Exception:
        try:
            xrefs = list(getattr(cfg.kb.xrefs, "xrefs", {}) or ())
            xrefs = [x for x in xrefs if getattr(x, "dst", None) == addr]
        except Exception:
            return []
    out: list[str] = []
    for xr in list(xrefs)[:limit]:
        try:
            src = getattr(xr, "ins_addr", None) or getattr(xr, "from_addr", None) or getattr(xr, "src", None)
            if src is not None:
                out.append(f"{int(src):#x}")
        except Exception:
            continue
    return out


def _limited_symbolic(proj: Any, fn_addr: int, target: int, max_steps: int = 64) -> dict[str, Any]:
    """Short local exploration from function entry toward the speed immediate."""
    try:
        import angr

        state = proj.factory.blank_state(
            addr=fn_addr,
            add_options={angr.options.ZERO_FILL_UNCONSTRAINED_MEMORY},
        )
        simgr = proj.factory.simulation_manager(state)
        # Explore briefly; avoid unbounded branching.
        simgr.explore(find=target, num_find=1, n=max_steps)
        return {
            "ok": True,
            "found": len(getattr(simgr, "found", []) or []),
            "active": len(getattr(simgr, "active", []) or []),
            "deadended": len(getattr(simgr, "deadended", []) or []),
            "steps": max_steps,
            "engine": "angr-explore-local",
        }
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}:{e}"}


def main() -> int:
    if len(sys.argv) < 3:
        print(json.dumps({"ok": False, "error": "usage: angr_cfg_worker.py <bin> <out.json>"}))
        return 2
    bin_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    base = int(os.environ.get("GHIDRA_BASE_ADDR", "0x08000000"), 0)
    max_packed = int(os.environ.get("ANGR_MAX_PACKED", "12") or "12")
    cfg_depth = int(os.environ.get("ANGR_CFG_DEPTH", "6") or "6")
    do_symbolic = os.environ.get("ANGR_SYMBOLIC", "0").strip() in ("1", "true", "True", "yes")
    sym_steps = int(os.environ.get("ANGR_SYMBOLIC_STEPS", "64") or "64")

    _apply_limits()

    try:
        import angr
    except Exception as e:
        out_path.write_text(json.dumps({"ok": False, "error": f"import:{e}"}), encoding="utf-8")
        return 1

    data = bin_path.read_bytes()
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
            data_references=True,
            normalize=True,
            force_complete_scan=False,
            resolve_indirect_jumps=True,
            cross_references=True,
            show_progressbar=False,
        )
    except MemoryError as e:
        out_path.write_text(json.dumps({"ok": False, "error": f"MemoryError:{e}"}), encoding="utf-8")
        return 1
    except Exception as e:
        out_path.write_text(json.dumps({"ok": False, "error": f"{type(e).__name__}:{e}"}), encoding="utf-8")
        return 1

    hints: list[dict[str, Any]] = []
    for packed, offsets in list(packed_offsets.items())[:max_packed]:
        kmh, role = known[packed]
        for off in offsets[:2]:
            # Skip tiny head false-positives (e.g. vector table noise at offset < 16)
            if off < 16:
                continue
            addr = base + off
            node = cfg.model.get_any_node(addr, anyaddr=True)
            pred_chain = _bfs_preds(cfg, node, depth=cfg_depth)
            preds = [p["addr"] for p in pred_chain]
            fn_name = None
            fn_addr = None
            if node is not None and node.function_address is not None:
                fn_addr = int(node.function_address)
                fn = cfg.functions.get(fn_addr)
                if fn is not None:
                    fn_name = fn.name
            callers = _callers(cfg, fn_addr)
            xrefs = _xrefs_to(cfg, addr)
            snippet_addr = int(getattr(node, "addr", addr) or addr) if node is not None else addr
            snippet = _block_snippet(proj, snippet_addr)
            hint: dict[str, Any] = {
                "packed": packed,
                "kmh": kmh,
                "role": role,
                "offset": off,
                "addr": f"{addr:#x}",
                "predecessors": preds,
                "predecessorChain": pred_chain,
                "callers": callers,
                "xrefs": xrefs,
                "snippet": snippet,
                "function": fn_name,
                "cfgDepth": cfg_depth,
                "engine": "angr-CFGFast-deep",
            }
            if do_symbolic and fn_addr is not None:
                hint["symbolic"] = _limited_symbolic(proj, fn_addr, addr, max_steps=sym_steps)
            hints.append(hint)

    graph = getattr(cfg.model, "graph", None)
    payload = {
        "ok": True,
        "hints": hints,
        "nodes": graph.number_of_nodes() if graph is not None else None,
        "edges": graph.number_of_edges() if graph is not None else None,
        "functions": len(cfg.functions) if hasattr(cfg, "functions") else None,
        "cfgDepth": cfg_depth,
        "symbolic": do_symbolic,
        "binBytes": len(data),
        "engine": "angr-CFGFast-deep",
    }
    out_path.write_text(json.dumps(payload), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
