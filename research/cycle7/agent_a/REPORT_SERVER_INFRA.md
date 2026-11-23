# Cycle 7 AGENT A – Server Infrastructure Inventory

**Date:** 2026-11-23  
**Author tip:** `cursor/cycle7-server-infra-inventory-86df` (from `cursor/server-fw-analysis-c7-b100` / multi-agent `@ f2db879`)  
**Source of truth (server code):** `origin/cursor/unified-investigation-flow-b100` `@ f306bf3` → `server/firmware-analysis/` (~222 paths)  
**Hard bans observed:** no key extraction, no auth bypass, no probing of live hosts with credentials

---

## 1. What exists on unified (`server/firmware-analysis/`)

### README summary

Worker accepts ZIP/ENC from the iOS app, stores jobs under `WORK_DIR`, runs **ninebottea** via `DECRYPT_CMD`, optionally **Ghidra Headless**, then returns `FirmwareDeepAnalysisResult` JSON. Repo **does not ship** ninebottea or decrypt keys.

Pipeline (README):

1. `POST /v1/firmware/jobs` (multipart `meta_json` + `archive`) → immediate `queued`
2. Persist under `WORK_DIR/YYYY/MM/DD/<jobId>/`
3. Extract `.enc` → `DECRYPT_CMD` → plaintext under `PLAINTEXT_STORE`
4. Optional Ghidra → `.c` under `DECOMPILE_STORE`
5. Deterministic speed/combo scan → JSON
6. Optional LLM (`allowLLM`, default **false**)
7. App polls `GET /v1/firmware/jobs/{id}` until `completed` / `failed`
8. Optional artifact downloads: `/plaintext`, `/decompile`, plus Phase-2+ artifact GETs

Deploy story: rsync to `/opt/scootercheck/firmware-analysis/`, `deploy/install-on-hetzner.sh`, systemd unit `scootercheck-fw.service` (uvicorn `127.0.0.1:8088`), nginx location `/scootercheck-fw/` → backend.

### FastAPI routes (`app.py`)

| Method | Path | Auth |
|--------|------|------|
| GET | `/health` | open |
| POST | `/v1/firmware/jobs` | require_auth |
| GET | `/v1/firmware/jobs/{id}` | require_auth + job ownership |
| GET | `/v1/firmware/jobs/{id}/plaintext` | same |
| GET | `/v1/firmware/jobs/{id}/decompile` | same |
| GET | `/v1/firmware/jobs/{id}/functions` | same |
| GET | `/v1/firmware/jobs/{id}/callgraph` | same |
| GET | `/v1/firmware/jobs/{id}/function-diff` | same |
| GET | `/v1/firmware/jobs/{id}/input-behavior` | same |
| GET | `/v1/firmware/jobs/{id}/input-behavior-diff` | same |
| GET | `/v1/firmware/jobs/{id}/activation-forensics` | same |
| GET | `/v1/firmware/jobs/{id}/semantic-dataflow` | same |
| GET/POST/DELETE | `/v1/firmware/admin/stock` (+ promote) | require_admin |
| GET | `/v1/firmware/admin/jobs`, `/admin/stats` | require_admin |
| GET/POST/DELETE | `/v1/firmware/admin/reference-catalogs*` / inventory | require_admin |
| DELETE | `/v1/firmware/admin/jobs/{id}` | require_admin |

`JobRequestMeta`: `clientReportId`, `originalFileName`, `archiveSHA256`, `payloadSHA256?`, `infoJSON?`, `models[]`, `controllerType?`, `allowDecrypt` (default true), `allowLLM` (default false).

### Auth model (`job_auth.py` + `require_auth` in `app.py`)

- **Bearer JWT** (`Authorization: Bearer …`): same `JWT_SECRET` / `JWT_ALGORITHM` (HS256) as ScooterCheck Auth API; user must be `active`; preferred owner `user:<sub>`. Preferred when both JWT and API token present.
- **API token** (`X-ScooterCheck-Token`): matches `API_TOKEN` or dedicated `ADMIN_API_TOKEN`.
- **Admin:** JWT `role=admin` **or** `ADMIN_API_TOKEN` (or legacy `API_TOKEN` only if `API_TOKEN_GRANTS_ADMIN=1`).
- **Secure defaults (Phase 2.2H / H.1):** `API_TOKEN_GRANTS_ADMIN=0`, `TRUST_API_TOKEN_CLIENT_ID=0` — shared token does **not** grant admin; `X-ScooterCheck-Client-Id` is metadata only (not a trusted principal).
- Unauthorized job access → opaque **404** (no metadata leak).
- Open mode only when **no** `API_TOKEN`, `ADMIN_API_TOKEN`, or `JWT_SECRET` configured (dev).

