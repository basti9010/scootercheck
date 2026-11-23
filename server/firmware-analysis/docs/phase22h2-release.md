# Phase 2.2H.2 — Release validation notes

## Analysis profile hash (Module F)

| Source | `ghidraVersion` in payload | Stored hash (pre-2.2H.2) |
|--------|----------------------------|--------------------------|
| Phase 2.2H stub (no Ghidra) | `null` | `8a4c448e…` |
| Phase 2.2H.1 real Ghidra | `"12.2"` | `1d0aea62…` |

**Cause:** pre-2.2H.2 `analysisProfileHash` hashed the full profile including runtime soft fields (`ghidraVersion`, `analysisTimeoutSec`, `memoryLimit`).

**Fix (2.2H.2):** semantic hash excludes those soft fields (and `runtimeConfig`). Canonical semantic hash for default Cortex profile:

`c0f507820a1457a1af98c2a66352db531f2f4ad1bcf72bc32c58e307e3f41de7`

Runtime values remain in `runtimeConfig` / top-level for visibility. Catalog compare re-hashes semantically so legacy stored hashes with soft drift stay `LEGACY_PARTIAL` / `COMPATIBLE`, not silent `INCOMPATIBLE`.

## iOS JWT / migration

- Bearer JWT from ScooterCheck login is required for firmware upload / poll / artifacts.
- Token storage: Keychain (`AuthKeychainStore`); one-shot migrate from UserDefaults then wipe.
- `X-ScooterCheck-Client-Id` is metadata only under `TRUST_API_TOKEN_CLIENT_ID=0`.
- Legacy jobs owned by `apitoken-client:*` are **not** auto-claimed by JWT users (admin migration only).
- Breaking for unauthenticated shared-token + Client-Id ownership: intentional.

## Production env (manual, no rotation by scripts)

```
API_TOKEN_GRANTS_ADMIN=0
TRUST_API_TOKEN_CLIENT_ID=0
ADMIN_API_TOKEN=<set>
JWT_SECRET=<same as auth service>
```

`/health` exposes `authSecurityOk` + `authSecurityWarnings`.
