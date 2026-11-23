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
| bluetooth-specialist | generalPurpose (+ Brief) | P0-1, P0-2 Implementierung |
| forensic-expert | generalPurpose (+ Brief) | P0-3 Implementierung |
| ios-developer | generalPurpose (+ Brief) | P0-4 + iOS Integration |
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
| Status | IN_PROGRESS |
| Akzeptanz | `AGENT_TASK_QUEUE.md` existiert; Agents dokumentieren Bridging; Überlapp-Timer gestoppt |
| Testergebnis | n/a (Docs) |
| Branch/Commit | `cursor/multi-agent-system-b100` |
| Review | Parent |

---

## P0-1 – BLE Central Ownership

| Feld | Wert |
|------|------|
| ID | P0-1 |
| Priorität | P0 |
| Agent (Impl) | bluetooth-specialist → `generalPurpose` |
| Agent (Review) | qa-security → `security-review`/`explore` |
| Abhängigkeiten | CYCLE2-ORCH-1 |
| Status | READY |
| Akzeptanz | Sekundäre Centrals (GATT Deep / Capability) dürfen nicht unkontrolliert parallel zu BleClient connecten; Mutex/Lease oder Serialisierung; bestehende Scan/Dump/Find bleiben nutzbar; Unit-Tests wo möglich |
| Testergebnis | — |
| Branch/Commit | — |
| Review | — |

---

## P0-2 – Enc2 Session Lifecycle

| Feld | Wert |
|------|------|
| ID | P0-2 |
| Priorität | P0 |
| Agent (Impl) | bluetooth-specialist → `generalPurpose` |
| Agent (Review) | qa-security |
| Abhängigkeiten | P0-1 (geteilt: `BleClient.swift`) — sequentiell nach oder mit P0-1 koordinieren |
| Status | READY |
| Akzeptanz | Disconnect/`resetSession` invalidiert crypto/auth; kein Dump-Reuse ohne Handshake; Tests für Session-Flags |
| Testergebnis | — |
| Branch/Commit | — |
| Review | — |

---

## P0-3 – Pack Integrity

| Feld | Wert |
|------|------|
| ID | P0-3 |
| Priorität | P0 |
| Agent (Impl) | forensic-expert → `generalPurpose` |
| Agent (Review) | qa-security |
| Abhängigkeiten | CYCLE2-ORCH-1 (unabhängig von P0-1/2) |
| Status | REVIEW |
| Akzeptanz | Manifest mit SHA-256 über kanonische Artefakte; Verifikation; PDF/JSON Metadaten; keine stillen Destructive Overwrites für sealed packs; Tests |
| Testergebnis | Unit-Tests `PackIntegrityTests` (hash stability, mismatch, missing); xcodebuild auf Linux nicht ausführbar — CI/macOS |
| Branch/Commit | `cursor/p0-pack-integrity-b100` @ 0610023c3ea58076878210382e7a5df57c104f9e |
| Review | — |

---

## P0-4 – Write-Disable Gate

| Feld | Wert |
|------|------|
| ID | P0-4 |
| Priorität | P0 |
| Agent (Impl) | ios-developer + bluetooth-specialist → `generalPurpose` |
| Agent (Review) | qa-security |
| Abhängigkeiten | CYCLE2-ORCH-1 (unabhängig von Pack; koordinate mit BleClient-Writes) |
| Status | READY |
| Akzeptanz | Zentraler Gate (default deny) für Fahrzeug-Schreibops; Allowlist nur Auth/Identify/Capability; Tests; keine neuen Manipulation-Pfade |
| Testergebnis | — |
| Branch/Commit | — |
| Review | — |

---

## Abgeschlossen (nicht erneut implementieren)

| ID | Status | Commit |
|----|--------|--------|
| CYCLE1-AGENTS | DONE | `cdd4d97` – sieben Agent-Configs |
| CYCLE1-DOCS | DONE | `cdd4d97` – PROJECT_STATUS/ARCHITECTURE/ROADMAP/AGENT_PROGRESS/OPEN_ISSUES |
| CYCLE1-REVIEW | DONE | Parallel explore Reviews → Roadmap |

---

## Cycle Lock

```
cycle_id: 2
owner_run: multi-agent-cycle-2
branch: cursor/multi-agent-system-b100
overlapping_autonomy_timer: unsubscribed (scootercheck-autonomous-next)
zwischenbericht_timer: scootercheck-4h-zwischenbericht (active)
```
