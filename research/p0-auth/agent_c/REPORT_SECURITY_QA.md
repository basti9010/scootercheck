# Agent C — Security & QA (P0 Auth Recovery)

**Branch:** `cursor/p0-auth-recovery-b100`  
**Stand:** 2026-11-28  
**Scope:** Security review, demo-bypass purge verification, test matrix, residual risks.  
**Epistemic:** CONFIRMED / HYPOTHESIS / INCOMPLETE as labeled.

---

## 1. Demo bypass purge

| Check | Result | Epistemic |
|------|--------|-----------|
| `DemoAuthBootstrap.swift` on **this** recovery branch | **Absent** | **CONFIRMED** |
| `AppFeatureFlags.authGateEnabled = false` on recovery | **Absent** (flag not present; `AuthGateView` is unconditional app root) | **CONFIRMED** |
| `ScooterCheckApp` calls demo bootstrap | **No** | **CONFIRMED** |
| Same artifacts on PR #114 `cursor/demo-skip-login-b100` | **Present** (`DemoAuthBootstrap.swift` + `authGateEnabled = false`) | **CONFIRMED** |
| Hardcoded demo credentials in PR #114 source | **Present** (two `auth.login` call sites; values **not** repeated here) | **CONFIRMED** |
| Password rotation after demo | Ops action still required if those accounts were real | **HYPOTHESIS** (validity unknown) |
| Do **not** merge PR #114 unchanged into productive line | Still recommended | **CONFIRMED** (policy) |

**Verdict:** Demo bypass is **fully purged from this recovery branch**. Regression coverage: `AuthSecurityRegressionTests`, `AppFeatureFlagsTests.testAuthGateNotDisabledViaFeatureFlag`, `research/p0-auth/agent_c/check_demo_bypass.py` (exit 0).

---

## 2. Security findings

| ID | Severity | Finding | Epistemic |
|----|----------|---------|-----------|
| C-01 | **High** (historical) | PR #114 shipped hardcoded admin/demo credentials + gate off | **CONFIRMED** on demo branch; **purged** here |
| C-02 | **Medium** | JWT not revoked on password change / disable — old Bearer works until `exp` (14d default). Pytest `test_password_change_does_not_revoke_existing_jwt` | **CONFIRMED** |
| C-03 | **Medium** | No refresh / logout / denylist / token version on server — re-login only after expiry | **CONFIRMED** |
| C-04 | **Medium** | `KeychainAuthTokenStore.saveToken` ignores `SecItemAdd` OSStatus; failed add + legacy UserDefaults cleared → silent token loss | **CONFIRMED** (code) |
| C-05 | **Medium** | Default `jwt_secret` / `admin_password` in `settings.py` if env unset — prod must override | **CONFIRMED** in code; live prod values **INCOMPLETE** |
| C-06 | **Low** | `firmwareAnalysisAPIToken` still in UserDefaults (separate from login JWT) | **CONFIRMED** |
| C-07 | **Low** | CORS `allow_origins=["*"]` with `allow_credentials=True` (browser quirk / misconfig risk) | **CONFIRMED** |
| C-08 | **Low** | `seed_admin()` re-promotes seed email to admin+active every startup | **CONFIRMED** |
| C-09 | **Info** | Auth user profile cache in UserDefaults (PII/role, not secret) — offline local unlock | **CONFIRMED** |
| C-10 | **Info** | UI Admin entry gated by `isAdmin`; API enforces `require_admin` + DB role (forged JWT `role` claim ignored) | **CONFIRMED** (pytest) |
| C-11 | **Info** | Pre-A: bootstrap cleared session on **any** error including network — **fixed** on this branch by Agent A | **CONFIRMED** |
| C-12 | **Info** | Session fixation via login: new JWT issued; no server-side session store to fixate | **CONFIRMED** (stateless JWT) |
| C-13 | **HYPOTHESIS** | Cached offline `isAdmin` could show Admin UI without network; API still 403 | Acceptable if UI failures handled |
| C-14 | **INCOMPLETE** | Original “login broken” root cause at demo disable time | unchanged |

