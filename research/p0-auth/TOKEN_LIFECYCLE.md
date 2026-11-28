# P0 Auth — Token Lifecycle Strategy

**Stand:** 2026-11-28  
**Epistemic:** Server behavior **CONFIRMED** in `backend/`; client behavior **CONFIRMED** on PR #117 code. Device verification **NOT VERIFIED**.

## Current design (no incompatible auth redesign)

| Item | Value |
|------|-------|
| Token type | Bearer access JWT (HS256) only |
| Claims | `sub`, `email`, `role`, `status`, `iat`, `exp` |
| Default lifetime | `JWT_EXPIRE_HOURS` = **336 h (14 days)** |
| Refresh | **Absent** (`POST /auth/refresh` → 404) |
| Storage (app) | Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) |
| Revocation list | **None** |

## Risks of missing revocation

| Event | What happens today | Risk |
|-------|--------------------|------|
| Password change | New logins use new hash; **old JWT still valid until `exp`** | Medium — stolen token survives |
| User disable / reject | `/auth/me` and admin routes re-check DB; FW `session/check` requires active | Partial mitigate — **CONFIRMED** DB status check on me/admin; forged role claim does not elevate |
| Logout (client) | Keychain cleared locally only | Server token still valid until exp if stolen earlier |
| Secret rotation | All tokens invalidate | Requires Freigabe; brief outage |

## Strategy (compatible, no Freigabe-breaking redesign)

1. **Expiry:** Keep 14d access; document re-login after `token_expired`.  
2. **Password change / disable:** Rely on DB status checks on `/auth/me` and protected routes (already). Client clears session on 401/403/`token_invalid`/`token_expired`.  
3. **Re-login:** Only supported renewal path until a dedicated refresh design is approved.  
4. **Future (Freigabe required):** refresh tokens + rotation, or server-side denylist/`token_version` claim bumped on password change/disable.  
5. **Ops:** Rotate credentials that appeared in PR #114 DemoAuthBootstrap; do not merge #114.

**Do not** ship refresh/denylist in this validation pass without explicit user Freigabe.
