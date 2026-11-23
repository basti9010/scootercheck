# Release compatibility (existing Hetzner layout)

## Symlink layout

```
/opt/scootercheck/releases/<sha>/     # immutable code tree per deploy
/opt/scootercheck/firmware-analysis → symlink to current release
/etc/scootercheck/*.env               # secrets — NEVER inside releases
/var/lib/scootercheck/**              # jobs, decrypted, stock — NEVER rsync --delete
/opt/ghidra                           # ReadOnlyPaths in systemd
/opt/scootercheck/decrypt-firm.sh     # wrapper outside release (or shared)
```

First CD deploy migrates a non-symlink app dir to `releases/pre-cd-<timestamp>`.

## Python / TEA / Ghidra

- Venv: prefer copy from previous release; else `pip install -r requirements.txt` with Python 3.12 (see `install-on-hetzner.sh`).
- NinebotTEA: still installed into venv site-packages on host; not downloaded by Actions.
- Ghidra: `GHIDRA_HOME` on host; release only ships `ghidra_scripts/`.
- Diagnostics: `diagnostics_*.py` must be in `deploy-manifest.txt`.

## Config validation

- CI: `deploy/validate-release-config.sh offline`
- Host: `... host` (prints key names only)
