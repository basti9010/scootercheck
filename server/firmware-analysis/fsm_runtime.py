"""Controlled Unicorn FSM runtime validation (Phase 2.2F).

Runs ONLY synthetic Thumb test programs. Never claims real vehicle behavior.
"""
from __future__ import annotations

import os
import struct
import time
from pathlib import Path
from typing import Any

ENABLE_FSM_RUNTIME = os.environ.get("ENABLE_FSM_RUNTIME", "1").strip() not in ("0", "false", "False")
MAX_INSNS = int(os.environ.get("FSM_RUNTIME_MAX_INSNS", "5000") or "5000")
FLASH_BASE = 0x08000000
SRAM_BASE = 0x20000000
SRAM_SIZE = 0x10000

# Evidence tiers (Phase 2.2F)
STATIC_CANDIDATE = "STATIC_CANDIDATE"
STATIC_STRUCTURE_IDENTIFIED = "STATIC_STRUCTURE_IDENTIFIED"
RUNTIME_TRANSITION_OBSERVED = "RUNTIME_TRANSITION_OBSERVED"
NOT_VERIFIABLE = "NOT_VERIFIABLE"


def unicorn_fsm_available() -> bool:
    if not ENABLE_FSM_RUNTIME:
        return False
    try:
        import unicorn  # noqa: F401

        return True
    except ImportError:
        return False


def build_two_state_program() -> dict[str, Any]:
    """Thumb program: global state at SRAM+0x100; event r0=1 transitions 0→1.

    Layout (Thumb):
      reset: mov r1, #state_lo; movt-like via literal; load state; cmp; ...
    Simplified hand-assembled blob with documented GT.
    """
    # Minimal documented machine for tests: we emulate via a tiny custom loop
    # using Unicorn + explicit state variable writes observed by hooks.
    # Bytes are a nop-sled + simple load/store sequence built below.
    state_addr = SRAM_BASE + 0x100
    code = bytearray()
    # movs r0, #0 ; str r0, [r1]  — need r1=state_addr first
    # We'll set registers in emulator setup; code:
    #   ldr r2, [r1]        @ load state
    #   cmp r2, #0
    #   bne done
    #   cmp r0, #1          @ event
    #   bne done
    #   movs r2, #1
    #   str r2, [r1]
    # done: b done / bkpt
    # End with spin (b .) — avoid BKPT which raises UC_ERR_EXCEPTION.
    code += bytes.fromhex(
        "0a68"  # ldr r2, [r1]
        "002a"  # cmp r2, #0
        "04d1"  # bne end
        "0128"  # cmp r0, #1
        "02d1"  # bne end
        "0122"  # movs r2, #1
        "0a60"  # str r2, [r1]
        "fee7"  # end: b .
    )
    return {
        "name": "two_state_one_transition",
        "code": bytes(code),
        "entryOffset": 0,
        "stateAddress": state_addr,
        "initialState": 0,
        "eventRegister": "r0",
        "eventValue": 1,
        "expectedFinalState": 1,
        "expectedTransitions": [{"from": 0, "to": 1, "event": 1}],
        "thumb": True,
    }


def build_three_state_program() -> dict[str, Any]:
    state_addr = SRAM_BASE + 0x104
    # Similar: if state==0 and event==1 -> 1; if state==1 and event==2 -> 2
    code = bytearray()
    code += bytes.fromhex(
        "0a68"  # ldr r2,[r1]
        "002a"  # cmp r2,#0
        "05d1"  # bne check1
        "0128"  # cmp r0,#1
        "0ad1"  # bne end
        "0122"  # movs r2,#1
        "0a60"  # str r2,[r1]
        "08e0"  # b end
        # check1:
        "012a"  # cmp r2,#1
        "05d1"  # bne end
        "0228"  # cmp r0,#2
        "03d1"  # bne end
        "0222"  # movs r2,#2
        "0a60"  # str r2,[r1]
        # end:
        "fee7"  # b .
    )
    return {
        "name": "three_state_multi",
        "code": bytes(code),
        "entryOffset": 0,
        "stateAddress": state_addr,
        "initialState": 0,
        "eventRegister": "r0",
        "eventValue": 1,
        "expectedFinalState": 1,
        "expectedTransitions": [{"from": 0, "to": 1, "event": 1}],
        "secondStep": {"eventValue": 2, "expectedFinalState": 2},
        "thumb": True,
    }


def build_no_transition_program() -> dict[str, Any]:
    p = build_two_state_program()
    p["name"] = "no_transition"
    p["eventValue"] = 0  # wrong event
    p["expectedFinalState"] = 0
    p["expectedTransitions"] = []
    return p


