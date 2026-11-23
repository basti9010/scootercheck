# Cycle 8 – Pipeline / TEA / E2E (Phases 3–5)

Stand: 2026-11-23 Europe/Berlin  
Tip: `cursor/server-deploy-ghidra-ios-c8-b100`

## Architecture (validated as design + partial runtime)

```
ScooterCheck (iOS Hub)
  → HTTPS → FastAPI (/v1/firmware/jobs)
  → Package load / SHA-256
  → Format + crypto gate
  → Static pre-analysis
  → DECRYPT_CMD (only if configured + authorized)
  → Ghidra headless (only if GHIDRA_HOME)
  → Structured report JSON
  → ScooterCheck UI statuses
```

Encrypted without authorized plaintext → **INCOMPLETE** (iOS crypto gate + server notes).  
No encryption bypass; no vehicle writes; no TEA key derivation.

## Grade matrix

| Capability | IMPLEMENTED | TESTED | DEPLOYED | END_TO_END_VERIFIED |
|------------|:-----------:|:------:|:--------:|:-------------------:|
| FastAPI job API (in-tree) | yes | yes (light suite) | yes* | no |
| iOS Hub + local pipeline | yes | unit (status/crypto) | n/a | no |
| SHA-256 integrity (server) | yes | yes | yes* | no |
| Crypto gate → INCOMPLETE | yes | yes (XCTest names) | n/a | no |
| DECRYPT_CMD hook | yes | code review | yes* (`decryptConfigured`) | no |
| Live TEA decrypt | — | NOT_TESTED | UNKNOWN | no |
| Ghidra scripts in-tree | yes | SKIP path | yes* (`ghidraConfigured`) | no |
| Ghidra on Cloud VM | no | SKIP | n/a | no |
| Authenticated job upload E2E | — | no (no secrets on VM) | — | no |

\* Public `/health` on documented App URL reports service up with decrypt/ghidra/jwt/apiToken configured.  
That is **not** SSH admin access and **not** a verified decrypt/Ghidra job run from this environment.

## Phase 4 – NinebotTEA

| Item | Grade |
|------|-------|
| `DECRYPT_CMD` FastAPI integration | **SUPPORTED** |
| Wrapper pattern (`decrypt-firm.example.sh`) | **SUPPORTED** (code) |
| ninebottea binary/keys in repo | **UNSUPPORTED** |
| TEA on this Cloud VM | **NOT_TESTED** / absent |
| Live prod decrypt success | **UNKNOWN** (health only) |
| XTEA fallback path in wrapper docs | **SUPPORTED** (code) |

## Phase 5 – E2E evidence (this environment)

| Step | Result |
|------|--------|
| Synthetic Ghidra runner | **SKIP** (no analyzeHeadless) — proof JSON written |
| Public `/health` | **OK** (`ok:true`, decrypt/ghidra configured) |
| Auth job upload | **NOT RUN** (no API token/JWT in Cloud secrets) |
| ZT3 packs | container/integrity only — **no decrypt** |
| Server light tests (PM) | `test_upload_integrity_sha256` + `test_api_auth_security` → **17 OK** |
| Agent D light suite | **113 passed, 6 skipped** (their VM) |

## Residual blockers for END_TO_END_VERIFIED

1. Cursor/app secrets for API token or JWT (user-bound; never invent)
2. Optional: SSH deploy key for host Ghidra smoke with Freigabe
3. XCTest CI green on PR #106 tip after Hub merge
