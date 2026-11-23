# ScooterCheck – Agent Task Queue

**Cycle:** 2 (P0 Hardening)  
**Branch:** `cursor/multi-agent-system-b100`  
**Lock:** `CYCLE2_ACTIVE` — keine parallelen Autonomie-Timer für denselben Scope  
**Zuletzt gelesen:** 2026-11-23 (Europe/Berlin)

Statuswerte: `BACKLOG` | `READY` | `IN_PROGRESS` | `REVIEW` | `BLOCKED` | `DONE`

---

## Orchestrierung (ehrlich)

| Custom Agent (`.cursor/agents/`) | Cloud `Task` subagent_type | Nutzung in Cycle 2 |
|----------------------------------|----------------------------|--------------------|
| project-manager | Parent / generalPurpose | Parent dieses Runs |
| bluetooth-specialist | generalPurpose (+ Brief) / Parent | P0-1, P0-2 (Parent mit Brief) |
| forensic-expert | generalPurpose (+ Brief) | P0-3 Worktree `bc-0711ce79…` |
| ios-developer | generalPurpose (+ Brief) | P0-4 Worktree `bc-763e88b0…` |
| qa-security | security-review / explore | unabhängige Reviews |
| firmware-analyst | explore | nicht P0-fokussiert |
| ui-ux-designer | explore | nicht P0-fokussiert |

Custom Agent-Namen sind **keine** aufrufbaren `subagent_type`-Werte. Rolle = Brief laden + Prompt.

---

## CYCLE2-ORCH-1 – Task Queue + Orchestrierung

| Feld | Wert |
|------|------|
| ID | CYCLE2-ORCH-1 |
| Priorität | P0 |
| Agent | project-manager |
| Abhängigkeiten | — |
| Status | DONE |
| Akzeptanz | `AGENT_TASK_QUEUE.md` existiert; Bridging dokumentiert; Überlapp-Timer gestoppt |
| Testergebnis | n/a (Docs) |
| Branch/Commit | `cursor/multi-agent-system-b100` |
| Review | Parent OK |

---

## P0-1 – BLE Central Ownership

| Feld | Wert |
|------|------|
| ID | P0-1 |
| Priorität | P0 |
| Agent (Impl) | Parent + bluetooth-specialist Brief (kein separater Task — Shared `BleClient`) |
| Agent (Review) | qa-security |
| Abhängigkeiten | CYCLE2-ORCH-1 |
| Status | REVIEW |
| Akzeptanz | Lease/Mutex; sekundäre Centrals blockiert während BleClient-Exklusiv; Tests |
| Testergebnis | `BLECentralCoordinatorTests` geschrieben; **nicht** auf Linux ausgeführt |
| Branch/Commit | `7d33c39` |
| Review | pending |

---

## P0-2 – Enc2 Session Lifecycle

| Feld | Wert |
|------|------|
| ID | P0-2 |
| Priorität | P0 |
| Agent (Impl) | Parent + bluetooth-specialist Brief |
| Agent (Review) | qa-security |
| Abhängigkeiten | P0-1 |
| Status | REVIEW |
| Akzeptanz | Handshake setzt alive; Reset/Disconnect invalidiert; kein Dump-Reuse ohne Handshake |
| Testergebnis | `Enc2SessionLifecycleTests` geschrieben; **nicht** auf Linux ausgeführt |
| Branch/Commit | `7d33c39` |
| Review | pending |

---

## P0-3 – Pack Integrity

| Feld | Wert |
|------|------|
| ID | P0-3 |
| Priorität | P0 |
| Agent (Impl) | forensic-expert → `generalPurpose` @ worktree `/tmp/sc-p03` |
| Agent (Review) | qa-security |
| Abhängigkeiten | CYCLE2-ORCH-1 |
| Status | REVIEW |
| Akzeptanz | Manifest SHA-256; verify; sealed after save/ensurePack |
| Testergebnis | `PackIntegrityTests` geschrieben; **nicht** auf Linux ausgeführt |
| Branch/Commit | merged `0610023` via `e8a988d` |
| Review | pending |

---

## P0-4 – Write-Disable Gate

| Feld | Wert |
|------|------|
| ID | P0-4 |
| Priorität | P0 |
| Agent (Impl) | ios-developer + bluetooth-specialist → `generalPurpose` @ `/tmp/sc-p04` |
| Agent (Review) | qa-security |
| Abhängigkeiten | CYCLE2-ORCH-1 |
| Status | REVIEW |
| Akzeptanz | Default-deny; Allowlist Auth/Identify/Capability; manipulation hard-false |
| Testergebnis | `BleWriteGateTests` geschrieben; **nicht** auf Linux ausgeführt |
| Branch/Commit | merged `7d3e30d` |
| Review | pending |

---

## Abgeschlossen (nicht erneut implementieren)

| ID | Status | Commit |
|----|--------|--------|
| CYCLE1-AGENTS | DONE | `cdd4d97` |
| CYCLE1-DOCS | DONE | `cdd4d97` |
| CYCLE1-REVIEW | DONE | Parallel explore → Roadmap |
| CYCLE2-ORCH-1 | DONE | Task Queue + Timer-Lock |

---

## Cycle Lock

```
cycle_id: 2
owner_run: multi-agent-cycle-2
branch: cursor/multi-agent-system-b100
overlapping_autonomy_timer: unsubscribed (scootercheck-autonomous-next)
zwischenbericht_timer: scootercheck-4h-zwischenbericht (active)
worktrees: /tmp/sc-p03 (pack), /tmp/sc-p04 (write-gate)
```
