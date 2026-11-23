# ScooterCheck – Agent Task Queue

**Cycle:** 3 (Quality & Autonomy / macOS CI)  
**Branch:** `cursor/multi-agent-system-b100`  
**Lock:** `CYCLE3_CI_ACTIVE` — keine parallelen Autonomie-Zyklen  
**Zuletzt gelesen:** 2026-11-23 (Europe/Berlin)

Statuswerte: `BACKLOG` | `READY` | `IN_PROGRESS` | `REVIEW` | `BLOCKED` | `DONE`

**P0-Verifikation:** Code implementiert, aber **UNVERIFIED** bis macOS CI grün meldet.

---

## Orchestrierung

| Custom Agent | Cloud Task | Cycle 3 |
|--------------|------------|---------|
| project-manager | Parent | CI-Setup, Fix-Loop (max 3) |
| ios-developer | generalPurpose | Scheme/CI Fixes |
| qa-security | explore | Review nach CI |
| bluetooth / forensic | generalPurpose | nur bei CI-Fail in ihrem Scope |

---

## CYCLE3-CI-1 – macOS XCTest Workflow

| Feld | Wert |
|------|------|
| ID | CYCLE3-CI-1 |
| Priorität | P0 |
| Agent | project-manager / ios-developer |
| Status | IN_PROGRESS |
| Akzeptanz | Workflow `ios-unit-tests.yml`; Scheme mit Testables; Docs; Trigger auf PR/Push |
| Testergebnis | Run `45133543772` **failure** — Xcode 16.2 ohne iOS 18.2 Simulator-Runtime |
| Branch/Commit | `0fed874` → Fix attempt 1 |
| Review | — |

---

## CYCLE3-CI-2 – P0 Verification via CI

| Feld | Wert |
|------|------|
| ID | CYCLE3-CI-2 |
| Priorität | P0 |
| Agent | qa-security + Parent |
| Abhängigkeiten | CYCLE3-CI-1 |
| Status | IN_PROGRESS |
| Akzeptanz | CI führt BLECentralCoordinator / Enc2 / PackIntegrity / BleWriteGate / WriteDisableRegression Tests aus; Ergebnis dokumentiert |
| Testergebnis | UNVERIFIED — Build failed before XCTest |
| Fix-Attempts | 2 / 3 (1: Xcode dest; 2: Swift 6 arg order in AttributionEngineTests) |

---

## CI-FIX-1 – Simulator destination / Xcode match

| Feld | Wert |
|------|------|
| ID | CI-FIX-1 |
| Priorität | P0 |
| Agent | project-manager |
| Status | IN_PROGRESS |
| Root cause | Xcode 16.2 + `name=iPhone 16` → OS:latest, aber Runtime 18.2 fehlt; Runner hat 18.5+/26.x |
| Fix | Prefer Xcode 26.x with visible destinations; else download platform; pin destination by UDID |
| Attempt | 2 / 3 |

---

## CYCLE3-REG-1 – Write-Disable Regression Tests

| Feld | Wert |
|------|------|
| ID | CYCLE3-REG-1 |
| Priorität | P0 |
| Agent | ios-developer / Parent |
| Status | REVIEW |
| Akzeptanz | `WriteDisableRegressionTests` im Target; SoftUnlock observational; Navee forbidden; Gate closed |
| Testergebnis | UNVERIFIED (wartet CI) |

---

## P0 (Cycle 2) – Implementiert, Verifikation ausstehend

| ID | Code | CI-Status |
|----|------|-----------|
| P0-1 BLE Central | DONE code | UNVERIFIED |
| P0-2 Enc2 Lifecycle | DONE code | UNVERIFIED |
| P0-3 Pack Integrity | DONE code | UNVERIFIED |
| P0-4 Write Gate | DONE code | UNVERIFIED |
| CYCLE2-ORCH-1 | DONE | n/a |

---

## P1 – BACKLOG (erst nach grüner P0-CI)

| ID | Status | Hinweis |
|----|--------|---------|
| P1-INV Investigation Flow 1.1 | BACKLOG | nach CYCLE3-CI-2 DONE |
| P1-CV ContentView modularisieren | BACKLOG | |
| P1-CORR BLE/Firmware Korrelation | BACKLOG | |
| P1-REG weitere Regressionstests | BACKLOG | |

---

## Abgeschlossen

| ID | Commit |
|----|--------|
| CYCLE1-* | `cdd4d97` |
| CYCLE2 P0 code | `7c8ecfa` |

---

## Cycle Lock

```
cycle_id: 3
owner: quality-autonomy-upgrade
branch: cursor/multi-agent-system-b100
overlapping_cycle2_p1_timer: unsubscribed
ci_fix_max_attempts: 3
zwischenbericht_timer: scootercheck-4h-zwischenbericht (may still be active)
```


## CI-FIX-2 – Swift 6 argument order in AttributionEngineTests

| Feld | Wert |
|------|------|
| ID | CI-FIX-2 |
| Status | IN_PROGRESS |
| Root cause | Xcode 26 / Swift 6: labeled args must match declaration order (`modMatch` vs `interpreted`) |
| Fix | Reorder `fact(...)` helper + call sites |
| Attempt | 2 / 3 |
