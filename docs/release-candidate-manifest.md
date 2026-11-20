# ScooterCheck — Release Candidate Manifest

**Status:** candidate for staging / production *review* (not an automatic release)  
**Branch:** `cursor/firmware-phase-234-release-hardening-b100` (PR #100)  
**Base:** `cursor/firmware-phase-233-quality-b100` (PR #99)  
**Stack:** PR #85 … #100 (16 PRs; base of stack = `cursor/backend-auth-b100`)

> No version number or production release is declared by this document.  
> Production deploy requires explicit human approval after gates pass.

## Release commit

Tip of `cursor/firmware-phase-234-release-hardening-b100` (verify with `git rev-parse`).

At document update time: `764adbf8e600c5fe44c26eaf172a860ed0843703`  
(PDF artifact recovery + XCTAttachment + simctl/xcresult export).

## PR stack

| PR | Head | Base |
|----|------|------|
| #85 | cursor/forensik-phase1-reliability-b100 | cursor/backend-auth-b100 |
| #86 | feature/firmware-forensics-phase2 | …phase1… |
| #87–#100 | phase-22c … phase-234 | previous head |

Integration simulation: merge tip #100 onto `origin/cursor/backend-auth-b100` in a disposable worktree → **clean merge**, 54 commits ahead of stack base, key modules present.

## Contained capabilities

- Ghidra headless ARM/Thumb, callgraph, dataflow export (schema v2 parameter quality)
- Semantic data flow + activation forensics + evidence graph (static; no unlock sequences)
- Function matching / FunctionDiff / FSM / input behavior
- JWT job ownership + artifact authorization (safe defaults)
- iOS deep-analysis models, PDFKit forensic reports, Keychain JWT
- CI split: `ios-unit-tests.yml` vs `testflight.yml`
- PDF release validation: 6 synthetic reports + previews + host export script

## Security requirements

- `JWT_SECRET` shared with ScooterCheck auth
- `ADMIN_API_TOKEN` set; `API_TOKEN_GRANTS_ADMIN=0`; `TRUST_API_TOKEN_CLIENT_ID=0`
- Do not rotate production secrets via rollout script
- Do not modify `/var/lib/scootercheck` jobs/catalogs in dry-run

## Test evidence

| Area | Result |
|------|--------|
| Python | 280 passed, 5 skipped, 0 failed |
| Parameter GT | exactParameterAccuracy **90%**; acceptedOrAmbiguousRate 100% (allowUnknown) |
| Ground truth A–G | C–E P=1.0 R=0.6842; F TP=13/R=0.6842 (FP=0); documented |
| JWT / ownership | phase22h2 / 232 / 233 / api_auth_security green |
| Deploy dry-run | `CONFIRM_PROD_DEPLOY=NO` OK |
| Git sim | clean merge tip→backend-auth base |
| iOS / PDF / TestFlight | see CI on tip SHA (must be green + artifact downloadable) |

## Staging

**STAGING_NOT_AVAILABLE** in this agent environment: no isolated `/opt` staging tree, no separate JWT staging secrets wired here. Staging plan only — do not treat production Hetzner as staging.

## Known limitations

- Opaque CC parameter off-by-one (exact 90%)
- Second annotator unavailable
- F-variant recall drift vs older docs (FP still 0)
- Visual PDF layout review: VISUAL_REVIEW_PENDING until humans inspect artifact PNGs
- Tip TestFlight / PDF artifact upload must be confirmed on the tip SHA

## Rollback

1. Keep previous remote app tree backup  
2. Redeploy prior known-good commit only with explicit approval  
3. Never delete `/var/lib/scootercheck` during rollback  
4. Revert TestFlight client to prior build if needed  
