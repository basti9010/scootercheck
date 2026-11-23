# Cycle 11 AGENT D – iOS Serverdiagnose

**Stand:** 2026-11-23  
**Base:** `cursor/server-diagnostics-c11-b100`  
**Branch:** `cursor/ios-server-diagnostics-b100`

## Goal

Settings → Firmwareanalyse → Serverdiagnose UI with Server / TEA / Ghidra / Worker grades, refresh, admin-only selftest, last selftest, export stub. Extend `FirmwareServerAnalysisClient` for `/v1/diagnostics/*` (404-tolerant until PM wires routes).

## UI entry path

1. Side menu → **Einstellungen** (`SettingsView`)
2. Section **Firmwareanalyse** (URL, API-Token, Admin-API-Token, LLM toggle)
3. Row **Serverdiagnose** → `FirmwareServerDiagnosticsView`

## Client / API

| Method | Path | Notes |
|--------|------|-------|
| `diagnosticsStatus()` | `GET /v1/diagnostics/status` | On 404 → map `GET /health` via `FirmwareDiagnosticsStatusMapper` (flags ≠ VERIFIED) |
| `diagnosticsStartSelftest()` | `POST /v1/diagnostics/selftest` | Admin token required; 404 → `routeNotAvailable` |
| `diagnosticsLastSelftest()` | `GET /v1/diagnostics/selftest/latest` | 404 → graceful message |
| `diagnosticsReportStub(...)` | `GET /v1/diagnostics/report` | Falls back to local JSON stub |

Admin gate: `AppSettings.firmwareAnalysisAdminAPIToken` / `client.isDiagnosticsAdmin` — **shared API token alone is not admin**.

## Grades

`CONFIGURED` · `AVAILABLE` · `VERIFIED` · `END_TO_END_VERIFIED` · `FAILED` · `UNKNOWN` · `NOT_CONFIGURED` · `ROUTE_MISSING`  

Colors via `FirmwareDiagnosticsGrade.color`. `/health` flags map at most to `CONFIGURED` / `AVAILABLE` — never `VERIFIED`.

## Files added

| File | Role |
|------|------|
| `FirmwareForensics/FirmwareDiagnosticsModels.swift` | Grades, status/selftest Codable, `/health` mapper |
| `FirmwareForensics/FirmwareServerDiagnosticsView.swift` | Serverdiagnose UI |
| `ScooterCheckTests/FirmwareDiagnosticsGradeTests.swift` | Grade parse + mapping + admin gate |
| `research/cycle11/agent_d/REPORT_IOS_DIAGNOSTICS.md` | This report |

## Files modified

| File | Change |
|------|--------|
| `FirmwareServerAnalysisClient.swift` | Diagnostics methods, admin token, 404 handling |
| `AppSettings.swift` | `firmwareAnalysisAdminAPIToken` + `isFirmwareDiagnosticsAdmin` |
| `SettingsView.swift` | Firmwareanalyse section + NavigationLink Serverdiagnose |
| `ScooterCheck.xcodeproj/project.pbxproj` | Wire new sources + tests |

## Untouched (no regression)

- `Correlation/CrossSourceCorrelator.swift` / CrossSource models / tests
- P0 BLE paths (`BleClient`, Radar, Signal-Finder)

## Test names

- `testParseConfiguredAvailableVerifiedFailedUnknown`
- `testParseEndToEndAndNotConfiguredAliases`
- `testGradeTokensAreUppercaseWireValues`
- `testGradeLabelsAreNonEmptyGerman`
- `testWorkerHealthMapsConfiguredFlagsNotVerified`
- `testWorkerHealthFailedWhenOkFalse`
- `testWorkerHealthTeaNotConfigured`
- `testNormalizedComponentsAlwaysFourRows`
- `testDiagnosticsAdminRequiresDedicatedAdminToken`
- `testGradeColorMappingCoversAllCases`

## Residual

1. `/v1/diagnostics/*` not in `app.py` yet — PM merge after Agents A–C; iOS falls back to `/health`.
2. AuthSession JWT admin role not on this lineage — dedicated Admin-API-Token field only.
3. XCTest not executed on Linux agent image — Codemagic CI expected.
4. Live E2E selftest against prod **not** run (policy: no prod admin without Freigabe).

## Epistemic

| Item | Grade |
|------|-------|
| UI + client code present | IMPLEMENTED |
| Grade unit tests authored | IMPLEMENTED |
| Live `/v1/diagnostics` E2E | ROUTE_MISSING until PM |
| CrossSource / BLE untouched | VERIFIED (diff scope) |
