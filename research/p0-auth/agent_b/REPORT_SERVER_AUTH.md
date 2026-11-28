# Agent B — Server Authentication Report (P0 Auth Recovery)

**Stand:** 2026-11-28  
**Branch:** `cursor/p0-auth-recovery-b100`  
**Epistemic legend:** CONFIRMED = verified in code or live probe; HYPOTHESIS = proposed; INCOMPLETE = not verified.

## 1. Audit summary (`backend/app/`)

| Area | Finding | Status |
|------|---------|--------|
| JWT issue | `create_access_token` → HS256, claims `sub/email/role/status/iat/exp` | **CONFIRMED** |
| JWT validate | `decode_access_token` via PyJWT; expired → `token_expired`, else `token_invalid` | **CONFIRMED** (after this change) |
| Expiry | `jwt_expire_hours` default **336 h (14 d)** | **CONFIRMED** |
| User store | SQLite `users` + `allowed_domains` | **CONFIRMED** |
| Login | `POST /auth/login` → `AuthResponse{access_token,token_type,user}` | **CONFIRMED** |
| Register | `POST /auth/register` → pending user + token; domain gate | **CONFIRMED** |
| Me | `GET /auth/me` any authenticated user (pending OK) | **CONFIRMED** |
| Change password | `POST /auth/change-password` | **CONFIRMED** |
| Refresh | **No** `/auth/refresh` (live 404 + code) | **CONFIRMED absence** |
| Roles | `user` / `admin`; statuses `pending/active/rejected/disabled` | **CONFIRMED** |
| Admin | `/admin/users*`, `/admin/domains*` behind `require_admin` | **CONFIRMED** |
| Session check | `GET /session/check` requires **active** | **CONFIRMED** |

## 2. Live probes (harmless only)

Base: `https://api.tuningscanner.de/scootercheck` (nginx → `:8002`)

| Request | HTTP | Body shape | Status |
|---------|------|------------|--------|
| `GET /health` | 200 | `{"status":"ok","service":"scootercheck-auth"}` | **CONFIRMED** |
| `POST /auth/login` wrong password (`p0-auth-probe-nobody@example.com`) | 401 | `{"detail":"E-Mail oder Passwort falsch"}` | **CONFIRMED** (pre-deploy; no `code` yet on prod) |
| `POST /auth/login` invalid email | 422 | Pydantic `detail` array | **CONFIRMED** |
| `GET /auth/me` no Bearer | 401 | `{"detail":"Nicht angemeldet"}` | **CONFIRMED** |
| `GET /auth/me` garbage JWT | 401 | `{"detail":"Token ungültig"}` | **CONFIRMED** |
| `POST /auth/refresh` | 404 | `{"detail":"Not Found"}` | **CONFIRMED absence** |

No real credentials used; no tokens dumped.

## 3. iOS ↔ server compatibility matrix

| Concern | Server | iOS (`AuthAPIClient` / models) | Gap |
|---------|--------|--------------------------------|-----|
| Base URL | nginx `/scootercheck/` → app root | `https://api.tuningscanner.de/scootercheck` | OK |
| Login/Register body | `email`, `password`, optional `display_name` | same | OK |
| Success payload | `access_token`, `token_type=bearer`, `user` snake_case | `AuthResponse` CodingKeys | OK |
| User fields | `display_name`, `created_at`, … | matched | OK |
| Token type | Bearer access JWT only | stores `accessToken` | OK |
| Claims | `sub/email/role/status/iat/exp` | client does not decode JWT | OK (opaque Bearer) |
| Expiry | 14 d default | no client-side refresh | **Re-login after expiry** |
| Refresh | absent | no refresh call | **CONFIRMED gap** — re-login required |
| Pending login | allowed; token issued | gate shows waiting UI | OK |
| FW decrypt | scootercheck-fw needs `status=active` | pending users get 403 on FW | **Documented** — not a second auth system |
| Error detail | German `detail` string | `parseError` / `AuthErrorMapper` | OK |
| Error code | `{detail, code}` (this PR) | `AuthErrorCode` + `mapHTTP(..., code:)` wired | Needs **deploy** + Agent A iOS commit |
| Invalid vs 5xx | 401+`invalid_credentials` vs ≥500 / nginx HTML | taxonomy separates `.invalidCredentials` vs `.serverError` / `.unreachable` | OK after deploy |

