# Cycle 11 AGENT B – NinebotTEA Validation

**Date:** 2026-11-23T21:20:07Z (UTC)  
**Branch:** `cursor/ninebottea-validation-b100`  
**Base:** `cursor/server-diagnostics-c11-b100` @ `9c6b153`  
**Own files:** `server/firmware-analysis/diagnostics_tea.py`, `server/firmware-analysis/test_diagnostics_tea.py`, this report  

**Hard bans observed:** no real ZT3/ENC decrypt; no invented keys; no env secret values in output; no shell API; no prod deploy.

Evidence class: **LIVE** = probed this Cloud VM / public `/health` this run; **REPO** = git files; **UNIT** = unittest.

---

## Grades table

| Check | Grade | Class | Evidence |
|-------|-------|-------|----------|
| `DECRYPT_CMD` on this Cloud VM | **UNKNOWN** | LIVE | Env unset; `diagnose_tea()` → grade `UNKNOWN` (`diag_host.json`) |
| Wrapper path / `which()` on this VM | **UNKNOWN** | LIVE | `/opt/scootercheck/decrypt-firm.sh` absent; `ninebottea` not on `PATH` |
| Safe `--help` / dry probe on this VM | **UNKNOWN** | LIVE | Skipped (`not_configured`) — never invented a decrypt |
| Repo example wrapper `decrypt-firm.example.sh` | **AVAILABLE** | LIVE | Path exists + executable; **no** documented `--help`/`--dry*` → probe skipped (`diag_example_wrapper.json`) |
| Public prod `/health` `decryptConfigured` | **CONFIGURED** | LIVE | `GET https://api.tuningscanner.de/scootercheck-fw/health` → `decryptConfigured: true`; mapped via `grade_from_configured_flag` only |
| Prod wrapper path / binary on Hetzner | **UNKNOWN** | — | No SSH / host env; flag ≠ AVAILABLE/VERIFIED |
| Prod TEA decrypt E2E | **UNKNOWN** | — | Not claimed; real packs never decrypted |
| Unit: unset → UNKNOWN | **UNKNOWN** | UNIT | `test_unset_is_unknown` |
| Unit: missing path → FAILED | **FAILED** | UNIT | `test_missing_wrapper_is_failed` |
| Unit: wrapper without safe flags → AVAILABLE | **AVAILABLE** | UNIT | `test_available_without_probe_flag` |
| Unit: stub `ninebottea --help` exit 0 → VERIFIED | **VERIFIED** | UNIT | `test_verified_on_help_exit_zero` |
| Unit: stub `--help` nonzero → FAILED | **FAILED** | UNIT | `test_failed_when_help_nonzero` |
| Health-flag helper alone | **CONFIGURED** | UNIT | `grade_from_configured_flag(True)` — never escalates to VERIFIED |

**Overall (this Cloud Agent host):** **UNKNOWN** — `DECRYPT_CMD` unset; TEA not installed here.  
**Overall (production, from public health only):** **CONFIGURED** — not AVAILABLE, not VERIFIED.

---

## What was actually executed

| # | Action | Result |
|---|--------|--------|
| 1 | `python3 -m unittest test_diagnostics_tea.py` | **19/19 OK** |
| 2 | `python3 diagnostics_tea.py` (host env) | grade **UNKNOWN**; probe not attempted |
| 3 | `python3 diagnostics_tea.py --decrypt-cmd …/decrypt-firm.example.sh` | grade **AVAILABLE**; probe skipped (`no_documented_safe_flag`) |
| 4 | `GET …/scootercheck-fw/health` (read-only HTTPS) | `ok:true`, `decryptConfigured:true` → flag grade **CONFIGURED** |
| 5 | Path probes: `/opt/scootercheck`, `which ninebottea` | absent / not found |
| 6 | Real `.enc` / ZT3 decrypt | **Not executed** |
| 7 | Source `/etc/scootercheck/decrypt.env` / read `KEY` | **Not executed** |
| 8 | Invent keys / write secrets | **Not executed** |

Artifacts: `research/cycle11/agent_b/diag_host.json`, `diag_example_wrapper.json`.

---

## Module contract (`diagnostics_tea.py`)

Safe ladder (CONFIGURED ≠ AVAILABLE ≠ VERIFIED ≠ FAILED ≠ UNKNOWN):

1. **CONFIGURED** — `DECRYPT_CMD` non-empty (or health `decryptConfigured` via `grade_from_configured_flag`).
2. **AVAILABLE** — `Path.exists()` or `shutil.which(first_token)` (same idea as `app.run_decrypt`).
3. **VERIFIED** — only if a **documented** safe flag runs and exits 0:
   - basename `ninebottea` → `--help` (documented in `deploy/install-on-hetzner.sh`)
   - shell wrapper → `--help` / `-h` / `--dry-run` / `--dry` / `--check` **only if present in script text**
   - example `decrypt-firm.example.sh` has none → max **AVAILABLE**
4. **FAILED** — configured but path/which miss, or documented probe attempted and failed.
5. **UNKNOWN** — unset on this host (not treated as FAILED).

Redaction: report stores basename + token length only (no full `DECRYPT_CMD` path string); probe stdout/stderr strips `KEY=` / secret-like lines; child env drops `*_KEY` / `*_TOKEN` / `*_SECRET`.

CLI: `python3 diagnostics_tea.py [--decrypt-cmd PATH] [--no-probe] [--timeout SEC]`

PM note: ready for Agent A `diagnostics_models` + admin route wiring; this module does not patch `app.py`.

---

## Policy checklist

| Rule | Status |
|------|--------|
| Admin-only diagnostics (route ownership) | Deferred to PM / Agent A — library only |
| No shell API | Pass |
| No env dump / no secret values in output | Pass (UNIT + LIVE JSON) |
| No keys invented | Pass |
| No decrypt of real packs | Pass |
| Flags alone ≠ VERIFIED | Pass |

---

## Verdict

Delivered safe TEA diagnostics + 19 unit tests. This VM cannot claim TEA **AVAILABLE**/**VERIFIED** (unset). Repo example wrapper proves the **AVAILABLE** path without unsafe decrypt. Production public health only supports **CONFIGURED**.
