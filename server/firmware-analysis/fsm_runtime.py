"""Controlled Unicorn FSM runtime validation (Phase 2.2F/G).

Runs ONLY synthetic Thumb test programs. Never claims real vehicle behavior.
"""
from __future__ import annotations

import os
import struct
import time
from typing import Any

ENABLE_FSM_RUNTIME = os.environ.get("ENABLE_FSM_RUNTIME", "1").strip() not in ("0", "false", "False")
MAX_INSNS = int(os.environ.get("FSM_RUNTIME_MAX_INSNS", "5000") or "5000")
FLASH_BASE = 0x08000000
SRAM_BASE = 0x20000000
SRAM_SIZE = 0x10000

# Evidence tiers
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
    """Thumb: state@SRAM+0x100; event r0=1 transitions 0→1; then spin."""
    state_addr = SRAM_BASE + 0x100
    # Correct Thumb offsets (PC = insn+4):
    #   0: ldr; 2: cmp#0; 4: bne end(+6→0xc); 6: cmp#1; 8: bne end(+2→0xc);
    #   a: movs#1; c: str; e: b .
    code = bytes.fromhex(
        "0a68"  # 0: ldr r2, [r1]
        "002a"  # 2: cmp r2, #0
        "03d1"  # 4: bne end (→0xc)
        "0128"  # 6: cmp r0, #1
        "01d1"  # 8: bne end (→0xc)
        "0122"  # a: movs r2, #1
        "0a60"  # c: str r2, [r1]
        "fee7"  # e: end: b .
    )
    return {
        "name": "two_state_one_transition",
        "code": code,
        "entryOffset": 0,
        "stateAddress": state_addr,
        "initialState": 0,
        "eventValue": 1,
        "expectedFinalState": 1,
        "expectedTransitions": [{"from": 0, "to": 1, "event": 1}],
        "maxInsnsPerStep": 32,
        "thumb": True,
    }


def build_three_state_program() -> dict[str, Any]:
    """Thumb: 0→1 on event 1, then 1→2 on event 2 (multi-step).

    Layout (verified with Capstone):
      0:  ldr r2,[r1]
      2:  cmp r2,#0
      4:  bne check1          → 0x10
      6:  cmp r0,#1
      8:  bne end             → 0x1c
      a:  movs r2,#1
      c:  str r2,[r1]
      e:  b end               → 0x1c
     10: check1: cmp r2,#1
     12: bne end              → 0x1c
     14: cmp r0,#2
     16: bne end              → 0x1c
     18: movs r2,#2
     1a: str r2,[r1]
     1c: end: b .
    """
    state_addr = SRAM_BASE + 0x104
    code = bytes.fromhex(
        "0a68"  # 0
        "002a"  # 2
        "04d1"  # 4: bne check1 → 0x10  (PC=8, +8)
        "0128"  # 6
        "08d1"  # 8: bne end → 0x1c       (PC=c, +16)
        "0122"  # a
        "0a60"  # c
        "05e0"  # e: b end → 0x1c         (PC=12, +10)
        "012a"  # 10: check1 cmp r2,#1
        "03d1"  # 12: bne end → 0x1c      (PC=16, +6)
        "0228"  # 14
        "01d1"  # 16: bne end → 0x1c      (PC=1a, +2)
        "0222"  # 18
        "0a60"  # 1a
        "fee7"  # 1c: end
    )
    return {
        "name": "three_state_multi",
        "code": code,
        "entryOffset": 0,
        "stateAddress": state_addr,
        "initialState": 0,
        "eventValue": 1,
        "expectedFinalState": 2,  # after full event sequence
        "expectedTransitions": [
            {"from": 0, "to": 1, "event": 1},
            {"from": 1, "to": 2, "event": 2},
        ],
        "eventSequence": [1, 2],
        "maxInsnsPerStep": 32,
        "thumb": True,
    }


def build_no_transition_program() -> dict[str, Any]:
    p = build_two_state_program()
    p["name"] = "no_transition"
    p["eventValue"] = 0
    p["expectedFinalState"] = 0
    p["expectedTransitions"] = []
    return p


def build_event_sequence_program() -> dict[str, Any]:
    p = build_three_state_program()
    p["name"] = "event_sequence_ordered"
    return p