### Keychain migration risks (Agent A)

| Risk | Notes | Epistemic |
|------|-------|-----------|
| One-shot UD → Keychain | Legacy key `scootercheck.auth.token` read once then removed | **CONFIRMED** |
| Accessibility | `AfterFirstUnlockThisDeviceOnly` — OK for background BLE; no iCloud sync | **CONFIRMED** |
| Dual-write race | Unlikely after A wired store exclusively through `AuthTokenStoring` | **HYPOTHESIS** low |
| SecItemAdd unchecked | See C-04 | **CONFIRMED** |
| Device Keychain behavior | Needs TestFlight / hardware | **INCOMPLETE** |

### Accidental auth bypass flags

| Path | Status |
|------|--------|
| `authGateEnabled=false` | Not on recovery tree |
| `#if DEBUG` login skip | Not found |
| Empty-token “guest” mode | Not found; `canUseApp` requires active user |

---

## 3. Test matrix

| Scenario | Coverage | Runner result |
|----------|----------|---------------|
| Login success | `AuthSessionStoreTests` + `test_login_success_admin_seed` | XCTest: **BLOCKED** (no Xcode); pytest: **PASS** |
| Login fail | Store + `invalid_credentials` pytest | same |
| Session restore | Store restore + Keychain migration unit | XCTest blocked |
| Expired / revoked clear | Store + `test_me_expired_token` | pytest PASS; XCTest blocked |
| Network ≠ logout | Store + policy + error mapper | XCTest blocked |
| Logout clears storage | Store | XCTest blocked |
| Offline local vs server | Policy + Store offline test | XCTest blocked |
| Admin vs user | Store `testAdminVsUserAccessFlags` + `test_auth_roles.py` | pytest PASS; XCTest blocked |
| Demo bypass absent | Regression XCTest + `check_demo_bypass.py` | Script **PASS**; XCTest blocked |
| Forged role claim | `test_forged_role_claim_ignored_for_admin` | **PASS** |
| Disabled user | `test_disabled_user_blocked_from_session_check` | **PASS** |
| No `/auth/refresh` | `test_refresh_endpoint_absent` | **PASS** |

### Commands run (this agent)

```text
python3 research/p0-auth/agent_c/check_demo_bypass.py   → OK
cd backend && python3 -m pytest tests/ -v               → 19 passed
xcodebuild / swift                                       → unavailable on Linux agent host
```

**XCTest blocker:** No `swift` / `xcodebuild` on this Cloud Agent VM. Auth XCTest suites are authored and in the Xcode target; run on macOS CI / local Xcode before TestFlight.

---

## 4. Residual risks (priority)

1. **Rotate** any credentials that appeared in PR #114 `DemoAuthBootstrap` (ops) — never paste values into git.  
2. **Deploy** Agent B `code`-bearing errors to prod so iOS taxonomy is reliable end-to-end.  
3. Consider **token invalidation** on password change / disable (jti denylist or `token_version`).  
4. Check **`SecItemAdd` OSStatus** and fail closed (keep legacy until Keychain write succeeds).  
5. Confirm prod **`JWT_SECRET` / `ADMIN_PASSWORD`** are not defaults.  
6. Run **XCTest** on macOS before shipping recovery TestFlight.

---

## 5. Deliverables (Agent C)

| Path | Role |
|------|------|
| `research/p0-auth/agent_c/REPORT_SECURITY_QA.md` | This report |
| `research/p0-auth/agent_c/check_demo_bypass.py` | Tree scan regression (no secrets printed) |
| `backend/tests/test_auth_roles.py` | Admin/user, disable, JWT-after-password-change, forged role |
| `AuthErrorMapperTests` (+ server `code` cases) | Taxonomy |
| `AuthSessionStoreTests.testAdminVsUserAccessFlags` | Role flags |
| (already on branch via A) | `AuthSecurityRegressionTests`, policy/models/store tests |

**Demo bypass on recovery branch:** **fully purged** (CONFIRMED).  
**PR #114:** still contains bypass — close or rewrite without credentials; rotate passwords.
