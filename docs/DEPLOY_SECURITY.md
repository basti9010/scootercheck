# Deploy security model (Cycle 12)

## Threat model (Actions → SSH)

| Threat | Mitigation |
|--------|------------|
| Unauthorized deploy | GitHub Environment `production` + required reviewers; `confirm_deploy` input; workflow_dispatch only |
| Secret leak in logs | Never echo SSH keys / tokens; smoke redacts bodies |
| Host key MITM | `StrictHostKeyChecking=yes` + `HETZNER_SSH_KNOWN_HOSTS` |
| Over-privileged CI SSH | Dedicated `scootercheck-deploy` user; limited sudoers for systemctl only |
| Concurrent deploys | Workflow concurrency + remote `flock` |
| Shared API token as admin | `API_TOKEN_GRANTS_ADMIN=0`; diagnostics need `ADMIN_API_TOKEN` / JWT admin |
| Shell via API | Not provided; diagnostics refuse open auth |

## Known prod risk

Live health previously showed `apiTokenGrantsAdmin=true`. Ops must set `API_TOKEN_GRANTS_ADMIN=0` and a dedicated admin token before treating diagnostics as safe.

## Rotation

1. Generate new deploy key → update `authorized_keys` + GitHub secret  
2. Rotate `ADMIN_API_TOKEN` / `API_TOKEN` in `/etc/scootercheck` only  
3. Revoke old keys in Hetzner / GitHub Environment  

## Process isolation

See systemd unit `ProtectSystem=strict`, `ProtectHome=true`, `NoNewPrivileges`, `ReadOnlyPaths` for Ghidra/decrypt. Do not weaken for CD.
