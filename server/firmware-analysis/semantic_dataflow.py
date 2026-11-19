"""Phase 2.3.1 — Compact semantic data-flow features from Ghidra exports.

Derives per-function memory / compare / call / conditional signals from an
optional ``*.dataflow.json`` (ExportDataFlowSummary) or, when missing, from
existing function-analysis fields (mnemonics, calls, constants, strings,
basicBlocks, cfgEdges).

Hard rules
----------
* Never reconstruct or emit activation / unlock sequences.
* Document analysis limitations; treat missing Ghidra data as partial/missing.
* Cap work at MAX_FUNCTIONS for timeout-friendly analysis.
* Features are structural code properties — not vehicle-behavior claims.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
PHASE = "2.3.3"

PROVENANCE_GHIDRA_EXPORTED = "GHIDRA_EXPORTED"
PROVENANCE_MNEMONIC_DERIVED = "MNEMONIC_DERIVED"
PROVENANCE_PARTIAL = "PARTIAL"
PROVENANCE_NOT_AVAILABLE = "NOT_AVAILABLE"
MAX_FUNCTIONS = int(os.environ.get("FW_DATAFLOW_MAX_FUNCTIONS", "2500") or "2500")
MAX_POLL_FUNCTIONS = int(os.environ.get("FW_DATAFLOW_POLL_MAX", "40") or "40")
MAX_LIMITATIONS_PER_FN = 6

_COMPARE_MNEMONICS = frozenset({"cmp", "cmn", "tst", "teq"})
_COND_BRANCH_EXACT = frozenset(
    {
        "beq",
        "bne",
        "blt",
        "bgt",
        "ble",
        "bge",
        "bcs",
        "bcc",
        "bmi",
        "bpl",
        "bvs",
        "bvc",
        "bhi",
        "bls",
        "cbz",
        "cbnz",
        "tbz",
        "tbnz",
        "it",
        "ite",
        "itt",
        "itee",
        "itet",
        "itte",
        "itti",
        "ittt",
        "iteee",
        "itett",
        "itete",
        "itteee",
        "ittte",
        "ittet",
        "itttt",
    }
)
_LOAD_PREFIXES = ("ldr", "ldm", "ldrex", "pop")
_STORE_PREFIXES = ("str", "stm", "strex", "push")
_CALL_MNEMONICS = frozenset({"bl", "blx"})

BASE_LIMITATIONS = [
    "Semantic data-flow is a compact structural summary — not full pcode / SSA.",
    "Ohne Ghidra-Dataflow-Export werden Merkmale aus Mnemonics/Calls/Refs abgeleitet (best-effort).",
    "parameterCount ist null wenn die Signatur unbekannt ist — nicht erraten.",
    "Keine Rekonstruktion oder Ausgabe von Aktivierungs-/Umgehungssequenzen.",
    "Memory-Read/Write-Zähler sind Näherungen (RefType und/oder LDR/STR-Mnemonics).",
]


def _norm_mnem(m: str) -> str:
    s = (m or "").strip().lower()
    if not s:
        return ""
    # Strip Thumb width / condition suffixes: "cmp.w", "beq.n", "ldr.w"
    if "." in s:
        s = s.split(".", 1)[0]
    return s


def _mnemonics(fn: dict[str, Any]) -> list[str]:
    raw = fn.get("mnemonics") or []
    if not isinstance(raw, list):
        return []
    out: list[str] = []
    for m in raw:
        if isinstance(m, str):
            n = _norm_mnem(m)
            if n:
                out.append(n)
        elif isinstance(m, dict):
            n = _norm_mnem(str(m.get("mnemonic") or m.get("op") or ""))
            if n:
                out.append(n)
    return out


def _is_load(m: str) -> bool:
    return any(m == p or m.startswith(p) for p in _LOAD_PREFIXES)


def _is_store(m: str) -> bool:
    return any(m == p or m.startswith(p) for p in _STORE_PREFIXES)


def _is_cond_branch(m: str) -> bool:
    if m in _COND_BRANCH_EXACT:
        return True
    # Conditional B<cc> but not plain b / bx / bl / blx
    if m.startswith("b") and m not in {"b", "bx", "bl", "blx", "bfc", "bfi", "bic", "bkpt"}:
        if len(m) >= 3 and m[1:3] not in {"l", "x"}:  # not bl*, bx*
            return True
    return False


def _int_or_none(v: Any) -> int | None:
    if v is None:
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def _int_or_zero(v: Any) -> int:
    n = _int_or_none(v)
    return 0 if n is None else max(0, n)


def _fns(export: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not isinstance(export, dict):
        return []
    raw = export.get("functions")
    if not isinstance(raw, list):
        return []
    return [f for f in raw if isinstance(f, dict)]


def _addr(f: dict[str, Any]) -> str:
    return str(f.get("address") or f.get("entry") or f.get("entryPoint") or "").strip()


def _name(f: dict[str, Any]) -> str:
    return str(f.get("name") or "").strip()


def _index_by_addr(functions: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for f in functions:
        a = _addr(f)
        if a:
            out[a.lower().replace("0x", "")] = f
            out[a.lower()] = f
    return out


def _call_counts_from_graph(call_graph: dict[str, Any] | None) -> dict[str, int]:
    """Map caller address → outbound call edge count (best-effort)."""
    if not isinstance(call_graph, dict):
        return {}
    edges = call_graph.get("edges") or []
    if not isinstance(edges, list):
        return {}
    counts: dict[str, int] = {}
    for e in edges:
        if not isinstance(e, dict):
            continue
        cls = str(e.get("classification") or "").upper()
        kind = str(e.get("kind") or "").lower()
        evidence = str(e.get("evidence") or "").lower()
        is_call = (
            cls in {"DIRECT_CALL", "INDIRECT_CALL", "TAIL_CALL", "UNRESOLVED_CALL"}
            or kind in {"direct", "indirect", "call", "tail"}
            or evidence in {"static", "heuristic"}
        )
        if not is_call:
            continue
        if cls == "INTERNAL_BRANCH" or evidence == "internal" or kind == "internal":
            continue
        frm = str(e.get("from") or e.get("fromAddress") or "").strip().lower()
        if not frm:
            continue
        key = frm.replace("0x", "")
        counts[key] = counts.get(key, 0) + 1
        counts[frm] = counts.get(frm, 0) + 1
    return counts


def load_dataflow_export(path: Path | str | None) -> dict[str, Any]:
    """Load optional ExportDataFlowSummary JSON (``*.dataflow.json``)."""
    if path is None:
        return {
            "ok": False,
            "schemaVersion": SCHEMA_VERSION,
            "functions": [],
            "functionCount": 0,
            "notes": ["dataflowExport=missing"],
            "analysisLimitations": ["Kein Ghidra-Dataflow-Export vorhanden."],
        }
    p = Path(path)
    if not p.is_file():
        return {
            "ok": False,
            "schemaVersion": SCHEMA_VERSION,
            "functions": [],
            "functionCount": 0,
            "notes": ["dataflowExport=missing"],
            "analysisLimitations": ["Kein Ghidra-Dataflow-Export vorhanden."],
        }
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:
        return {
            "ok": False,
            "schemaVersion": SCHEMA_VERSION,
            "functions": [],
            "functionCount": 0,
            "notes": [f"dataflowExport=badjson:{e}"],
            "analysisLimitations": ["Dataflow-Export JSON ungültig."],
        }
    if not isinstance(data, dict):
        return {
            "ok": False,
            "schemaVersion": SCHEMA_VERSION,
            "functions": [],
            "functionCount": 0,
            "notes": ["dataflowExport=not-object"],
            "analysisLimitations": ["Unerwartetes Dataflow-Exportformat."],
        }
    fns = data.get("functions") or []
    if not isinstance(fns, list):
        fns = []
    limitations = list(data.get("analysisLimitations") or [])
    if data.get("truncated"):
        limitations.append(
            f"Dataflow-Export gekürzt (maxFunctions={data.get('maxFunctions')}, "
            f"skipped={data.get('truncatedSkipped')})."
        )
    return {
        "ok": True,
        "schemaVersion": int(data.get("schemaVersion") or SCHEMA_VERSION),
        "tool": data.get("tool"),
        "processor": data.get("processor"),
        "functions": [f for f in fns if isinstance(f, dict)],
        "functionCount": int(data.get("functionCount") or len(fns)),
        "truncated": bool(data.get("truncated")),
        "notes": [f"dataflowExport=ok count={len(fns)}"],
        "analysisLimitations": limitations,
        "raw": data,
    }


def _provenance_from_state(
    *,
    source: str,
    quality: str,
    has_export_row: bool,
    has_mnemonics: bool,
) -> str:
    if has_export_row and source == "dataflow_export" and quality == "ok":
        return PROVENANCE_GHIDRA_EXPORTED
    if quality == "missing" and not has_mnemonics and not has_export_row:
        return PROVENANCE_NOT_AVAILABLE
    if has_mnemonics or source in ("derived", "function_export"):
        return PROVENANCE_PARTIAL if quality in ("partial", "missing") else PROVENANCE_MNEMONIC_DERIVED
    if has_export_row:
        return PROVENANCE_PARTIAL
    return PROVENANCE_NOT_AVAILABLE


def _derive_from_function(
    fn: dict[str, Any],
    *,
    df: dict[str, Any] | None,
    graph_calls: int | None,
) -> dict[str, Any]:
    """Build one compact semantic data-flow record for a function."""
    limitations: list[str] = []
    source = "derived"
    mnems = _mnemonics(fn)
    has_export_row = False

    # Prefer explicit dataflow export fields when present.
    param = None
    memory_reads = None
    memory_writes = None
    compare_ops = None
    cond_branches = None
    call_count = None
    data_refs = None

    if isinstance(df, dict):
        has_export_row = True
        source = "dataflow_export"
        param = _int_or_none(df.get("parameterCount"))
        memory_reads = _int_or_none(df.get("memoryReads"))
        memory_writes = _int_or_none(df.get("memoryWrites"))
        compare_ops = _int_or_none(df.get("compareOps"))
        cond_branches = _int_or_none(df.get("conditionalBranches"))
        call_count = _int_or_none(df.get("callCount"))
        data_refs = _int_or_none(df.get("dataReferenceCount"))
        for lim in df.get("limitations") or []:
            if isinstance(lim, str) and lim and lim not in limitations:
                limitations.append(lim)
        q_df = str(df.get("quality") or "").lower()
        if q_df in {"partial", "missing"}:
            limitations.append(f"dataflow quality={q_df}")

    # Optional compact fields already on function export (Phase 2.3.1 extension).
    if param is None:
        param = _int_or_none(fn.get("parameterCount"))
    if memory_reads is None and fn.get("memoryReadCount") is not None:
        memory_reads = _int_or_zero(fn.get("memoryReadCount"))
        if source == "derived":
            source = "function_export"
    if memory_writes is None and fn.get("memoryWriteCount") is not None:
        memory_writes = _int_or_zero(fn.get("memoryWriteCount"))
        if source == "derived":
            source = "function_export"
    if compare_ops is None and fn.get("compareOpCount") is not None:
        compare_ops = _int_or_zero(fn.get("compareOpCount"))
    if data_refs is None and fn.get("dataReferenceCount") is not None:
        data_refs = _int_or_zero(fn.get("dataReferenceCount"))

    # Derive remaining from mnemonics / calls / constants / strings / CFG.
    if compare_ops is None:
        if mnems:
            compare_ops = sum(1 for m in mnems if m in _COMPARE_MNEMONICS)
        else:
            compare_ops = 0
            limitations.append("compareOps=0 (keine Mnemonics)")

    if cond_branches is None:
        if mnems:
            cond_branches = sum(1 for m in mnems if _is_cond_branch(m))
        else:
            # Fall back to branchMnemonicCount / CFG shape (weaker).
            bmc = _int_or_none(fn.get("branchMnemonicCount"))
            if bmc is not None:
                cond_branches = bmc
                limitations.append("conditionalBranches≈branchMnemonicCount (inkl. unbedingte)")
            else:
                bb = _int_or_zero(fn.get("basicBlocks"))
                edges = _int_or_zero(fn.get("cfgEdges"))
                cond_branches = max(0, edges - max(bb, 1) + 1) if (bb or edges) else 0
                if bb or edges:
                    limitations.append("conditionalBranches aus CFG-Näherung")

    if memory_reads is None:
        if mnems:
            memory_reads = sum(1 for m in mnems if _is_load(m))
        else:
            memory_reads = 0
            limitations.append("memoryReads unbekannt (keine Mnemonics/Refs)")

    if memory_writes is None:
        if mnems:
            memory_writes = sum(1 for m in mnems if _is_store(m))
        else:
            memory_writes = 0
            limitations.append("memoryWrites unbekannt (keine Mnemonics/Refs)")

    calls = fn.get("calls") if isinstance(fn.get("calls"), list) else []
    if call_count is None:
        if calls:
            call_count = len(calls)
        elif mnems:
            call_count = sum(1 for m in mnems if m in _CALL_MNEMONICS)
        elif graph_calls is not None:
            call_count = graph_calls
            limitations.append("callCount aus Callgraph")
        else:
            call_count = 0

    if data_refs is None:
        constants = fn.get("constants") if isinstance(fn.get("constants"), list) else []
        strings = fn.get("strings") if isinstance(fn.get("strings"), list) else []
        if constants or strings:
            data_refs = len(constants) + len(strings)
            limitations.append("dataReferenceCount≈constants+strings")
        else:
            data_refs = int(memory_reads or 0) + int(memory_writes or 0)

    # Quality
    has_body = _int_or_zero(fn.get("basicBlocks")) > 0 or _int_or_zero(fn.get("size")) > 0
    has_mnem = bool(mnems)
    if source == "dataflow_export" and has_body:
        quality = "ok"
    elif has_mnem and has_body:
        quality = "ok" if source != "derived" or (compare_ops or memory_reads or call_count) else "partial"
        if source == "derived":
            quality = "partial"
            limitations.append("abgeleitet ohne Dataflow-Export")
    elif has_body or calls or _int_or_zero(fn.get("cfgEdges")) > 0:
        quality = "partial"
        limitations.append("teilweise Merkmale (begrenzte Instruktionsdaten)")
    else:
        quality = "missing"
        limitations.append("keine verwertbaren Dataflow-Merkmale")

    if isinstance(df, dict) and str(df.get("quality") or "").lower() == "missing":
        quality = "missing"
    elif isinstance(df, dict) and str(df.get("quality") or "").lower() == "partial" and quality == "ok":
        quality = "partial"

    features: dict[str, bool] = {}
    if param is not None:
        features["usesParameters"] = param > 0
    elif mnems:
        # Unknown signature — omit usesParameters rather than invent.
        pass
    features["readsMemory"] = int(memory_reads or 0) > 0
    features["writesMemory"] = int(memory_writes or 0) > 0
    features["feedsConditionals"] = int(compare_ops or 0) > 0 and int(cond_branches or 0) > 0
    features["interproceduralCalls"] = int(call_count or 0) > 0

    if len(limitations) > MAX_LIMITATIONS_PER_FN:
        limitations = limitations[:MAX_LIMITATIONS_PER_FN]

    provenance = _provenance_from_state(
        source=source,
        quality=quality,
        has_export_row=has_export_row,
        has_mnemonics=bool(mnems),
    )

    return {
        "address": _addr(fn) or ( _addr(df) if isinstance(df, dict) else ""),
        "name": _name(fn) or (_name(df) if isinstance(df, dict) else ""),
        "parameterCount": param,
        "memoryReads": int(memory_reads or 0),
        "memoryWrites": int(memory_writes or 0),
        "compareOps": int(compare_ops or 0),
        "conditionalBranches": int(cond_branches or 0),
        "callCount": int(call_count or 0),
        "dataReferenceCount": int(data_refs or 0),
        "features": features,
        "quality": quality,
        "limitations": limitations,
        "source": source,
        "provenance": provenance,
    }


def compute_dataflow_quality_metrics(sdf_full: dict[str, Any]) -> dict[str, Any]:
    """Phase 2.3.3 — coverage / confidence metrics from a full semantic dataflow result."""
    records = list(sdf_full.get("functions") or [])
    if not isinstance(records, list):
        records = []
    records = [r for r in records if isinstance(r, dict)]
    total = len(records)
    if total == 0:
        return {
            "totalFunctions": 0,
            "dataflowExportCoverage": 0.0,
            "parameterRecoveryCoverage": 0.0,
            "memoryAccessCoverage": 0.0,
            "dataReferenceCoverage": 0.0,
            "unresolvedDataflowCount": 0,
            "semanticConfidenceDistribution": {
                PROVENANCE_GHIDRA_EXPORTED: 0,
                PROVENANCE_MNEMONIC_DERIVED: 0,
                PROVENANCE_PARTIAL: 0,
                PROVENANCE_NOT_AVAILABLE: 0,
            },
        }

    exported_ok = sum(
        1
        for r in records
        if r.get("provenance") == PROVENANCE_GHIDRA_EXPORTED and str(r.get("quality") or "").lower() == "ok"
    )
    # parameterCount null = unknown; 0 = Ghidra recovered zero params (not invented, but may be incomplete).
    with_params = sum(1 for r in records if r.get("parameterCount") is not None)
    with_params_nonzero = sum(
        1 for r in records if r.get("parameterCount") is not None and int(r.get("parameterCount") or 0) > 0
    )
    with_mem = sum(
        1 for r in records if int(r.get("memoryReads") or 0) > 0 or int(r.get("memoryWrites") or 0) > 0
    )
    with_refs = sum(1 for r in records if int(r.get("dataReferenceCount") or 0) > 0)
    unresolved = sum(
        1
        for r in records
        if str(r.get("quality") or "").lower() == "missing"
        or r.get("provenance") in (PROVENANCE_PARTIAL, PROVENANCE_NOT_AVAILABLE)
    )
    dist = {
        PROVENANCE_GHIDRA_EXPORTED: sum(1 for r in records if r.get("provenance") == PROVENANCE_GHIDRA_EXPORTED),
        PROVENANCE_MNEMONIC_DERIVED: sum(
            1 for r in records if r.get("provenance") == PROVENANCE_MNEMONIC_DERIVED
        ),
        PROVENANCE_PARTIAL: sum(1 for r in records if r.get("provenance") == PROVENANCE_PARTIAL),
        PROVENANCE_NOT_AVAILABLE: sum(1 for r in records if r.get("provenance") == PROVENANCE_NOT_AVAILABLE),
    }
    pct = lambda n: (n / total * 100.0) if total else 0.0
    return {
        "totalFunctions": total,
        "dataflowExportCoverage": pct(exported_ok),
        "parameterRecoveryCoverage": pct(with_params),
        "parameterNonZeroCoverage": pct(with_params_nonzero),
        "memoryAccessCoverage": pct(with_mem),
        "dataReferenceCoverage": pct(with_refs),
        "unresolvedDataflowCount": unresolved,
        "semanticConfidenceDistribution": dist,
        "exportedOkCount": exported_ok,
        "parameterKnownCount": with_params,
        "parameterNonZeroCount": with_params_nonzero,
        "memoryAccessCount": with_mem,
        "dataReferenceCount": with_refs,
        "note": (
            "parameterRecoveryCoverage zählt auch parameterCount=0 als bekannt "
            "(nicht null); parameterNonZeroCoverage misst >0."
        ),
    }


def analyze_semantic_dataflow(
    function_analysis: dict[str, Any] | None,
    dataflow_export: dict[str, Any] | None = None,
    call_graph: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Analyze compact semantic data-flow features (Phase 2.3.1).

    Parameters
    ----------
    function_analysis:
        Loaded ExportFunctionAnalysis payload (or ``load_function_analysis`` result).
    dataflow_export:
        Optional ExportDataFlowSummary payload / ``load_dataflow_export`` result.
    call_graph:
        Optional call-graph export to refine callCount when needed.
    """
    notes: list[str] = [f"phase={PHASE}"]
    limitations = list(BASE_LIMITATIONS)

    fns = _fns(function_analysis)
    if not fns and isinstance(function_analysis, dict) and function_analysis.get("ok") is False:
        notes.append("functionAnalysis=missing-or-invalid")
        limitations.append("Funktionsexport fehlt oder ungültig.")

    df_ok = isinstance(dataflow_export, dict) and (
        dataflow_export.get("ok") is True
        or (dataflow_export.get("ok") is None and isinstance(dataflow_export.get("functions"), list))
    )
    df_fns = _fns(dataflow_export) if df_ok else []
    df_index = _index_by_addr(df_fns)
    if df_ok and df_fns:
        notes.append(f"dataflowExport=ok count={len(df_fns)}")
    else:
        notes.append("dataflowExport=absent-deriving")
        limitations.append("Dataflow-Export fehlt — Ableitung aus Function-Analysis.")
        if isinstance(dataflow_export, dict):
            for lim in dataflow_export.get("analysisLimitations") or []:
                if isinstance(lim, str) and lim not in limitations:
                    limitations.append(lim)

    graph_counts = _call_counts_from_graph(call_graph)
    if graph_counts:
        notes.append("callGraph=used-for-callCount-fallback")

    # Prefer function_analysis as the primary iteration order; append dataflow-only.
    seen: set[str] = set()
    records: list[dict[str, Any]] = []
    max_fns = max(50, MAX_FUNCTIONS)
    truncated = False

    for fn in fns:
        if len(records) >= max_fns:
            truncated = True
            break
        addr = _addr(fn)
        key = addr.lower().replace("0x", "") if addr else ""
        if key:
            seen.add(key)
        df = None
        if key:
            df = df_index.get(key) or df_index.get(addr.lower())
        gcalls = None
        if key:
            gcalls = graph_counts.get(key)
            if gcalls is None and addr:
                gcalls = graph_counts.get(addr.lower())
        records.append(_derive_from_function(fn, df=df, graph_calls=gcalls))

    if not truncated:
        for df in df_fns:
            if len(records) >= max_fns:
                truncated = True
                break
            addr = _addr(df)
            key = addr.lower().replace("0x", "") if addr else ""
            if key and key in seen:
                continue
            if key:
                seen.add(key)
            # Minimal stub from dataflow-only row.
            stub = {
                "address": addr,
                "name": _name(df),
                "basicBlocks": 1,
                "mnemonics": [],
                "calls": [],
                "constants": [],
                "strings": [],
            }
            gcalls = graph_counts.get(key) if key else None
            records.append(_derive_from_function(stub, df=df, graph_calls=gcalls))

    if truncated:
        limitations.append(f"Analyse auf MAX_FUNCTIONS={max_fns} begrenzt.")
        notes.append(f"truncated=1 max={max_fns}")

    quality_ok = sum(1 for r in records if r.get("quality") == "ok")
    quality_partial = sum(1 for r in records if r.get("quality") == "partial")
    quality_missing = sum(1 for r in records if r.get("quality") == "missing")
    with_reads = sum(1 for r in records if int(r.get("memoryReads") or 0) > 0)
    with_writes = sum(1 for r in records if int(r.get("memoryWrites") or 0) > 0)
    with_cond = sum(1 for r in records if r.get("features", {}).get("feedsConditionals"))
    with_calls = sum(1 for r in records if int(r.get("callCount") or 0) > 0)
    with_params = sum(
        1 for r in records if r.get("parameterCount") is not None and int(r["parameterCount"]) > 0
    )
    derived_n = sum(1 for r in records if r.get("source") == "derived")
    export_n = sum(1 for r in records if r.get("source") == "dataflow_export")
    prov_counts = {
        PROVENANCE_GHIDRA_EXPORTED: sum(
            1 for r in records if r.get("provenance") == PROVENANCE_GHIDRA_EXPORTED
        ),
        PROVENANCE_MNEMONIC_DERIVED: sum(
            1 for r in records if r.get("provenance") == PROVENANCE_MNEMONIC_DERIVED
        ),
        PROVENANCE_PARTIAL: sum(1 for r in records if r.get("provenance") == PROVENANCE_PARTIAL),
        PROVENANCE_NOT_AVAILABLE: sum(
            1 for r in records if r.get("provenance") == PROVENANCE_NOT_AVAILABLE
        ),
    }
    total_fn = len(records)
    exported_n = prov_counts[PROVENANCE_GHIDRA_EXPORTED]
    coverage_pct = (exported_n / total_fn * 100.0) if total_fn else 0.0

    summary = {
        "functionCount": total_fn,
        "totalFunctions": total_fn,
        "qualityOk": quality_ok,
        "qualityPartial": quality_partial,
        "qualityMissing": quality_missing,
        "withMemoryReads": with_reads,
        "withMemoryWrites": with_writes,
        "withConditionals": with_cond,
        "withCalls": with_calls,
        "withParameters": with_params,
        "fromDataflowExport": export_n,
        "derivedOnly": derived_n,
        "exportedFunctions": exported_n,
        "derivedFunctions": prov_counts[PROVENANCE_MNEMONIC_DERIVED],
        "partialFunctions": prov_counts[PROVENANCE_PARTIAL],
        "unavailableFunctions": prov_counts[PROVENANCE_NOT_AVAILABLE],
        "dataflowCoveragePercent": coverage_pct,
        "provenanceCounts": prov_counts,
        "truncated": truncated,
        "maxFunctions": max_fns,
    }
    quality_metrics = compute_dataflow_quality_metrics(
        {"functions": records, "summary": summary}
    )
    summary["dataflowQualityMetrics"] = quality_metrics
    notes.append(
        f"semanticDataflow=ok functions={len(records)} "
        f"ok={quality_ok} partial={quality_partial} missing={quality_missing}"
    )
    notes.append(
        f"dataflowExportCoverage={quality_metrics.get('dataflowExportCoverage'):.2f}% "
        f"unresolved={quality_metrics.get('unresolvedDataflowCount')}"
    )

    processor = None
    if isinstance(function_analysis, dict):
        processor = function_analysis.get("processor")
    if not processor and isinstance(dataflow_export, dict):
        processor = dataflow_export.get("processor")

    return {
        "ok": bool(records) or bool(fns),
        "schemaVersion": SCHEMA_VERSION,
        "phase": PHASE,
        "processor": processor,
        "summary": summary,
        "functions": records[:max_fns],
        "analysisLimitations": limitations,
        "notes": notes,
    }


