#!/usr/bin/env python3
"""Generate Phase 2.3.3 test fixtures (≥40 GT cases, variants A–G, ghidra GT)."""
from __future__ import annotations

import copy
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "testdata" / "phase233" / "fixtures"
GT_DIR = ROOT / "testdata" / "phase233" / "ghidra_export_gt"
MANUAL = ROOT / "testdata" / "phase233" / "manual"

SHIFT_D = 0x1000
BASE = 0x08001000
STEP = 0x80


def _addr(i: int) -> str:
    return hex(BASE + i * STEP)


def _generic(addr: str) -> str:
    return f"FUN_{addr.replace('0x', '').upper()}"


# id, name (None→FUN_*), expectDetect, category, profile dict
CASES: list[dict] = [
    # --- positives (named / structural) ---
    ("fn_00", "btn_input_handler", True, "button_input", {"mmio": True, "fan_in": 3, "strings": ["button"]}),
    ("fn_01", "gpio_exti_isr", True, "gpio_input", {"mmio": True, "fan_in": 3, "strings": ["gpio"]}),
    ("fn_02", "indicator_process", True, "indicator_input", {"fan_in": 2, "strings": ["indicator"]}),
    ("fn_03", "hazard_lamp_update", True, "hazard_indicator_input", {"strings": ["hazard"]}),
    ("fn_04", "ble_gatt_on_write", True, "ble_input", {"fan_in": 3, "strings": ["ble", "gatt"]}),
    ("fn_05", "uart_rx_event", True, "uart_input", {"fan_in": 3, "strings": ["uart", "rx"]}),
    ("fn_06", "event_queue_dispatch", True, "event_queue", {"fan_in": 2, "event_queue": True, "strings": ["event", "queue"]}),
    ("fn_07", "mode_state_set", True, "state_update", {"strings": ["state"], "branch_light": True}),
    ("fn_08", None, True, "input_callback", {"fan_in": 3, "strings": ["state", "mode"]}),
    ("fn_09", None, True, "input_callback", {"strings": ["process_input"], "fan_in": 2}),
    ("fn_11", None, True, "input_callback", {"strings": ["msg_handler"]}),
    ("fn_13", "process_input_frame", True, "input_callback", {"fan_in": 3, "strings": ["input"]}),
    ("fn_14", "feature_gate_check", True, "conditional_feature_gate", {"fan_in": 2, "strings": ["feature", "gate"], "stores": 2}),
    ("fn_15", "can_rx_decode", True, "uart_input", {"fan_in": 3, "strings": ["can"], "mmio": True}),
    ("fn_16", None, True, "event_queue", {"event_queue": True, "fan_in": 3}),
    ("fn_17", "button_debounce", True, "button_input", {"fan_in": 3, "mmio": True}),
    ("fn_18", None, True, "input_callback", {"parameter_gated": True, "fan_in": 1}),
    # ambiguous weak positives
    ("fn_19", None, True, "input_callback", {"fan_in": 2, "weak": True, "strings": ["handler"]}),
    ("fn_20", "adc_sample_isr", True, "gpio_input", {"fan_in": 3, "mmio": True}),
    # --- negatives ---
    ("fn_10", "memcpy_like_helper", False, "negative_compute", {"negative": "compute"}),
    ("fn_12", "x86_stub_ignored", False, "negative_arch", {"negative": "arch", "processor": "x86:LE:32:default"}),
    ("fn_21", "math_kernel", False, "negative_compute", {"negative": "compute"}),
    ("fn_22", None, False, "negative_dense_branch", {"negative": "dense_branch"}),
    ("fn_23", None, False, "negative_memory_only", {"negative": "memory_only"}),
    ("fn_24", "crc16_update", False, "negative_compute", {"negative": "compute"}),
    ("fn_25", None, False, "negative_dense_branch", {"negative": "dense_branch"}),
    ("fn_26", "delay_loop", False, "negative_compute", {"negative": "compute"}),
    ("fn_27", None, False, "negative_memory_only", {"negative": "memory_only"}),
    ("fn_28", "nop_sled", False, "negative_compute", {"negative": "compute"}),
    ("fn_29", None, False, "negative_dense_branch", {"negative": "dense_branch"}),
    ("fn_30", "hash_mix", False, "negative_compute", {"negative": "compute"}),
    ("fn_31", None, False, "negative_memory_only", {"negative": "memory_only"}),
    ("fn_32", "float_div", False, "negative_compute", {"negative": "compute"}),
    ("fn_33", None, False, "negative_dense_branch", {"negative": "dense_branch"}),
    ("fn_34", "memcpy_block", False, "negative_compute", {"negative": "compute"}),
    ("fn_35", None, False, "negative_memory_only", {"negative": "memory_only"}),
    ("fn_36", "sort_compare", False, "negative_dense_branch", {"negative": "dense_branch"}),
    ("fn_37", "idle_wfi", False, "negative_compute", {"negative": "compute"}),
    ("fn_38", None, False, "negative_memory_only", {"negative": "memory_only"}),
    ("fn_39", "table_lookup", False, "negative_compute", {"negative": "compute"}),
    # ambiguous → expectDetect false per spec
    ("fn_40", None, False, "ambiguous_weak", {"expectAmbiguous": True, "weak": True, "fan_in": 2}),
    ("fn_41", "maybe_input", False, "ambiguous_weak", {"expectAmbiguous": True, "weak": True, "strings": ["input"]}),
]


