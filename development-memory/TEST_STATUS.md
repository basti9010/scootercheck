# Test Status

**Inventory date:** 2026-11-28  
**Rule:** Never claim tests passed without CI artifact or local macOS/`pytest` output. This memory is derived.

## iOS XCTest

| Item | Value |
|------|-------|
| Location | `ios/ScooterCheck/ScooterCheckTests/` |
| Suites (files) | ~48 |
| `test*` methods (rg count) | ~395 |
| Workflow | `.github/workflows/ios-unit-tests.yml` (macos-15) |
| On Linux agents | **Cannot run** → UNVERIFIED locally |
| Historical note (docs) | Multi-agent tip once reported CI green `45245015142` @ `a2c9329` (350/0) — **historical**; re-verify on current SHA before claiming |

### Notable suites (present)

P0-oriented: `BLECentralCoordinatorTests`, `Enc2SessionLifecycleTests`, `PackIntegrityTests`, `BleWriteGateTests`, `WriteDisableRegressionTests`  
P1-oriented: `InvestigationStoreTests`, `InvestigationFlowLogicTests`, `InvestigationCombinedPDFTests`, `CrossSourceCorrelatorTests`  
Plus BLE search/radar/AR, firmware ZIP, evidence, pedelec, universal diagnosis, FAQ, etc.

## Server pytest

| Item | Value |
|------|-------|
| Location | `server/firmware-analysis/test_*.py` (~44 modules) + `testdata/` |
| Workflow | `.github/workflows/server-firmware-tests.yml` |
| Focus subset (workflow) | auth / path / diagnostics / zip / deploy-smoke |
| Cycle 12 local note (docs) | ~46 deploy/manifest/smoke tests OK on agent machine — treat as **TESTED** for those modules when re-run confirms |

## AI Bridge pytest (v2)

| Item | Value |
|------|-------|
| Location | `services/ai-bridge/tests` + `mcp/tests` |
| Local 2026-11-28 | **52 passed** on `cursor/ai-bridge-v2-b100` |
| Live Cursor | **NOT VERIFIED** — `BLOCKED_MISSING_CREDENTIAL` |
| ChatGPT MCP | **NOT VERIFIED** |

## Backend pytest

| Item | Value |
|------|-------|
| Sources on this checkout | **Absent** |
| PR #117 note | Body claims backend pytest 22 passed — verify on that branch’s CI, not this tip |

## PR #117 / device

- Owner: device login tested (UX).  
- CI / merge: **verify independently** (scheme/TestAction history noted in PR body).  
- Do not copy “all green” into this file without a run id.

## Labels cheat sheet

| Label | Meaning |
|-------|---------|
| IMPLEMENTED | Code present |
| TESTED | Automated tests executed successfully (cite run) |
| END_TO_END_VERIFIED | Full path verified with Freigabe / device+server |
| NOT VERIFIED | No proof yet |
| INCOMPLETE | Known missing capability (e.g. decrypt) |
