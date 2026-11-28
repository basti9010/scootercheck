# Agent A — iOS Authentication (P0 Auth Recovery)

**Branch:** `cursor/p0-auth-recovery-b100`  
**Stand:** 2026-11-28  
**Scope:** Client session storage, bootstrap harden, AuthError taxonomy, offline local gate, XCTest.  
**Out of scope:** Backend Python (Agent B); DemoAuthBootstrap / `authGateEnabled=false` (never reintroduced).

## Grades

| Item | Grade | Notes |
|------|-------|-------|
| Keychain token + UserDefaults migration | **IMPLEMENTED** | `KeychainAuthTokenStore`; legacy key `scootercheck.auth.token` migrated once then cleared |
| Bootstrap: network ≠ logout | **IMPLEMENTED** | Keep token + cached user; set `lastAuthError` / banner |
| Bootstrap: 401/403/expired/revoked → clear | **IMPLEMENTED** | `AuthAPIError.shouldClearSession` + `AuthSessionPolicy` |
| AuthError taxonomy | **IMPLEMENTED** | `AuthErrorKind` + `AuthErrorMapper` (URLError + HTTP) |
| Offline local vs server vs admin | **IMPLEMENTED** | `AuthSessionPolicy.AccessTier`; gate uses `canUseLocalFeatures` |
| Logout clears Keychain + state | **IMPLEMENTED** | `tokenStore.deleteToken()` + `userCache.deleteUser()` |
| No DemoAuthBootstrap / gate-off | **IMPLEMENTED** | Regression XCTests; AuthGateView remains app root |
| XCTest coverage | **TESTED** (authored) | Run on macOS/Xcode — this Linux agent host has no `xcodebuild` |

Epistemic: **CONFIRMED** for code on this branch. Device Keychain behavior on hardware = **HYPOTHESIS** until TestFlight. Original “login impossible” server root cause at demo time = **INCOMPLETE** (unchanged).

## Behavior changes

1. **Token storage:** JWT leaves UserDefaults → Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). One-shot migration from `scootercheck.auth.token`.
2. **User cache:** Active/pending profile JSON in UserDefaults (`scootercheck.auth.cached_user`) so offline restore can unlock local features without `/auth/me`.
3. **Bootstrap / refreshMe:**  
   - Transport / timeout / unreachable / 5xx → keep session, `isOfflineSession = true`, user-facing German message.  
   - 401/403 / invalid / expired / revoked → `clearSession()`, re-login required.
4. **AuthGateView:** Uses `canUseLocalFeatures` (policy). Offline banner when `isOfflineSession`. Still no `authGateEnabled` flag.
5. **Access tiers:** `localOnly` | `serverAPI` | `adminAPI` | `signedOut`. Admin elevation only when online + `isAdmin`. `requireServerAuth()` denies offline / signed-out.
6. **API client:** Maps `URLError` and HTTP statuses into `AuthAPIError` kinds; injectable `AuthRemoteClient` for tests.

## Files touched (iOS)

| Path | Role |
|------|------|
| `Auth/AuthTokenKeychainStore.swift` | Keychain + in-memory store + migration |
| `Auth/AuthUserCache.swift` | Cached `AuthUser` |
| `Auth/AuthSessionPolicy.swift` | Pure bootstrap / tier decisions |
| `Auth/AuthSessionStore.swift` | Hardened session + DI |
| `Auth/AuthModels.swift` | `AuthErrorKind`, `AuthErrorMapper` |
| `Auth/AuthAPIClient.swift` | Typed errors + `LiveAuthRemoteClient` |
| `Auth/AuthGateView.swift` | Offline local entry + banner |
| `Auth/AuthCredentialsNormalizer.swift` | Kind-aware wrong-credentials helper |
| `PrivacyContent.swift` | Keychain JWT disclosure |
| `ScooterCheckTests/AuthSessionStoreTests.swift` | Login / bad creds / restore / revoke / network / logout / offline |
| `ScooterCheckTests/AuthErrorMapperTests.swift` | Taxonomy mapping |
| `ScooterCheckTests/AuthSessionPolicyTests.swift` | Policy matrix |
| `ScooterCheckTests/AuthModelsTests.swift` | User flags + coding keys |
| `ScooterCheckTests/AuthSecurityRegressionTests.swift` | No demo bypass |
| `ScooterCheckTests/AppFeatureFlagsTests.swift` | Gate-off guard |
| `ScooterCheck.xcodeproj/project.pbxproj` | New sources/tests |

## Test matrix (authored)

| Case | Expected | Status |
|------|----------|--------|
| Successful login (mock) | Token + active user, `serverAPI` | **TESTED** (unit, mock) |
| Bad credentials | No session, `invalidCredentials` | **TESTED** |
| Restored session + `/me` OK | Cache then refresh profile | **TESTED** |
| Expired / revoked / 403 | Clear Keychain + cache | **TESTED** |
| Network / timeout / unreachable | Keep token, `localOnly` | **TESTED** |
| Logout | Clears store + cache | **TESTED** |
| Offline local vs server denial | Local OK; `requireServerAuth` throws | **TESTED** |
| Legacy UserDefaults migrate | Key removed after load | **TESTED** |
| Demo bypass absent | File/symbol guards | **TESTED** |

**Not run here:** Full `xcodebuild test` (no Xcode on agent VM) — **INCOMPLETE** until CI/macOS.

## Remaining gaps

| Gap | Epistemic |
|-----|-----------|
| Confirm Keychain on physical device / TestFlight | **HYPOTHESIS** |
| Wire every server call site through `requireServerAuth()` (firmware client still sends bearer opportunistically) | **INCOMPLETE** / minimal by design |
| Refresh-token / silent renew | **INCOMPLETE** — not in client; Agent B |
| Rotate any credentials that ever lived in PR #114 demo bypass | **Ops** — not done in this agent |
| Broader “login impossible” server root cause at demo disable time | **INCOMPLETE** |
| Privacy copy still mentions “kein Benutzerkonto” in at-a-glance elsewhere | **INCOMPLETE** (only localStorage section updated) |

## Explicit non-goals honored

- Did **not** copy `DemoAuthBootstrap` or set `authGateEnabled = false`.
- Did **not** print or commit demo passwords.
- Did **not** edit backend Python.
