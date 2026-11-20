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

Expected parameter counts: `0,1,2,3,4,2,1,2,1,2`  
Recovered: `0,1,2,3,4,2,1,2,1,3` (opaque_cc off-by-one)

Quality metrics (separated — do **not** conflate):

| Metric | Value |
|--------|------:|
| `exactParameterAccuracy` | **90%** (9/10) |
| `acceptedOrAmbiguousRate` | 100% (includes documented `allowUnknown` on opaque/incomplete) |
| `unknownParameterRate` | 0% |
| `partialSignatureRate` | 0% |
| `recoveredParameterCoverage` | 100% |

Legacy alias `recoveryAccuracyPercent` must equal `exactParameterAccuracy` (never report 100% exact when a wrong count exists).

## Blind annotation

`testdata/phase234/annotation/` — auto labels withheld until after manual labels; `SECOND_ANNOTATOR_NOT_AVAILABLE`.

## Final release integration

- `ios-unit-tests.yml` runs on all PRs/pushes touching `ios/ScooterCheck/**` (no branch allowlist; no signing secrets).
- PDFKit release validation writes six synthetic reports + page previews under `release-validation/pdf/` and uploads CI artifact `pdf-release-validation`.
- Manifest: `docs/release-candidate-manifest.md`.
