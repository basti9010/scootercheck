# Deploy & runtime security (Cycle 12)

Owner checklist for Hetzner CD + firmware-analysis auth. **No secrets in this file.**

Companion setup steps: [`HETZNER_DEPLOYMENT_SETUP.md`](./HETZNER_DEPLOYMENT_SETUP.md).

---

## 1. Auth posture: `apiTokenGrantsAdmin` risk

Public `/health` may expose:

| Field | Secure target |
|-------|----------------|
| `apiTokenGrantsAdmin` | `false` |
| `adminApiTokenConfigured` | `true` |
| `authMode` | `separated` |
| `authSecurityOk` | `true` |
| `authSecurityCritical` | `false` |

### Why `apiTokenGrantsAdmin=true` is dangerous

When `API_TOKEN_GRANTS_ADMIN=1`, the **shared** `API_TOKEN` (also used by the iOS app for normal API calls) becomes an **admin** credential. Anyone who obtains the app/API token can hit admin routes (stock, catalogs, job admin, …).

### Required ops fix (on VPS env — not in GitHub chat)

In `/etc/scootercheck/firmware-analysis.env`:

1. Set a dedicated **`ADMIN_API_TOKEN`** (long random; never equal to `API_TOKEN`).
2. Set **`API_TOKEN_GRANTS_ADMIN=0`** (must stay 0).
3. Keep **`TRUST_API_TOKEN_CLIENT_ID=0`**.
4. Keep **`JWT_SECRET`** aligned with ScooterCheck auth.
5. Restart `scootercheck-fw`, then verify health flags above (loopback on host).

In-tree defaults already prefer grants=0; **live prod historically lagged** (Cycle 10 LIVE P0). Treat any live `apiTokenGrantsAdmin=true` as **CRITICAL** until fixed.

---

## 2. Diagnostics = true-admin only

`/v1/diagnostics/status` and `/v1/diagnostics/selftest*` must accept **only**:

- JWT with `role=admin`, or  
- Header `X-ScooterCheck-Token` equal to **`ADMIN_API_TOKEN`**

Must **refuse**:

- Open auth (`auth=open`)
- Shared `API_TOKEN` even when `apiTokenGrantsAdmin=true`
- Any path that elevates solely via `API_TOKEN_GRANTS_ADMIN`

Implementation: `diagnostics_routes.enforce_diagnostics_admin` (stricter than generic `require_admin`).

iOS Serverdiagnose must use the dedicated admin token field — not the shared API token.

---

## 3. No shell API

Hard rule for the public/admin HTTP surface:

- **No** endpoint that runs caller-supplied shell strings.
- Subprocess helpers (decrypt, Ghidra headless, TEA probes) use **fixed argv lists**, `shell=False`, timeouts.
- Diagnostics status: existence/config checks only — **no env dumps**, no secret values.
- Selftest: fixed probes only; no user argv; single-flight / rate hints as documented in `diagnostics_routes.py`.

If a future “remote exec” feature is proposed → **reject**. Deploy stays on SSH + systemd, not HTTP shell.

---

## 4. Secrets never in logs

| Do | Don’t |
|----|--------|
| Log “token configured: yes/no” | Log token / JWT / PEM contents |
| Redact Authorization / X-ScooterCheck-Token in access logs | Echo `EnvironmentFile` in CI |
| GitHub mask secrets via Environment secrets | `echo "$DEPLOY_SSH_KEY"` in workflows |
| Fail closed if a secret is missing | Print `.env` in health or diagnostics |

Workflow authors: never `cat` private keys into step summaries. Prefer `ssh-agent` / file with `0600` in `$RUNNER_TEMP`, delete after job.

App/worker: health and diagnostics already avoid secret values — keep it that way.

---

## 5. Secret rotation checklist

Run after suspected leak, staff change, or scheduled rotation:

