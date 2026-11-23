# Phase 2.2H — Integrationsmatrix (PR #85–#92)

Stand: Integrationsbranch `cursor/firmware-phase-22h-integration-b100` (basiert auf 2.2G `6ba8c78`).

| PR | Phase | Branch | Base | Head | Mergeable | CI (zuletzt) | Status |
|----|-------|--------|------|------|-----------|--------------|--------|
| #85 | Phase 1 | `cursor/forensik-phase1-reliability-b100` | `cursor/backend-auth-b100` | `0093deaf` | yes (unstable) | historisch FAILURE / stack | INTEGRATED_IN_DEVELOPMENT |
| #86 | Phase 2/2.2B | `feature/firmware-forensics-phase2` | #85 | `38cdb173` | yes (clean) | success | INTEGRATED_IN_DEVELOPMENT |
| #87 | Klartext-Skip | `cursor/plaintext-server-skip-b100` | #86 | `5607250a` | yes (clean) | success | INTEGRATED_IN_DEVELOPMENT |
| #88 | 2.2C | `cursor/firmware-phase-22c-b100` | #87 | `fdc8ee80` | yes (clean) | success | INTEGRATED_IN_DEVELOPMENT |
| #89 | 2.2D | `cursor/firmware-phase-22d-b100` | #88 | `3f93820e` | yes (clean) | success | INTEGRATED_IN_DEVELOPMENT |
| #90 | 2.2E | `cursor/firmware-phase-22e-b100` | #89 | `726d035a` | yes (clean) | success | INTEGRATED_IN_DEVELOPMENT |
| #91 | 2.2F | `cursor/firmware-phase-22f-b100` | #90 | `68268e41` | yes (clean) | success | INTEGRATED_IN_DEVELOPMENT |
| #92 | 2.2G | `cursor/firmware-phase-22g-b100` | #91 | `6ba8c787` | yes (unstable) | CI pending/in progress | INTEGRATED_IN_DEVELOPMENT |
| — | 2.2H | `cursor/firmware-phase-22h-integration-b100` | #92 | (dieser Branch) | — | nach Push | READY_FOR_MERGE (nach Gates) |

Keine automatischen Merges. Stack-Reihenfolge: #85 → … → #92 → #93 (2.2H).

## Komponenten → PR → Integrationsstatus

| Komponente | PRs | Status |
|------------|-----|--------|
| ZIP-Härtung / Ampel / PDF | #85 | INTEGRATED_IN_DEVELOPMENT |
| Ghidra SeedCortexM / Auth / Job-Ownership | #86 | INTEGRATED_IN_DEVELOPMENT |
| Klartext Decrypt-Skip | #87 | INTEGRATED_IN_DEVELOPMENT |
| Function Matching / Input Behavior | #88 | INTEGRATED_IN_DEVELOPMENT |
| FSM/Matching Qualität | #89 | INTEGRATED_IN_DEVELOPMENT |
| Referenzinventar / Completeness | #90 | INTEGRATED_IN_DEVELOPMENT |
| Callgraph / BLE / Catalog Batch / FSM Runtime | #91 | INTEGRATED_IN_DEVELOPMENT |
| Analyseprofil 2.2G.1 / Repro / BLE Confidence | #92 | INTEGRATED_IN_DEVELOPMENT |
| E2E / Auth default=0 / Staging / Ghidra-Arch-Gate | 2.2H | INCOMPLETE→PASS nach Tests |

## Bekannte Integrationskorrekturen in 2.2H

1. `API_TOKEN_GRANTS_ADMIN` Default `"0"`.
2. `process_job`: Container-Analyse schrieb in undefiniertes `result` (NameError → stille Ausnahme) — behoben via `container_meta` vor `deep_result`.
3. Ghidra-Skip wenn `ghidraImportAllowed is False`.