def summarize_semantic_dataflow_for_poll(full: dict[str, Any]) -> dict[str, Any]:
    """Compact poll-safe summary — no large uncontrolled arrays."""
    fns = full.get("functions") or []
    sample = fns[:MAX_POLL_FUNCTIONS] if isinstance(fns, list) else []
    summary = full.get("summary") if isinstance(full.get("summary"), dict) else {}
    return {
        "ok": bool(full.get("ok")),
        "schemaVersion": full.get("schemaVersion", SCHEMA_VERSION),
        "phase": full.get("phase", PHASE),
        "processor": full.get("processor"),
        "summary": {
            "functionCount": summary.get("functionCount", len(sample)),
            "qualityOk": summary.get("qualityOk"),
            "qualityPartial": summary.get("qualityPartial"),
            "qualityMissing": summary.get("qualityMissing"),
            "withMemoryReads": summary.get("withMemoryReads"),
            "withMemoryWrites": summary.get("withMemoryWrites"),
            "withConditionals": summary.get("withConditionals"),
            "withCalls": summary.get("withCalls"),
            "fromDataflowExport": summary.get("fromDataflowExport"),
            "derivedOnly": summary.get("derivedOnly"),
            "totalFunctions": summary.get("totalFunctions"),
            "exportedFunctions": summary.get("exportedFunctions"),
            "derivedFunctions": summary.get("derivedFunctions"),
            "partialFunctions": summary.get("partialFunctions"),
            "unavailableFunctions": summary.get("unavailableFunctions"),
            "dataflowCoveragePercent": summary.get("dataflowCoveragePercent"),
            "provenanceCounts": summary.get("provenanceCounts"),
            "truncated": summary.get("truncated"),
            "dataflowQualityMetrics": summary.get("dataflowQualityMetrics"),
        },
        "sampleFunctions": [
            {
                "address": f.get("address"),
                "name": f.get("name"),
                "parameterCount": f.get("parameterCount"),
                "memoryReads": f.get("memoryReads"),
                "memoryWrites": f.get("memoryWrites"),
                "compareOps": f.get("compareOps"),
                "conditionalBranches": f.get("conditionalBranches"),
                "callCount": f.get("callCount"),
                "dataReferenceCount": f.get("dataReferenceCount"),
                "features": f.get("features"),
                "quality": f.get("quality"),
                "provenance": f.get("provenance"),
            }
            for f in sample
            if isinstance(f, dict)
        ],
        "notes": list(full.get("notes") or []),
        "analysisLimitations": list(full.get("analysisLimitations") or []),
    }
