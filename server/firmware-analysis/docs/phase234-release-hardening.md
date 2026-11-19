# Phase 2.3.4 — Release Hardening

## CI architecture

- `ios-unit-tests.yml` — PR/push unit tests on `ios/ScooterCheck/**` (no TestFlight upload).
- `testflight.yml` — distribution allowlist only (authorized branches); unit tests then Fastlane beta.

## Parameter recovery

`ExportDataFlowSummary.java` (schemaVersion 2):

- `DEFAULT` + `getParameterCount()==0` → `parameterCount: null`, `UNKNOWN_PARAMETER_COUNT`
- Optional HighFunction recovery (`GHIDRA_DATAFLOW_DECOMP_PARAMS`, budget)
- Qualities: `CONFIRMED_ZERO_PARAMETERS` | `RECOVERED_PARAMETER_COUNT` | `UNKNOWN_PARAMETER_COUNT` | `PARTIAL_SIGNATURE`

`semantic_dataflow.py` reinterprets legacy exports that wrote `0` without quality as UNKNOWN.

## Controlled GT

`testdata/phase234/param_gt/` — 10 ARM/Thumb functions; live Ghidra 12.2 + JDK 25.

## Blind annotation

`testdata/phase234/annotation/` — auto labels withheld until after manual labels; `SECOND_ANNOTATOR_NOT_AVAILABLE`.