def run_fsm_program(program: dict[str, Any]) -> dict[str, Any]:
    """Execute one synthetic FSM program under Unicorn."""
    limitations = [
        "Unicorn-Test ist kein Nachweis realen Fahrzeugverhaltens.",
        "Nur künstliche Testprogramme — keine Scooter-Firmware.",
    ]
    if not unicorn_fsm_available():
        return {
            "ok": False,
            "program": program.get("name"),
            "evidenceTier": NOT_VERIFIABLE,
            "error": "unicorn unavailable",
            "analysisLimitations": limitations + ["Unicorn nicht installiert/deaktiviert."],
            "dynamicRuntimeVerified": False,
        }

    from unicorn import Uc, UcError, UC_ARCH_ARM, UC_MODE_THUMB, UC_HOOK_CODE, UC_HOOK_MEM_INVALID
    from unicorn.arm_const import UC_ARM_REG_PC, UC_ARM_REG_SP, UC_ARM_REG_R0, UC_ARM_REG_R1

    code = bytes(program["code"])
    flash_size = max(0x1000, ((len(code) + 0xFFF) // 0x1000) * 0x1000)
    state_addr = int(program["stateAddress"])
    initial = int(program.get("initialState") or 0)
    event = int(program.get("eventValue") or 0)
    transitions_observed: list[dict[str, Any]] = []
    last_state = [initial]
    insn_count = [0]
    abort_reason = None
    t0 = time.perf_counter()

    try:
        mu = Uc(UC_ARCH_ARM, UC_MODE_THUMB)
        mu.mem_map(FLASH_BASE, flash_size)
        mu.mem_map(SRAM_BASE, SRAM_SIZE)
        mu.mem_write(FLASH_BASE, code + b"\x00" * (flash_size - len(code)))
        mu.mem_write(state_addr, struct.pack("<I", initial))
        mu.reg_write(UC_ARM_REG_SP, SRAM_BASE + SRAM_SIZE - 0x100)
        mu.reg_write(UC_ARM_REG_R1, state_addr)
        mu.reg_write(UC_ARM_REG_R0, event)
        start = FLASH_BASE + int(program.get("entryOffset") or 0)
        mu.reg_write(UC_ARM_REG_PC, start | 1)

        def on_code(uc, address, size, user_data):
            insn_count[0] += 1
            if insn_count[0] > MAX_INSNS:
                uc.emu_stop()
            try:
                cur = struct.unpack("<I", uc.mem_read(state_addr, 4))[0]
            except Exception:
                return
            if cur != last_state[0]:
                transitions_observed.append(
                    {"from": last_state[0], "to": cur, "atInsn": insn_count[0], "pc": hex(address)}
                )
                last_state[0] = cur

        def on_mem_invalid(uc, access, address, size, value, user_data):
            nonlocal abort_reason
            abort_reason = f"mem_invalid@{address:#x}"
            return False

        mu.hook_add(UC_HOOK_CODE, on_code)
        mu.hook_add(UC_HOOK_MEM_INVALID, on_mem_invalid)
        try:
            mu.emu_start(start | 1, FLASH_BASE + len(code) + 8, count=0, timeout=2_000_000)
        except UcError as e:
            abort_reason = abort_reason or f"UcError:{e}"

        # Optional second step for multi-transition programs
        second = program.get("secondStep")
        if second and abort_reason is None:
            insn_count[0] = 0  # allow another bounded run after spin-stop
            mu.reg_write(UC_ARM_REG_R0, int(second["eventValue"]))
            mu.reg_write(UC_ARM_REG_PC, start | 1)
            try:
                mu.emu_start(start | 1, FLASH_BASE + len(code) + 8, count=0, timeout=2_000_000)
            except UcError as e:
                abort_reason = abort_reason or f"UcError:second:{e}"

        final = struct.unpack("<I", mu.mem_read(state_addr, 4))[0]
    except Exception as e:
        return {
            "ok": False,
            "program": program.get("name"),
            "evidenceTier": NOT_VERIFIABLE,
            "error": f"{type(e).__name__}:{e}",
            "analysisLimitations": limitations,
            "dynamicRuntimeVerified": False,
        }

    elapsed_ms = (time.perf_counter() - t0) * 1000
    if abort_reason is None and insn_count[0] >= MAX_INSNS:
        abort_reason = "insn_limit"
    expected_final = program.get("expectedFinalState")
    match = expected_final is None or final == expected_final
    observed = len(transitions_observed) > 0
    if observed and match:
        tier = RUNTIME_TRANSITION_OBSERVED
    elif observed:
        tier = RUNTIME_TRANSITION_OBSERVED  # observed but mismatch still runtime data
    else:
        tier = NOT_VERIFIABLE if abort_reason else STATIC_STRUCTURE_IDENTIFIED

    return {
        "ok": True,
        "program": program.get("name"),
        "initialState": initial,
        "finalState": final,
        "expectedFinalState": expected_final,
        "finalStateMatchedExpectation": match,
        "observedTransitions": transitions_observed,
        "expectedTransitions": program.get("expectedTransitions"),
        "instructionCount": insn_count[0],
        "elapsedMs": round(elapsed_ms, 3),
        "abortReason": abort_reason,
        "evidenceTier": tier,
        "dynamicRuntimeVerified": observed,
        "validationKind": "unicorn_controlled",
        "analysisLimitations": limitations
        + (["Timeout/Abort: " + abort_reason] if abort_reason else []),
        "notes": [
            f"fsmRuntime={program.get('name')} final={final} transitions={len(transitions_observed)} "
            f"insns={insn_count[0]} tier={tier}"
        ],
    }


def run_fsm_runtime_suite() -> dict[str, Any]:
    """Run the controlled suite of synthetic FSM programs."""
    programs = [
        build_two_state_program(),
        build_three_state_program(),
        build_no_transition_program(),
    ]
    # Event-driven alias
    ev = build_two_state_program()
    ev["name"] = "event_driven_transition"
    programs.append(ev)

    # Missing memory region test
    bad = build_two_state_program()
    bad["name"] = "missing_memory"
    bad["stateAddress"] = 0x30000000  # unmapped
    programs.append(bad)

    # Infinite loop with timeout
    loop = {
        "name": "infinite_loop_timeout",
        "code": bytes.fromhex("fee7"),  # b .
        "entryOffset": 0,
        "stateAddress": SRAM_BASE + 0x108,
        "initialState": 0,
        "eventValue": 0,
        "expectedFinalState": 0,
        "expectedTransitions": [],
        "thumb": True,
    }
    programs.append(loop)

    results = [run_fsm_program(p) for p in programs]
    observed = sum(1 for r in results if r.get("dynamicRuntimeVerified"))
    return {
        "ok": True,
        "schemaVersion": 1,
        "tool": "unicorn-fsm-runtime",
        "programCount": len(results),
        "runtimeTransitionsObserved": observed,
        "dynamicRuntimeVerified": observed > 0,
        "results": results,
        "evidenceTier": RUNTIME_TRANSITION_OBSERVED if observed else NOT_VERIFIABLE,
        "analysisLimitations": [
            "Nur kontrollierte synthetische Programme.",
            "Kein Nachweis realen Fahrzeugverhaltens.",
            "Statisch erwarteter Übergang ≠ Laufzeitnachweis.",
        ],
        "notes": [f"fsmRuntimeSuite observed={observed}/{len(results)}"],
    }


def merge_runtime_into_state_machines(
    state_machine_analysis: dict[str, Any] | None,
    runtime: dict[str, Any] | None,
) -> dict[str, Any] | None:
    """Attach runtime validation summary without claiming vehicle proof."""
    if not state_machine_analysis:
        return state_machine_analysis
    out = dict(state_machine_analysis)
    validation = dict(out.get("stateMachineValidation") or {})
    if runtime and runtime.get("ok"):
        validation["controlledTransitionEvidence"] = int(runtime.get("runtimeTransitionsObserved") or 0)
        validation["dynamicRuntimeVerified"] = bool(runtime.get("dynamicRuntimeVerified"))
        validation["runtimeSuite"] = {
            "programCount": runtime.get("programCount"),
            "evidenceTier": runtime.get("evidenceTier"),
            "notes": runtime.get("notes"),
        }
        # Map evidence: only mark RUNTIME when suite observed transitions
        if runtime.get("dynamicRuntimeVerified"):
            out["runtimeEvidenceTier"] = RUNTIME_TRANSITION_OBSERVED
        else:
            out["runtimeEvidenceTier"] = NOT_VERIFIABLE
    else:
        validation["dynamicRuntimeVerified"] = False
        out["runtimeEvidenceTier"] = NOT_VERIFIABLE
    validation.setdefault(
        "notes",
        [
            "Keine dynamische Laufzeitverifikation ohne Emulationsdaten.",
            "Unicorn-Suite ist kein Fahrzeugtest.",
        ],
    )
    out["stateMachineValidation"] = validation
    return out