def _mnemonics_for(profile: dict) -> list[str]:
    neg = profile.get("negative")
    if neg == "compute":
        return ["add", "mul", "mov", "bx"]
    if neg == "arch":
        return ["ret"]
    if neg == "dense_branch":
        return ["cmp", "beq", "cmp", "bne", "cmp", "blt", "cmp", "bgt", "cmp", "beq"]
    if neg == "memory_only":
        return ["ldr", "ldr", "str", "bx"]
    out = ["ldr", "cmp", "bne", "str", "bx"]
    if profile.get("event_queue") or profile.get("stores", 1) >= 2:
        out = ["ldr", "cmp", "cmp", "beq", "bne", "str", "str", "bx"]
    if profile.get("branch_light"):
        out = ["ldr", "cmp", "str", "bx"]
    if profile.get("parameter_gated"):
        out = ["push", "ldr", "cmp", "beq", "str", "pop", "bx"]
    return out


def _build_fn(i: int, spec: tuple) -> dict:
    _id, name, expect, category, profile = spec
    addr = _addr(i)
    disp_name = name or _generic(addr)
    mnems = _mnemonics_for(profile)
    fan = profile.get("fan_in", 0)
    called_by = [hex(0x0800F000 + j) for j in range(fan)] if fan else []
    constants = []
    if profile.get("mmio"):
        constants.append("0x40021000")
    fn: dict = {
        "address": addr,
        "name": disp_name,
        "size": 32 + len(mnems) * 4,
        "basicBlocks": max(1, len(mnems) // 3),
        "cfgEdges": max(0, len(mnems) // 2),
        "calls": [],
        "calledBy": called_by,
        "constants": constants,
        "strings": list(profile.get("strings") or []),
        "mnemonics": mnems,
        "branchMnemonicCount": sum(1 for m in mnems if m in ("beq", "bne", "blt", "bgt")),
        "fingerprint": f"fp_{_id}",
        "quality": "ok" if profile.get("negative") != "arch" else "unsupported_arch",
        "processor": profile.get("processor", "ARM:LE:32:Cortex"),
    }
    if profile.get("parameter_gated"):
        fn["parameterCount"] = 2
    return fn


def _variant_generic(export: dict) -> dict:
    out = copy.deepcopy(export)
    for f in out["functions"]:
        f["name"] = _generic(f["address"])
    return out


def _variant_no_strings(export: dict) -> dict:
    out = _variant_generic(export)
    for f in out["functions"]:
        f["strings"] = []
    return out


def _variant_shifted(export: dict) -> dict:
    out = copy.deepcopy(export)
    for f in out["functions"]:
        a = int(f["address"], 16) + SHIFT_D
        f["address"] = hex(a)
        f["name"] = _generic(f["address"])
        f["strings"] = []
        f.pop("fingerprint", None)
        f.pop("confidence", None)
    return out


def _variant_anon(export: dict) -> dict:
    out = _variant_no_strings(export)
    for f in out["functions"]:
        for k in ("fingerprint", "confidence", "quality", "processor"):
            f.pop(k, None)
    return out


def _variant_no_sig_dataflow(df: dict) -> dict:
    out = copy.deepcopy(df)
    for row in out.get("functions") or []:
        row.pop("parameterCount", None)
    return out


def _dataflow_row(fn: dict, *, partial: bool = False, quality: str = "ok") -> dict:
    mn = fn.get("mnemonics") or []
    reads = sum(1 for m in mn if str(m).startswith("ldr"))
    writes = sum(1 for m in mn if str(m).startswith("str"))
    compares = sum(1 for m in mn if m in ("cmp", "cmn", "tst"))
    branches = sum(1 for m in mn if m in ("beq", "bne", "blt", "bgt", "bne"))
    row = {
        "address": fn["address"],
        "name": fn["name"],
        "parameterCount": fn.get("parameterCount"),
        "memoryReads": reads,
        "memoryWrites": writes,
        "compareOps": compares,
        "conditionalBranches": max(branches, 1 if compares else 0),
        "callCount": len(fn.get("calls") or []),
        "dataReferenceCount": len(fn.get("constants") or []) + len(fn.get("strings") or []),
        "quality": quality,
    }
    if partial:
        row["limitations"] = ["partial export slice"]
    return row


def build() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    GT_DIR.mkdir(parents=True, exist_ok=True)
    MANUAL.mkdir(parents=True, exist_ok=True)

    functions = [_build_fn(i, spec) for i, spec in enumerate(CASES)]
    base = {
        "ok": True,
        "schemaVersion": 1,
        "featuresVersion": 2,
        "processor": "ARM:LE:32:Cortex",
        "functionCount": len(functions),
        "truncated": False,
        "functions": functions,
    }

    variants = {
        "A_named": copy.deepcopy(base),
        "B_generic": _variant_generic(base),
        "C_no_strings": _variant_no_strings(base),
        "D_shifted": _variant_shifted(base),
        "E_anon_meta": _variant_anon(base),
        "F_generic_no_signature": _variant_generic(base),
        "G_partial_dataflow": copy.deepcopy(base),
    }

    for key, data in variants.items():
        (OUT / f"{key}.functions.json").write_text(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )

    # Dataflow sidecars
    all_rows = [_dataflow_row(f) for f in functions]
    partial_rows = all_rows[: max(12, len(all_rows) // 3)]
    for key in ("A_named", "B_generic", "C_no_strings", "D_shifted", "E_anon_meta"):
        rows = all_rows if key == "A_named" else copy.deepcopy(all_rows)
        if key == "D_shifted":
            for r in rows:
                r["address"] = hex(int(r["address"], 16) + SHIFT_D)
        (OUT / f"{key}.dataflow.json").write_text(
            json.dumps(
                {
                    "ok": True,
                    "schemaVersion": 1,
                    "processor": "ARM:LE:32:Cortex",
                    "functionCount": len(rows),
                    "functions": rows,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

    f_rows = [_dataflow_row(f) for f in variants["F_generic_no_signature"]["functions"]]
    f_df = {"ok": True, "schemaVersion": 1, "functionCount": len(f_rows), "functions": f_rows}
    f_df = _variant_no_sig_dataflow(f_df)
    (OUT / "F_generic_no_signature.dataflow.json").write_text(json.dumps(f_df, indent=2) + "\n", encoding="utf-8")

    g_rows = [_dataflow_row(f, partial=True, quality="partial") for f in partial_rows]
    (OUT / "G_partial_dataflow.dataflow.json").write_text(
        json.dumps(
            {"ok": True, "schemaVersion": 1, "functionCount": len(g_rows), "functions": g_rows},
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    gt_cases = []
    pos = neg = 0
    for i, spec in enumerate(CASES):
        _id, name, expect, category, profile = spec
        addr_a = _addr(i)
        addr_d = hex(int(addr_a, 16) + SHIFT_D)
        amb = bool(profile.get("expectAmbiguous"))
        entry = {
            "id": _id,
            "logicalName": name,
            "addressA": addr_a,
            "addressD": addr_d,
            "expectDetect": expect,
            "category": category,
        }
        if amb:
            entry["expectAmbiguous"] = True
        gt_cases.append(entry)
        if expect:
            pos += 1
        else:
            neg += 1

    ground = {
        "schemaVersion": 1,
        "phase": "2.3.3",
        "disclaimer": "Kontrollierte Fixtures — keine realen Aktivierungsmechanismen.",
        "addressShiftD": hex(SHIFT_D),
        "variants": {k: {"file": f"{k}.functions.json"} for k in variants},
        "cases": gt_cases,
        "expectCounts": {"positives": pos, "negatives": neg, "total": len(gt_cases)},
    }
    (OUT / "ground_truth.json").write_text(json.dumps(ground, indent=2) + "\n", encoding="utf-8")

    # Ghidra export GT (10 synthetic)
    synth_fns = []
    synth_df = []
    gt_export = []
    templates = [
        ("gt_00", "thumb_entry", 1, 2, 1, 0, 1, True),
        ("gt_01", "FUN_deadbeef", None, 0, 0, 0, 0, False),
        ("gt_02", "mem_rw_helper", 0, 3, 2, 0, 0, False),
        ("gt_03", "call_hub", 2, 1, 0, 4, 2, False),
        ("gt_04", "branch_dispatch", 1, 1, 0, 2, 5, False),
        ("gt_05", "ret_thunk", 0, 0, 0, 0, 0, False),
        ("gt_06", "global_ref_init", 0, 2, 3, 0, 0, True),
        ("gt_07", "local_only", 1, 1, 1, 0, 0, False),
        ("gt_08", "incomplete_sig", None, 1, 0, 0, 1, False),
        ("gt_09", "indirect_caller", 0, 0, 0, 1, 1, False),
    ]
    for j, (gid, nm, pc, rd, wr, cc, br, gref) in enumerate(templates):
        ad = hex(0x08010000 + j * 0x20)
        synth_fns.append(
            {
                "address": ad,
                "name": nm,
                "size": 24,
                "basicBlocks": 2,
                "cfgEdges": 2,
                "mnemonics": ["ldr", "cmp", "beq", "bx"] if br else ["bx"],
                "calls": ["0x08020000"] if cc else [],
                "constants": ["0x20001000"] if gref else [],
            }
        )
        row = {
            "address": ad,
            "name": nm,
            "parameterCount": pc,
            "memoryReads": rd,
            "memoryWrites": wr,
            "compareOps": 1 if br else 0,
            "conditionalBranches": br,
            "callCount": cc,
            "dataReferenceCount": (1 if gref else 0) + (1 if pc is not None else 0),
            "quality": "partial" if pc is None and nm == "incomplete_sig" else "ok",
        }
        if pc is None and nm != "FUN_deadbeef":
            row["limitations"] = ["signature unknown"]
        synth_df.append(row)
        gt_export.append(
            {
                "id": gid,
                "address": ad,
                "name": nm,
                "expect": {
                    "parameterCount": pc,
                    "memoryReads": rd,
                    "memoryWrites": wr,
                    "callCount": cc,
                    "conditionalBranches": br,
                    "dataReferenceCount": row["dataReferenceCount"],
                    "globalRef": gref,
                    "returnPresent": True,
                    "quality": row["quality"],
                },
            }
        )

    (GT_DIR / "synthetic_functions.json").write_text(
        json.dumps({"ok": True, "functionCount": len(synth_fns), "functions": synth_fns}, indent=2) + "\n",
        encoding="utf-8",
    )
    (GT_DIR / "synthetic_dataflow.json").write_text(
        json.dumps({"ok": True, "functionCount": len(synth_df), "functions": synth_df}, indent=2) + "\n",
        encoding="utf-8",
    )
    (GT_DIR / "ground_truth.json").write_text(
        json.dumps({"schemaVersion": 1, "phase": "2.3.3", "functions": gt_export}, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Wrote {len(gt_cases)} GT cases ({pos}+ / {neg}-) to {OUT}")


if __name__ == "__main__":
    build()