### DECRYPT_CMD / ninebottea

- ENV `DECRYPT_CMD` → wrapper path (example `/opt/scootercheck/decrypt-firm.sh`).
- `decrypt-firm.example.sh`: calls `NINEBOTTEA_BIN` / `ninebottea` with `decrypt <in> <out> [--key] --variant tea|xtea`; sources `/etc/scootercheck/decrypt.env` for `KEY` / `VARIANT` (not in git).
- Exit 4 = decrypt failure; plaintext recovery path may still accept Cortex-M IVT dumps (see formats).

### Ghidra

- `ghidra_decompile.py`: `ghidra_configured()` looks for `GHIDRA_HEADLESS`, `GHIDRA_HOME/.../support/analyzeHeadless`, `PATH`, or `/opt/ghidra/ghidra_*/…`.
- Scripts under `ghidra_scripts/` (decompile, callgraph, functions, speed xrefs, limit slice, IVT seed, etc.).
- Serialized with angr via `_HEAVY_ANALYSIS_LOCK` (4 GB VPS OOM guard).
- ENV: `ENABLE_GHIDRA`, `GHIDRA_PROCESSOR` (default `ARM:LE:32:Cortex`), `GHIDRA_BASE_ADDR` (`0x08000000`), auto-identify / IVT seed flags.

### `/health` flags (selected)

`ok`, `service=scootercheck-fw`, `decryptConfigured`, `ghidraConfigured`, `ghidraEnabled`, `jwtConfigured`, `apiTokenConfigured`, `adminApiTokenConfigured`, `apiTokenGrantsAdmin`, `trustApiTokenClientId`, `authSecurityOk`, `authSecurityWarnings`, retention caps, `llmConfigured` / provider / model, `stockFwDir` / `stockRefCount`, `r2Configured`, `capstoneConfigured`, `yaraConfigured`, `unicornConfigured`, `angrLiteConfigured`, `angrEngineConfigured`, angr timeout/mem/depth/symbolic, `time`.

### Supporting tree (high level)

- Analysis modules: speed/combo, stock_diff, cortex_m_ivt, r2/capstone/yara, unicorn/angr_lite, limit_slice, input_*, function_*, activation_forensics, semantic_dataflow, llm_*, reference catalog, etc.
- Deploy: systemd, nginx snippets, Hetzner install + phase rollout scripts.
- Tests + `testdata/` for phases 22d–234 (fixtures/exports; no live keys).
- `.env.example` / `requirements.txt` (FastAPI, uvicorn, PyJWT, capstone, yara, unicorn; angr optional/unpinned).

---

## 2. What is NOT on this Cloud VM (verified)

| Item | Result |
|------|--------|
| `server/` on tip `cursor/server-fw-analysis-c7-b100` | **Absent** (`server_absent_on_tip`) |
| `GHIDRA_HOME` / `GHIDRA_HEADLESS` | **unset** |
| `analyzeHeadless` / `ghidra` on PATH | **not found** |
| `/opt/ghidra` | **missing** |
| `ninebottea` on PATH | **not found** |
| `/opt/scootercheck`, `decrypt-firm.sh` | **missing** |
| `/etc/scootercheck/firmware-analysis.env` / `decrypt.env` | **missing** |
| `DECRYPT_CMD` / firmware-related env vars | **unset** |
| Decrypt keys / `KEY` material | **not present** (and must not be invented or extracted) |

Note: agent stores under `/cursor/stores/…` contain prior Ghidra *timing/metrics* artifacts from other runs — not an installed Ghidra toolchain for this VM.

---

## 3. Supported formats (README + `app.py` / `plaintext_detect.py`)

**Uploads**

- **ZIP:** must contain `FIRM.bin.enc` / `*.bin.enc` / any `*.enc`; optional `info.json` (≤2 MiB). Zip-safety checks (path traversal, bombs, symlinks).
- **Bare `.enc` / other:** copied as-is into job dir as the enc payload path.
- Size capped (`MAX_UPLOAD_BYTES` via `zip_safe.validate_upload_size`).

**Decrypt / plaintext recovery**

1. If `looks_like_plaintext_firmware` (filename `.dec.bin` / `.dec`, or Cortex-M IVT, or soft low-entropy+zeros) → **skip** ninebottea; copy through.
2. Else run `DECRYPT_CMD` (tea then xtea in example wrapper).
3. If decrypt fails: recovery only when IVT evidence with `ignore_filename=True` and reason `cortex_m_ivt` (handles ninebottea exit 4 on cleartext dumps misnamed as enc).
4. Else job `failed` / `DECRYPT_FAILED`. Client can set `allowDecrypt=false` → `DECRYPT_NOT_ALLOWED`.

