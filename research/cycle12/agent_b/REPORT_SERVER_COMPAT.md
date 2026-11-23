# Cycle 12 Agent B – Server Compatibility Report

**Branch:** `cursor/c12-server-compat-b100`  
**Base:** `origin/cursor/hetzner-deploy-cd-c12-b100`  
**Scope:** FastAPI firmware-analysis compatibility for versioned CD releases  
**Hard bans honored:** no prod changes · no keys · no second architecture · encrypted stays INCOMPLETE without TEA

## 1. Runtime dependency inventory

### Python (requirements.txt)

| Package | Role |
|---------|------|
| fastapi==0.115.6 | API |
| uvicorn[standard]==0.32.1 | ASGI server (systemd ExecStart) |
| python-multipart==0.0.17 | uploads |
| pydantic==2.10.3 | models |
| PyJWT==2.10.1 | Bearer JWT |
| capstone==5.0.3 | disasm / angr_lite fallback |
| yara-python==4.5.1 | `yara_rules/` |
| unicorn==2.1.1 | emulate |
| angr (optional, unpinned) | deep CFG; omit on 4 GB VPS |

### Python 3.12 venv (`install-on-hetzner.sh` + `release-deploy.sh`)

- Forces `python3.12 -m venv .venv` (3.14 lacks wheels for pinned pydantic-core).
- CD prefers copying `.venv` from previous release; else rebuild per `releases/<sha>`.
- `apt` bootstrap: `python3.12`, `python3.12-venv`, `python3-pip`, `radare2`.

### DECRYPT_CMD / NinebotTEA

- Env: `DECRYPT_CMD=/opt/scootercheck/decrypt-firm.sh` (outside release).
- Wrapper sources `/etc/scootercheck/decrypt.env` (`NINEBOTTEA_BIN`, optional `KEY=` — never in git).
- TEA copied into **service venv** (`NINEBOTTEA_SRC`); `ProtectHome=true` blocks `/root`.
- Without working decrypt → encrypted path **INCOMPLETE** / fail-closed (intentional).

### GHIDRA_HOME

- Default `/opt/ghidra` outside releases; unit `ReadOnlyPaths=/opt/ghidra … /usr/lib/jvm`.
- Releases ship only `ghidra_scripts/`.

### angr guards (seeded if missing)

`ENABLE_ANGR`, `ANGR_MAX_BYTES`, `ANGR_TIMEOUT_SEC`, `ANGR_MEM_MB`, `ANGR_CFG_DEPTH`, `ANGR_SYMBOLIC=0`.

### Data stores (never release-synced)

| Env | Path |
|-----|------|
| `WORK_DIR` | `/var/lib/scootercheck/firmware-jobs` |
| `PLAINTEXT_STORE` | `/var/lib/scootercheck/decrypted` |
| `DECOMPILE_STORE` | `/var/lib/scootercheck/decompiled` |
| `STOCK_FW_DIR` | `/var/lib/scootercheck/stock-fw` |

## 2. Deliverables

| Artifact | Purpose |
|----------|---------|
| `deploy/validate-release-config.sh` | `offline` (CI) / `host` (names only, no secret values) |
| `deploy/RELEASE_COMPAT.md` | Outside-release list, symlink layout, TEA + Ghidra contracts |
| `deploy/deploy-manifest.txt` | CD file checklist incl. C11 `diagnostics_*.py` |
| `test_deploy_manifest.py` | Pure offline pytest + unittest checks |
| `.env.example` | Documented angr guards + critical auth keys |
| `deploy/phase1-rollout.sh` | Extended file list + diagnostics import check |

Aligned with Agent A layout: `/opt/scootercheck/releases/<sha>` + symlink at `firmware-analysis`.

## 3. Validation (no Hetzner)

```bash
./server/firmware-analysis/deploy/validate-release-config.sh offline
cd server/firmware-analysis && python -m pytest -q test_deploy_manifest.py
```

## 4. Grades (evidence class)

| Claim | Grade |
|-------|-------|
| Manifest + offline validator in-repo | **REPO** |
| Host systemd/env/path checks | Script ready; needs Freigabe → not **DEPLOYED** |
| TEA/Ghidra live decrypt/decompile | Not claimed (**AVAILABLE** at most via diagnostics) |
| Encrypted end-to-end | Stays **INCOMPLETE** without server KEY (by design) |

## 5. Handoff

- DevOps: pack releases from `deploy-manifest.txt`; after new venv, re-copy NinebotTEA.
- Security: keep secrets under `/etc/scootercheck/`; `API_TOKEN_GRANTS_ADMIN=0`.
- QA: offline validator + `test_deploy_manifest.py` are CD gates (already in server-firmware-tests.yml).
