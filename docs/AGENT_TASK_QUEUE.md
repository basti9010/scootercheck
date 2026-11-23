# ScooterCheck – Agent Task Queue

**Cycle:** 4 (CI Recovery & P0 Verification)  
**Branch:** `cursor/multi-agent-system-b100`  
**Lock:** `CYCLE4_CI_RECOVERY_ACTIVE`  
**Zuletzt gelesen:** 2026-11-23 (Europe/Berlin)

Statuswerte: `BACKLOG` | `READY` | `IN_PROGRESS` | `REVIEW` | `BLOCKED` | `DONE`

Cycle 3 Fix-Budget (3/3) abgeschlossen. Cycle 4: **neues** Budget max **3** Auto-Fix-Durchläufe.

---

## CYCLE4-ORCH-1 – Bestandaufnahme

| Feld | Wert |
|------|------|
| ID | CYCLE4-ORCH-1 |
| Status | DONE |
| CI evidence | Runs `45135136966`, `45163223956` (sha `31a0aed` / `abccc47`) |
| Errors | LiveTelemetryTests:30 Double?; BLESearchMotionCoreTests:308/327/332/365 Double?; BLEWatchRadarTests:64 missing `minHitsForAlarm` |
| Classification | API/Optional typing (XCTAssertEqual accuracy needs Double); outdated test API member |

---

## CYCLE4-A – LiveTelemetryTests

| Feld | Wert |
|------|------|
| ID | CYCLE4-A |
| Status | IN_PROGRESS |
| Agent | explore `bc-3326a84a…` + Parent implement |
| Cause | `decodeBmsTempC` → `Double?`; accuracy overload needs `Double` |
| Fix | unwrap before accuracy assert |

---

## CYCLE4-B – BLESearchMotionCoreTests

| Feld | Wert |
|------|------|
| ID | CYCLE4-B |
| Status | IN_PROGRESS |
| Agent | explore `bc-f82614c4…` + Parent implement |
| Cause | `measuredRssi` → `Double?` |
| Fix | unwrap / `??` before accuracy assert |

---

## CYCLE4-C – BLEWatchRadarTests

| Feld | Wert |
|------|------|
| ID | CYCLE4-C |
| Status | IN_PROGRESS |
| Agent | explore `bc-9c9544a6…` + Parent implement |
| Cause | `minHitsForAlarm` renamed → Foreground/Background |
| Fix | assert `minHitsForAlarmForeground` (>=2) + background constant |

---

## CYCLE4-CI-1 – Push & verify

| Feld | Wert |
|------|------|
| ID | CYCLE4-CI-1 |
| Status | READY |
| Fix-Attempts | 0 / 3 |
| Goal | build-for-testing OK + test-without-building executes XCTest |

---

## CYCLE4-P0 – P0 suite evidence

| Feld | Wert |
|------|------|
| ID | CYCLE4-P0 |
| Status | BACKLOG |
| Suites | BLECentralCoordinator / Enc2SessionLifecycle / PackIntegrity / BleWriteGate |
| Need | executed counts (pass/fail/skip), not compile-only |

---

## CYCLE4-QA – Independent review

| Feld | Wert |
|------|------|
| ID | CYCLE4-QA |
| Status | BACKLOG |

---

## P0 Code (Cycle 2) — CI-Verifikation

| ID | Code | CI |
|----|------|-----|
| P0-1 BLE Central | DONE | UNVERIFIED (Cycle 4) |
| P0-2 Enc2 Lifecycle | DONE | UNVERIFIED |
| P0-3 Pack Integrity | DONE | UNVERIFIED |
| P0-4 Write Gate | DONE | UNVERIFIED |

---

## P1 – gesperrt bis CYCLE4-P0 DONE

| ID | Status |
|----|--------|
| P1-INV Investigation Flow 1.1 | BACKLOG |
| P1-CV ContentView modularisieren | BACKLOG |
| P1-CORR BLE/Firmware Korrelation | BACKLOG |

---

## Cycle Lock

```
cycle_id: 4
ci_fix_attempts: 0/3
status: ACTIVE
branch: cursor/multi-agent-system-b100
prior_cycle_3: BLOCKED 3/3 exhausted — closed
```