1. **Deploy SSH key** — new keypair; update VPS `authorized_keys`; update GitHub `DEPLOY_SSH_KEY`; remove old pubkey; revoke old private copies.
2. **`API_TOKEN`** — generate new; update VPS env; update iOS/ops clients; restart worker.
3. **`ADMIN_API_TOKEN`** — generate new (≠ API_TOKEN); update VPS env + admin clients; restart.
4. **`JWT_SECRET`** — rotate with ScooterCheck auth service in lockstep; expect session invalidation.
5. **LLM / decrypt secrets** — rotate provider keys; update `/etc/scootercheck/*` only on host.
6. **GitHub Environment** — confirm reviewers still correct; remove stale collaborator access.
7. Verify: health `authSecurityOk=true`; diagnostics still works with new admin token; shared token still **denied** on diagnostics.
8. Record rotation date in ops notes (not in git with values).

---

## 6. Preventing unauthorized deploys

### GitHub Environment protection

| Control | Required |
|---------|----------|
| Environment name | `production` |
| Required reviewers | ≥ 1 human |
| Deployment branch policy | Restricted |
| Secrets scoped to environment | Yes |
| Trigger | `workflow_dispatch` only for prod mutate (no push-to-main auto-prod) |

### Confirm gates (scripts & workflows)

- Default = **dry-run** (no remote writes, no restart).
- Live mutate only when explicit confirm is set, e.g. `CONFIRM_PROD_DEPLOY=YES` or workflow input `confirm=YES`.
- Do not default confirm from an unchecked checkbox.

### Host identity

- Pin `known_hosts`; `StrictHostKeyChecking=yes`.
- Ban: `StrictHostKeyChecking=no`, blank `DEPLOY_KNOWN_HOSTS`, TOFU `accept-new` in Actions.

### Identity on the box

- SSH as non-root deploy user.
- Limited sudoers for systemctl / release path only.
- Service runs as `User=scootercheck` (see systemd unit) — separate from deploy user.

### What CD must never do

- Delete or “clean” `/var/lib/scootercheck/**`
- Overwrite `/etc/scootercheck/*.env` from the repo
- Disable host-key checking
- Run as root GitHub Actions without environment approval

---

## 7. Systemd hardening (document — do not weaken)

Unit: `server/firmware-analysis/deploy/scootercheck-fw.service`

Already enabled (keep):

- `NoNewPrivileges=true`
- `PrivateTmp=true`
- `ProtectSystem=strict`
- `ProtectHome=true`
- Bind uvicorn to `127.0.0.1:8088` (nginx terminates TLS)

Optional further hardening (ops may add **only if** tested; never remove the above):

| Directive | Intent |
|-----------|--------|
| `ProtectKernelTunables=true` | Block `/proc/sys` writes |
| `ProtectKernelModules=true` | No module load |
| `ProtectControlGroups=true` | Limit cgroup influence |
| `LockPersonality=true` | Reduce personality syscall abuse |
| `RestrictSUIDSGID=true` | No suid elevation |
| `SystemCallArchitectures=native` | No foreign arch binaries |
| `CapabilityBoundingSet=` (empty or minimal) | Drop caps if still functional |

Do **not** set `ProtectSystem=false` / remove `ReadOnlyPaths` to “make deploy easier”. Fix permissions instead.

Details + verify commands: [`../server/firmware-analysis/docs/process-isolation.md`](../server/firmware-analysis/docs/process-isolation.md).

---

## 8. Related code pointers

- Auth health: `server/firmware-analysis/app.py` (`authMode`, grants CRITICAL)
- Diagnostics gate: `server/firmware-analysis/diagnostics_routes.py`
- Rollout dry-run: `server/firmware-analysis/deploy/phase1-rollout.sh` (`CONFIRM_PROD_DEPLOY`)
- Env template: `server/firmware-analysis/.env.example`
- Threat model (Actions→SSH): [`../research/cycle12/agent_c/REPORT_SECURITY.md`](../research/cycle12/agent_c/REPORT_SECURITY.md)