---

## 4. Auth model (contracts for Cycle 7)

Documented for porting; **do not invent secrets**:

| Mechanism | Header / claim | Role |
|-----------|----------------|------|
| JWT | `Authorization: Bearer <token>` | User jobs; owner `user:<sub>`; admin if `role=admin` |
| Shared API token | `X-ScooterCheck-Token: API_TOKEN` | Authenticate app; **not** admin by default; no client-id ownership by default |
| Admin API token | `X-ScooterCheck-Token: ADMIN_API_TOKEN` | Admin endpoints / promote-stock / catalogs |
| Client id | `X-ScooterCheck-Client-Id` | Metadata only unless legacy `TRUST_API_TOKEN_CLIENT_ID=1` |

iOS (on unified, not on multi-agent tip): JWT in Keychain; upload/poll/artifacts expect Bearer JWT (`FirmwareServerAnalysisClient`).

---

## 5. Default base URL (iOS client)

On **unified** (file missing on current multi-agent tip):

`ios/.../FirmwareServerAnalysisClient.swift`:

```text
static let defaultBaseURLString = "https://api.tuningscanner.de/scootercheck-fw"
```

Matches README App-Default and nginx `location /scootercheck-fw/` → `127.0.0.1:8088`.  
Auth API sibling: `https://api.tuningscanner.de/scootercheck` (`AuthAPIClient`).

**No live probe performed** from this agent (policy + no credentials).

---

## 6. Gaps vs live deployment — INCOMPLETE

Without production credentials / host access, the following are **unknown**:

- Whether `api.tuningscanner.de/scootercheck-fw` is currently serving the unified revision (`f306bf3` lineage) or an older build
- Live `/health` values (`decryptConfigured`, `ghidraConfigured`, `authSecurityOk`, LLM, stockRefCount, …)
- Contents of `/etc/scootercheck/firmware-analysis.env` and `/etc/scootercheck/decrypt.env` (keys, `DECRYPT_CMD`, tokens)
- Whether `ADMIN_API_TOKEN` is set and grants flags are at secure defaults in prod
- Stock library population under `/var/lib/scootercheck/stock-fw/`
- Real nginx TLS / rate-limit / body-size behavior beyond the checked-in snippet
- Operational ninebottea binary version / TEA vs XTEA default success rates

**Status: INCOMPLETE** — inventory is code-complete from git; live parity unverified.

---

## 7. Cycle 7 implementation recommendations

1. **Port** `server/firmware-analysis/` (code, README, `.env.example`, deploy examples, tests/fixtures) from `origin/cursor/unified-investigation-flow-b100` onto the Cycle 7 branch — **no keys**, no `decrypt.env`, no real `API_TOKEN`/`JWT_SECRET` values.
2. **Port iOS contracts** together: `FirmwareServerAnalysisClient`, job/status Codable models, Keychain JWT wiring — keep default base URL as documented; override via settings for staging.
3. Treat **API surface** as the contract: `/health`, job submit/poll, artifact GETs, admin stock/catalog — align client decoding with Phase 2.2H+ auth security fields.
4. **Local/Cloud VM:** expect `decryptConfigured=false` / `ghidraConfigured=false` until ops install ninebottea wrapper + Ghidra; CI should skip headless when `GHIDRA_HOME` unset (synthetic fixtures only).
5. **Do not invent keys** or probe production with guessed tokens. Ops inject secrets only on the Hetzner host via `/etc/scootercheck/*.env`.
6. After port: wire offline-safe app path (encrypted → server job schema only; no local Ghidra) per `docs/AGENT_TASK_QUEUE.md` Cycle 7 packages.

---

## Verification commands run (this VM)

```text
which analyzeHeadless ninebottea  → not found
echo $GHIDRA_HOME / $DECRYPT_CMD → unset
test -d /opt/ghidra /opt/scootercheck → missing
test -d server/ on tip → absent
git show origin/cursor/unified-investigation-flow-b100:server/firmware-analysis/…
```

## Refs

- Source tree: `origin/cursor/unified-investigation-flow-b100:server/firmware-analysis/`
- iOS default URL: same tip `FirmwareServerAnalysisClient.defaultBaseURLString`
- Cycle queue: `docs/AGENT_TASK_QUEUE.md` (Cycle 7 Agent A)
)
