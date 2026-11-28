# P0 Auth — Final Validation & TestFlight Readiness

**Stand:** 2026-11-28 (Europe/Berlin)  
**PR:** #117 · Branch `cursor/p0-auth-recovery-b100`

## CI

| Check | Status | Epistemic |
|-------|--------|-----------|
| Vor Validierung | keine Workflow-Runs auf Branch (fehlte `ios-unit-tests.yml`) | **CONFIRMED** |
| Nach Validierung | `ios-unit-tests.yml` ergänzt; PR-Push triggert macOS XCTest | **IMPLEMENTED** — Ergebnis nach CI-Lauf |
| Backend pytest (Agent-VM) | **22 passed** | **CONFIRMED** |
| XCTest authored (Auth*) | **46** `test*` Methoden in Auth*/AppFeatureFlags | **CONFIRMED** count |
| XCTest executed | Linux Agent: kein Xcode → **NOT VERIFIED** bis macOS CI grün | |

## Security

| Item | Status |
|------|--------|
| DemoAuthBootstrap / gate-off on #117 | absent + regression tests **CONFIRMED** |
| Hardcoded demo passwords on #117 | absent **CONFIRMED** |
| JWT in Keychain | **IMPLEMENTED** |
| Klartext-JWT UserDefaults | migration clears legacy key **IMPLEMENTED** |
| Klartext-Login-Passwort | not stored **CONFIRMED** (code) |
| Role separation | DB `require_admin`; forged JWT role ineffective **TESTED** |
| Insecure default secrets | **fail-closed** at startup **IMPLEMENTED** + pytest |
| PR #114 credentials | still on sibling branch — **rotate** (ops); do not merge |

## TestFlight readiness

| Item | Status |
|------|--------|
| Secure login only (#117) | **CONFIRMED** (no #114 bypass) |
| Auth sources/tests in pbxproj | **CONFIRMED** |
| `testflight.yml` includes `cursor/p0-auth-recovery-b100` | **IMPLEMENTED** |
| Build upload | starts on push when paths match — monitor Actions |
| Device checklist | `IPHONE_TESTPLAN.md` — all **NOT VERIFIED** |

## User actions still required

1. Wait for macOS **iOS Unit Tests** green on #117  
2. Install TestFlight build; run 10-step checklist  
3. Freigabe before any **prod** auth-server deploy (fail-closed needs real `JWT_SECRET`/`ADMIN_PASSWORD` already in `/opt/scootercheck/.env` — verify before restart)  
4. Rotate PR #114 demo credentials; close/reject #114  

## Residual risks

- Device E2E **NOT VERIFIED** → not END_TO_END_VERIFIED  
- No token denylist until Freigabe  
- Prod Auth `code` field needs backend deploy (separate Freigabe)  
- TestFlight signing/secrets failures possible (ops)  
