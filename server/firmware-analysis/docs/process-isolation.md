# Process isolation & forensic reproducibility (Cycle 10)

Ops checklist for the firmware worker. **No secrets.** Host verification requires SSH/admin access (not available from Cloud Agent VMs without deploy keys).

## Systemd unit (repo: `deploy/scootercheck-fw.service`)

| Hardening | Expected | Purpose |
|-----------|----------|---------|
| `NoNewPrivileges=true` | active | Block privilege escalation |
| `PrivateTmp=true` | active | Per-service `/tmp` (analyzer temp files isolated) |
| `ProtectSystem=strict` | active | Read-only OS; writes only via `ReadWritePaths` |
| `ProtectHome=true` | active | No home-dir access |
| Bind `127.0.0.1:8088` | active | Not public without nginx |

Verify on host (ops):

```bash
systemctl show scootercheck-fw -p NoNewPrivileges -p PrivateTmp -p ProtectSystem -p ProtectHome
curl -fsS http://127.0.0.1:8088/health | jq '{authMode,authSecurityOk,authSecurityCritical,apiTokenGrantsAdmin,adminApiTokenConfigured}'
```

## Residual (I1)

Ghidra / r2 / unicorn / angr still share the service UID. There is **no** nsjail/seccomp wrapper in-tree. Treat deeper sandboxing as a host change, not a small API diff.

## Temp / job storage

- Job dirs created via `_secure_mkdir` → mode `0o750` (best-effort).
- Prefer `WORK_DIR` / `PLAINTEXT_STORE` / `DECOMPILE_STORE` under `/var/lib/scootercheck/…` (see `.env.example`), not world-writable `/tmp`, on prod.
- Downloads confined to store roots (Cycle 9 path confinement).

## Ghidra result reproducibility

- Normalize + compare: `ghidra_reproducibility.compare_runs` (strips timestamps / export order).
- Persist `analysisProfile` / hash next to exports (`ghidra_decompile`).
- Same input + same profile → equal semantic hashes; divergence ⇒ semantic (not cosmetic) change.
- Live headless proof needs `GHIDRA_HOME` + host access; `ghidraConfigured=true` on public `/health` is **not** execution proof.
