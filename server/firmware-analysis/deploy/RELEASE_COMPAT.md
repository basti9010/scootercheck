# Firmware-analysis release compatibility (Cycle 12)

How versioned CD releases stay compatible with the existing Hetzner layout
(`install-on-hetzner.sh`, `scootercheck-fw.service`, `release-deploy.sh`,
Phase 1 rollout).

**Hard rules:** no secrets in release tarballs · no second architecture ·
encrypted firmware analysis without `DECRYPT_CMD` stays **INCOMPLETE** ·
never sync-delete `/var/lib/scootercheck`.

## What must stay *outside* releases

| Path | Why |
|------|-----|
| `/etc/scootercheck/firmware-analysis.env` | `EnvironmentFile` — tokens, JWT, path config |
| `/etc/scootercheck/decrypt.env` | NinebotTEA `KEY=` / `NINEBOTTEA_BIN=` (mode 640, root:scootercheck) |
| `/var/lib/scootercheck/firmware-jobs` | `WORK_DIR` job store |
| `/var/lib/scootercheck/decrypted` | `PLAINTEXT_STORE` |
| `/var/lib/scootercheck/decompiled` | `DECOMPILE_STORE` |
| `/var/lib/scootercheck/stock-fw` | `STOCK_FW_DIR` (+ catalogs) |
| `/opt/ghidra` | `GHIDRA_HOME` install tree (large, shared) |
| `/opt/scootercheck/decrypt-firm.sh` | `DECRYPT_CMD` wrapper (not in git with keys) |
| `/usr/lib/jvm` | Java for Ghidra headless |

Release packages may ship **code + requirements + ghidra_scripts + yara_rules**.
They must **not** ship `.env`, `decrypt.env`, stock bins, job artifacts, or TEA keys.

## Symlink layout (compatible with `install-on-hetzner.sh` + `release-deploy.sh`)

Bootstrap (`install-on-hetzner.sh`) targets:

```text
APP_DIR=/opt/scootercheck/firmware-analysis
```

CD (`release-deploy.sh`) keeps that path as the **stable name** the unit uses,
and makes it a symlink to an immutable release directory:

```text
/opt/scootercheck/
  decrypt-firm.sh                          # outside releases
  releases/
    <sha>/                                 # unpacked CD artifact (code + .venv)
      app.py
      diagnostics_*.py
      requirements.txt
      ghidra_scripts/
      yara_rules/
      .venv/                               # Python 3.12 venv for this release
    previous                               # prior release path (rollback)
    current_target
  firmware-analysis -> releases/<sha>      # atomic symlink flip
```

**Compatibility notes:**

1. `scootercheck-fw.service` keeps `WorkingDirectory=` / `ExecStart=` under
   `/opt/scootercheck/firmware-analysis` — no unit path rewrite when only the
   symlink target changes.
2. `ReadWritePaths=` already includes `/opt/scootercheck/firmware-analysis`
   (follows the active tree) and `/var/lib/scootercheck`.
3. `install-on-hetzner.sh` is **bootstrap / repair**, not the CD hot path. CD
   unpacks `releases/<sha>`, reuses or rebuilds `.venv`, then `ln -sfn` via
   `release-deploy.sh`. Do not re-run full `apt-get` / env regeneration on
   every release.
4. First CD deploy migrates a non-symlink app dir to `releases/pre-cd-<timestamp>`
   (see `release-deploy.sh`).
5. `phase1-rollout.sh` remains a legacy/emergency file-rsync path. Both CD and
   phase1 must honor `deploy-manifest.txt` so C11 diagnostics are never omitted.

## Python 3.12 venv story

`install-on-hetzner.sh` deliberately uses **Python 3.12** (`python3.12 -m venv`):

- Pinned `pydantic-core` / FastAPI stack lacks wheels on newer interpreters
  (e.g. 3.14 on some hosts).
- Auth service on the same box already standardizes on 3.12.

`release-deploy.sh` prefers copying `.venv` from the previous release; otherwise
rebuild with `pip install -r requirements.txt` for that release before flip.

`requirements.txt` (pinned): FastAPI, uvicorn, multipart, pydantic, PyJWT,
capstone, yara-python, unicorn. **angr is optional** and unpinned — `angr_lite`
falls back to Capstone when angr is absent (`ENABLE_ANGR` + size/timeout/mem
guards still apply).

## NinebotTEA copy constraints

- **Never** install ninebottea from the public internet in CD / Actions.
- `ProtectHome=true` blocks the service user from `/root` — TEA must live in
  the service venv, not under `/root/ninebottea/...` at runtime.
- Bootstrap copies host package into
  `$APP_DIR/.venv/.../site-packages/ninebottea` via `NINEBOTTEA_SRC` /
  `NINEBOTTEA_META` (see `install-on-hetzner.sh`).
- `decrypt.env` sets `NINEBOTTEA_BIN` to
  `/opt/scootercheck/firmware-analysis/.venv/bin/ninebottea` (follows symlink).
- After a release flip with a **new** venv (not copied), re-copy TEA into that
  venv. Do not put `KEY=` in the release.

Encrypted uploads without a working `DECRYPT_CMD` remain **INCOMPLETE** /
fail-closed — that is intentional (Cycle 9+).

## Ghidra + systemd `ReadOnlyPaths`

Unit contract (`deploy/scootercheck-fw.service`):

```text
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/scootercheck /opt/scootercheck/firmware-analysis /var/lib/scootercheck/stock-fw
ReadOnlyPaths=/opt/ghidra /opt/scootercheck/decrypt-firm.sh /etc/scootercheck /usr/lib/jvm
```

- `GHIDRA_HOME=/opt/ghidra` (or nested `ghidra_*_PUBLIC`) stays **outside** the
  release symlink so CD does not re-unpack multi-hundred-MB toolchains.
- Headless must remain readable under `ReadOnlyPaths`; do not move Ghidra under
  a release dir unless the unit is updated in the same change.
- Releases only ship `ghidra_scripts/`; `JAVA_HOME` is set on the unit.

## angr guards (4 GB VPS)

Documented in `.env.example` and seeded by `install-on-hetzner.sh` when absent:

| Key | Role |
|-----|------|
| `ENABLE_ANGR` | Master switch |
| `ANGR_MAX_BYTES` | Skip large bins (default 262144) |
| `ANGR_TIMEOUT_SEC` | Parent kills worker |
| `ANGR_MEM_MB` | `RLIMIT_AS` in worker |
| `ANGR_CFG_DEPTH` | CFG predecessor depth |
| `ANGR_SYMBOLIC` | Must stay `0` unless ops explicitly enables short local explore |

## Auth / admin (CD must not regress)

Release config validation expects these **names** in `.env.example` and set on
host (values never logged by `validate-release-config.sh`):

- `API_TOKEN`, `ADMIN_API_TOKEN`, `JWT_SECRET`, `JWT_ALGORITHM`
- `API_TOKEN_GRANTS_ADMIN=0`, `TRUST_API_TOKEN_CLIENT_ID=0` (secure defaults)

## Validation

```bash
# CI / laptop (no Hetzner):
./deploy/validate-release-config.sh offline
python -m pytest -q test_deploy_manifest.py

# On host after Freigabe (names only, no secret values):
./deploy/validate-release-config.sh host
```

## Manifest

`deploy/deploy-manifest.txt` is the CD file checklist (includes Cycle 11
`diagnostics_*.py`). Prefer consuming the manifest when packing release trees;
keep `phase1-rollout.sh` lists as a non-regressing subset/superset for emergency
rsync.