### scootercheck-fw compatibility (do not invent second architecture)

- Same `JWT_SECRET` / HS256 as auth API (**CONFIRMED** in `server/firmware-analysis` README + `require_auth`).
- Optional shared `X-ScooterCheck-Token` / `API_TOKEN` for workers — **not** user login.
- Active-status check on FW JWT path; auth `/auth/me` does **not** require active.

## 4. Refresh status

**CONFIRMED absence** of refresh tokens and `/auth/refresh`.

**Client requirement today:** after `exp` (or `token_expired`), user must **re-login**. Access lifetime = `JWT_EXPIRE_HOURS` (default 14 days).

**Proposed minimal compatible refresh (not implemented — would change login contract):**

1. At login/register, also issue `refresh_token` (longer-lived JWT with `typ=refresh`, or opaque DB row).
2. `POST /auth/refresh` `{ "refresh_token" }` → new `access_token` (+ rotate refresh).
3. iOS: store refresh in Keychain; call before clearing session on `token_expired`.

**Why not implemented in this pass:** higher surface area (schema + iOS store + FW irrelevant); 14-day access already covers typical sessions; re-login is explicit and testable. Sliding re-issue of non-expired access tokens is low value without offline refresh.

## 5. Error taxonomy (server → iOS)

After this change, auth failures return:

```json
{"detail": "E-Mail oder Passwort falsch", "code": "invalid_credentials"}
```

| code | HTTP | iOS `AuthErrorKind` (via `AuthErrorCode`) |
|------|------|-------------------------------------------|
| `invalid_credentials` | 401 | `.invalidCredentials` |
| `token_expired` | 401 | `.expired` |
| `token_invalid` / `user_unknown` / `not_authenticated` | 401 | `.expired` (re-auth) |
| `account_not_active` / `forbidden` / domain codes | 403 | `.forbidden` |
| (none) | 422 | validation (not login-invalid) |
| (none / HTML) | 5xx / 502/503 | `.serverError` / `.unreachable` |

**Distinguishability:** invalid credentials are **401 + `code=invalid_credentials`**; validation is **422**; outages are **5xx / nginx HTML** without auth `code`. Production still returns detail-only until this backend is deployed.

## 6. Code changes (Agent B)

- `backend/app/errors.py` — `APIError` + stable codes
- `backend/app/main.py` — coded auth errors; expired JWT distinct from invalid
- `backend/tests/` — 15 pytest cases
- `backend/README.md` — refresh absence, error table, FW note
- iOS coordination (shared with Agent A working tree, **not** AuthSessionStore): `AuthErrorCode` + `mapHTTP(code:)` + `parseErrorPayload`

## 7. Test results

```text
cd backend && PYTHONPATH=. python3 -m pytest tests/ -v
======================= 15 passed, 34 warnings in ~6s ========================
```

Covered: health, invalid credentials code, unknown user shape, 422 vs 401, admin login, me authZ, expired/invalid token, JWT claims for FW, refresh 404, domain gate, pending vs session/check, change-password wrong current.

## 8. Deploy notes (NO production deploy from this agent)

1. **No secret rotation / JWT_SECRET change without Freigabe.**
2. Deploy path (ops, when approved): sync `backend/` → `/opt/scootercheck`, restart `scootercheck-auth.service` (uvicorn `:8002`); nginx snippet already proxies `/scootercheck/`.
3. After deploy, re-probe: wrong login must return `code=invalid_credentials`; expired token `code=token_expired`.
4. scootercheck-fw: keep shared `JWT_SECRET` from `/opt/scootercheck/.env` — do not introduce a second user-auth stack.
5. Demo bypass PR #114 / `DemoAuthBootstrap`: **untouched** (iOS-only; out of scope).

## 9. Parent handoff

- Refresh: document re-login; optional future refresh design above.
- Agent A: include `AuthErrorCode` / mapper `code` wiring when committing AuthModels/AuthAPIClient; do not regress detail-string fallbacks for pre-deploy prod.
- Inventory refresh field: update from HYPOTHESIS → **CONFIRMED absence**.
