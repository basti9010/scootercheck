# ScooterCheck — Release Candidate Manifest

**Status:** candidate for staging / production *review* (not an automatic release)  
**Branch:** `cursor/firmware-phase-234-release-hardening-b100` (PR #100)  
**Base:** `cursor/firmware-phase-233-quality-b100` (PR #99)  
**Stack:** PR #85 … #100 (firmware forensics stack)

> No version number or production release is declared by this document.  
> Production deploy requires explicit human approval after gates pass.

## Release commit

`6d82408d65abee213b7a314a4f46a359bdb77e50` on `cursor/firmware-phase-234-release-hardening-b100`

```bash
git rev-parse cursor/firmware-phase-234-release-hardening-b100
```

## Contained capabilities (stack)

- Ghidra headless ARM/Thumb function analysis, callgraph, dataflow export
- Semantic data flow + parameter quality (`UNKNOWN` / `CONFIRMED_ZERO` / `RECOVERED` / `PARTIAL`)
- Function matching / FunctionDiff / FSM / input behavior
- Activation forensics + evidence graph (static; no unlock-sequence reconstruction)
- JWT job ownership + artifact authorization
- iOS deep-analysis models, PDFKit forensic reports, Keychain JWT session
- CI split: `ios-unit-tests.yml` (compile/test/PDF) vs `testflight.yml` (signed distribution)

## New / updated backend modules (relative to pre-forensics baseline)

- `semantic_dataflow.py`, `activation_forensics.py`, `analysis_profile.py`, …
- Ghidra: `ExportDataFlowSummary.java`, `ExportFunctionAnalysis.java`, `ExportCallGraph.java`, `SeedCortexMEntryPoints.java`, …
- Auth: `job_auth.py` with safe defaults `API_TOKEN_GRANTS_ADMIN=0`, `TRUST_API_TOKEN_CLIENT_ID=0`

## New / updated iOS models

- `FirmwareDeepAnalysisModels.swift` — dataflow quality metrics including:
  - `exactParameterAccuracy`
  - `acceptedOrAmbiguousRate`
  - `unknownParameterRate` / `partialSignatureRate` / `recoveredParameterCoverage`
- `FirmwareForensicPDF.swift` — PDF rendering of separated GT metrics
- `FirmwareForensicPDFReleaseValidationTests.swift` — six synthetic PDFKit reports + page previews

## Configuration / security requirements

- `JWT_SECRET` shared with ScooterCheck auth
- `ADMIN_API_TOKEN` set; shared `API_TOKEN` must not grant admin by default
- Do not rotate production secrets via rollout script
- Reference catalogs and job stores under `/var/lib/scootercheck` must not be modified by dry-run

## Test evidence (final integration)

| Area | Result |
|------|--------|
| Python full discovery | 280 passed, 5 skipped, 0 failed |
| Parameter GT (10 fn) | exactParameterAccuracy **90%** (9 exact, 1 wrong/ambiguous opaque_cc 3≠2); acceptedOrAmbiguousRate 100% with documented `allowUnknown` |
| Ground truth A–G (42) | Re-run OK; C–E P=1.0 R=0.6842; F now TP=13/R=0.6842 (was documented TP=14 — FP still 0; see phase233-quality.md) |
| JWT / ownership | `test_phase233_jwt_artifacts`, `test_phase232_jwt_dataflow`, `test_phase22h2_jwt_e2e` |
| Deploy dry-run | `CONFIRM_PROD_DEPLOY=NO ./deploy/phase1-rollout.sh` OK; no prod writes |
| iOS / PDFKit | Exercised on GitHub Actions `macos-15` via `ios-unit-tests.yml` + artifact `pdf-release-validation` |

## Known limitations

- Opaque calling-convention case remains inexact (got 3, expected 2) — correctly counted as non-exact
- Second annotator not available for blind dual-annotation kappa
- PDF layout overlap checks are assisted by page preview artifacts; full visual QA is manual
- Stacked PRs #85–#100 share commits; merge only bottom-up, no squash across stack without plan
- No automatic production deploy

## Rollback hints

1. Keep previous remote app tree / systemd unit backup from last successful deploy
2. Redeploy prior known-good commit with `CONFIRM_PROD_DEPLOY=YES` only after explicit approval
3. Do not delete `/var/lib/scootercheck` jobs or catalogs during rollback
4. Revert iOS TestFlight to prior build number if client regression appears

## Staging checklist (prepared, not executed)

1. Pin release commit SHA  
2. Confirm CI green on that SHA  
3. Build backend artifact from dry-run file list  
4. Isolated staging `.env` (separate JWT secrets, work dirs)  
5. Start service → healthcheck  
6. Synthetic firmware job → Ghidra / semantic / activation artifacts  
7. Owner JWT 200; foreign JWT 404; invalid/expired 401  
8. Rollback drill on staging only  