def build_invalid_state_program() -> dict[str, Any]:
    """Start in invalid state 99 — no transition expected."""
    p = build_two_state_program()
    p["name"] = "invalid_initial_state"
    p["initialState"] = 99
    p["eventValue"] = 1
    p["expectedFinalState"] = 99
    p["expectedTransitions"] = []
    return p


def build_alt_initial_program() -> dict[str, Any]:
    """Start at state 1 with event 2 → expect 2 (uses three_state body)."""
    p = build_three_state_program()
    p["name"] = "alt_initial_state_1"
    p["initialState"] = 1
    p["eventValue"] = 2
    p["eventSequence"] = [2]
    p["expectedFinalState"] = 2
    p["expectedTransitions"] = [{"from": 1, "to": 2, "event": 2}]
    return p


def run_fsm_program(program: dict[str, Any]) -> dict[str, Any]:
    """Execute one synthetic FSM program under Unicorn."""
    limitations = [
        "Unicorn-Test ist kein Nachweis realen Fahrzeugverhaltens.",
        "Nur künstliche Testprogramme — keine Scooter-Firmware.",
        "Statisch erwarteter Übergang ≠ Laufzeitnachweis.",
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
    transitions_observed: list[dict[str, Any]] = []
    last_state = [initial]
    insn_count = [0]
    step_insns = [0]
    abort_reason = None
    t0 = time.perf_counter()
    max_per_step = int(program.get("maxInsnsPerStep") or MAX_INSNS)

    # Build event sequence: prefer eventSequence, else eventValue + optional secondStep
    events: list[int] = []
    if program.get("eventSequence"):
        events = [int(x) for x in program["eventSequence"]]
    else:
        events = [int(program.get("eventValue") or 0)]
        second = program.get("secondStep")
        if second and "eventValue" in second:
            events.append(int(second["eventValue"]))

    expected_final = program.get("expectedFinalState")
    if program.get("secondStep") and "expectedFinalState" in program["secondStep"] and len(events) > 1:
        # Prefer last-step expectation when sequence present without overriding explicit expectedFinalState
        if program.get("eventSequence") is None:
            expected_final = program["secondStep"]["expectedFinalState"]

    try:
        mu = Uc(UC_ARCH_ARM, UC_MODE_THUMB)
        mu.mem_map(FLASH_BASE, flash_size)
        mu.mem_map(SRAM_BASE, SRAM_SIZE)
        mu.mem_write(FLASH_BASE, code + b"\x00" * (flash_size - len(code)))
        mu.mem_write(state_addr, struct.pack("<I", initial))
        mu.reg_write(UC_ARM_REG_SP, SRAM_BASE + SRAM_SIZE - 0x100)
        mu.reg_write(UC_ARM_REG_R1, state_addr)
        start = FLASH_BASE + int(program.get("entryOffset") or 0)

        def on_code(uc, address, size, user_data):
            insn_count[0] += 1
            step_insns[0] += 1
            if step_insns[0] > max_per_step:
                uc.emu_stop()
                return
            try:
                cur = struct.unpack("<I", uc.mem_read(state_addr, 4))[0]
            except Exception:
                return
            if cur != last_state[0]:
                transitions_observed.append(
                    {
                        "from": last_state[0],
                        "to": cur,
                        "atInsn": insn_count[0],
                        "pc": hex(address),
                        "event": user_data,
                    }
                )
                last_state[0] = cur

        def on_mem_invalid(uc, access, address, size, value, user_data):
            nonlocal abort_reason
            abort_reason = f"mem_invalid@{address:#x}"
            return False

        mu.hook_add(UC_HOOK_MEM_INVALID, on_mem_invalid)

        for ev in events:
            if abort_reason and abort_reason.startswith("mem_invalid"):
                break
            step_insns[0] = 0
            # Clear spin-stop abort between deliberate multi-steps
            if abort_reason in {"insn_limit", "step_insn_limit"}:
                abort_reason = None
            mu.reg_write(UC_ARM_REG_R0, int(ev))
            mu.reg_write(UC_ARM_REG_R1, state_addr)
            mu.reg_write(UC_ARM_REG_PC, start | 1)
            hook = mu.hook_add(UC_HOOK_CODE, on_code, user_data=int(ev))
            try:
                mu.emu_start(start | 1, FLASH_BASE + len(code) + 8, count=0, timeout=2_000_000)
            except UcError as e:
                abort_reason = abort_reason or f"UcError:{e}"
            finally:
                try:
                    mu.hook_del(hook)
                except Exception:
                    pass
            if step_insns[0] >= max_per_step and abort_reason is None:
                # Intentional spin stop — not a failure for multi-step FSMs
                abort_reason = "step_insn_limit"

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
    # step_insn_limit after successful work is not a hard failure
    soft_abort = abort_reason in {"step_insn_limit", "insn_limit"}
    hard_abort = abort_reason and not soft_abort
    match = expected_final is None or final == expected_final
    observed = len(transitions_observed) > 0
    # Timeout/spin alone never counts as a transition
    if hard_abort and not observed:
        tier = NOT_VERIFIABLE
    elif observed:
        tier = RUNTIME_TRANSITION_OBSERVED
    elif soft_abort and not observed:
        tier = STATIC_STRUCTURE_IDENTIFIED if match else NOT_VERIFIABLE
    else:
        tier = STATIC_STRUCTURE_IDENTIFIED if match else NOT_VERIFIABLE

    return {
        "ok": not bool(hard_abort and not observed),
        "program": program.get("name"),
        "initialState": initial,
        "finalState": final,
        "expectedFinalState": expected_final,
        "finalStateMatchedExpectation": match,
        "eventSequence": events,
        "observedTransitions": transitions_observed,
        "expectedTransitions": program.get("expectedTransitions"),
        "instructionCount": insn_count[0],
        "elapsedMs": round(elapsed_ms, 3),
        "abortReason": abort_reason,
        "evidenceTier": tier,
        "dynamicRuntimeVerified": observed,
        "validationKind": "unicorn_controlled",
        "analysisLimitations": limitations
        + ([f"Abort: {abort_reason}"] if hard_abort else [])
        + (["Spin/Instruktionslimit nach Schritt (erwartet bei Endlosschleife)."] if soft_abort else []),
        "notes": [
            f"fsmRuntime={program.get('name')} final={final} transitions={len(transitions_observed)} "
            f"insns={insn_count[0]} tier={tier} events={events}"
        ],
    }


def run_fsm_runtime_suite() -> dict[str, Any]:
    """Run the controlled suite of synthetic FSM programs."""
    programs = [
        build_two_state_program(),
        build_three_state_program(),
        build_event_sequence_program(),
        build_no_transition_program(),
        build_invalid_state_program(),
        build_alt_initial_program(),
    ]

    # Missing memory region
    bad = build_two_state_program()
    bad["name"] = "missing_memory"
    bad["stateAddress"] = 0x30000000
    programs.append(bad)

    # Infinite loop with insn limit
    loop = {
        "name": "infinite_loop_timeout",
        "code": bytes.fromhex("fee7"),
        "entryOffset": 0,
        "stateAddress": SRAM_BASE + 0x108,
        "initialState": 0,
        "eventValue": 0,
        "expectedFinalState": 0,
        "expectedTransitions": [],
        "maxInsnsPerStep": 64,
        "thumb": True,
    }
    programs.append(loop)

    results = [run_fsm_program(p) for p in programs]
    # Reproducibility: re-run three_state twice
    t1 = run_fsm_program(build_three_state_program())
    t2 = run_fsm_program(build_three_state_program())
    repro_ok = (
        t1.get("finalState") == t2.get("finalState") == 2
        and len(t1.get("observedTransitions") or []) == len(t2.get("observedTransitions") or []) == 2
    )
    observed = sum(1 for r in results if r.get("dynamicRuntimeVerified"))
    return {
        "ok": True,
        "schemaVersion": 1,
        "tool": "unicorn-fsm-runtime",
        "programCount": len(results),
        "runtimeTransitionsObserved": observed,
        "dynamicRuntimeVerified": observed > 0,
        "threeStateReproducible": repro_ok,
        "results": results,
        "evidenceTier": RUNTIME_TRANSITION_OBSERVED if observed else NOT_VERIFIABLE,
        "analysisLimitations": [
            "Nur kontrollierte synthetische Programme.",
            "Kein Nachweis realen Fahrzeugverhaltens.",
            "Statisch erwarteter Übergang ≠ Laufzeitnachweis.",
            "Timeout/Spin allein ist kein Zustandsübergang.",
        ],
        "notes": [
            f"fsmRuntimeSuite observed={observed}/{len(results)} threeStateRepro={repro_ok}"
        ],
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
            "threeStateReproducible": runtime.get("threeStateReproducible"),
            "notes": runtime.get("notes"),
        }
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
