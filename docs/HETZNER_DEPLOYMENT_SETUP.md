# Hetzner deployment setup (iPad-friendly)

**Status: NOT DONE until you finish every checkbox below.**  
Cloud Agents / CI cannot complete this for you. No live SSH from this doc.

Keep this page short. Do steps in order. Prefer Safari/GitHub + Hetzner Console on iPad; use a Mac only where marked.

---

## 0. Goal

GitHub Actions (manual `workflow_dispatch`) → SSH as a **non-root** deploy user → release under `/opt/scootercheck/firmware-analysis` → restart `scootercheck-fw` → healthcheck. Rollback via workflow or script.

Secrets stay in GitHub Environment `production` and on the VPS under `/etc/scootercheck/`. Never paste private keys into chat, issues, or logs.

---

## 1. GitHub Environment `production`

On GitHub → **Settings → Environments → New environment** → name: `production`.

| Setting | Value |
|---------|--------|
| Required reviewers | At least one trusted person (you or a co-owner) |
| Wait timer | Optional (e.g. 5 min) |
| Deployment branches | Limit to the release branch(es) you trust (e.g. `main` / cycle release branch) |

Do **not** put deploy secrets in repository-wide Secrets alone. Bind them to Environment **`production`** so the approval gate applies.

---

## 2. Environment secrets (names + purpose)

Create these as **Environment secrets** on `production`.  
**Never** commit values. **Never** invent keys in docs/examples.

| Secret name | Purpose |
|-------------|---------|
| `DEPLOY_HOST` | Hostname or IP of the VPS (e.g. `api.tuningscanner.de`) |
| `DEPLOY_USER` | Least-privilege SSH user (not `root`) |
| `DEPLOY_SSH_KEY` | Private key for that user (PEM). Generated once — see §3 |
| `DEPLOY_KNOWN_HOSTS` | One-line `ssh-keyscan` / known_hosts entry for `DEPLOY_HOST` — see §5 |
| `DEPLOY_PATH` | App path on server (default `/opt/scootercheck/firmware-analysis`) |
| `DEPLOY_SERVICE` | systemd unit name (default `scootercheck-fw`) |

Optional (only if the workflow needs them; prefer reading from server env files instead):

| Secret name | Purpose |
|-------------|---------|
| `HEALTH_URL` | Loopback health URL used **on the server** after SSH (e.g. `http://127.0.0.1:8088/health`) |

**Not** GitHub secrets (live only on VPS, mode `600`/`640`):

- `/etc/scootercheck/firmware-analysis.env` — `API_TOKEN`, `ADMIN_API_TOKEN`, `JWT_SECRET`, …
- `/etc/scootercheck/decrypt.env` — decrypt tooling paths / keys

See also: [`DEPLOY_SECURITY.md`](./DEPLOY_SECURITY.md).

---

## 3. Generate deploy SSH key ONCE

Do this **yourself** in Hetzner Console (web terminal) or on a Mac. Not in CI. Not in a Cloud Agent.

**On Mac (recommended):**

1. Open Terminal.
2. Create a dedicated key (ed25519):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/scootercheck_deploy -C "scootercheck-github-deploy" -N ""
```

3. Keep `~/.ssh/scootercheck_deploy` private. You will paste **only the private file contents** into GitHub secret `DEPLOY_SSH_KEY`.
4. Copy the **public** key (`~/.ssh/scootercheck_deploy.pub`) to the VPS `authorized_keys` for the deploy user (§4).

**On Hetzner Console:** same `ssh-keygen` as the deploy user (or as root only to place the pubkey), then download/copy the private key into GitHub Environment secrets via a secure channel on your device. Delete any temporary copy on the VPS after install.

Rotate = generate a new keypair, update `authorized_keys` + GitHub secret, remove the old pubkey.

---

## 4. Deploy user (least privilege — not root)

On the VPS (you, via Console or existing admin SSH):

1. Create user if missing, e.g. `deploy` (or reuse a dedicated non-root account).
2. Home `~/.ssh/authorized_keys` = **only** the deploy public key from §3. Mode `700` / `600`.
3. Grant **only** what deploy needs via `sudoers` (NOPASSWD limited commands), for example:
   - `systemctl restart scootercheck-fw`
   - `systemctl status scootercheck-fw`
   - `systemctl stop scootercheck-fw` / `start` (rollback)
   - Optional: rsync/write into `/opt/scootercheck/firmware-analysis` (or ACL/group ownership)
4. **Do not** allow unrestricted root shell from Actions.
5. **Do not** sync-delete `/var/lib/scootercheck/*` (jobs, decrypted, decompiled, stock-fw).

Legacy script note: `server/firmware-analysis/deploy/phase1-rollout.sh` still defaults to `root@…` — CD must override with `DEPLOY_USER` / non-root. See security report.

---

## 5. Capture `known_hosts`

On a Mac (or any trusted machine that can reach the host):

```bash
ssh-keyscan -T 10 -t ed25519,rsa YOUR_DEPLOY_HOST
```

1. Verify the fingerprint against Hetzner Console / a prior trusted login.
2. Paste the **exact** line(s) into Environment secret `DEPLOY_KNOWN_HOSTS`.
3. Workflow must use `StrictHostKeyChecking=yes` + that file.  
   **Forbidden:** `StrictHostKeyChecking=no` or disabling host-key checks.

Legacy `accept-new` in `phase1-rollout.sh` is **not** acceptable for GitHub Actions CD — pin hosts.

---

## 6. Workflow: `workflow_dispatch` + approval

Expected flow (Agent A wires the YAML; this is the security contract):

1. Open **Actions** → deploy workflow → **Run workflow**.
2. Job targets Environment **`production`** → GitHub asks for **reviewer approval**.
3. After approve: checkout → load secrets → SSH with pinned known_hosts → dry checks → release → restart → health.
4. Default / dry path must **not** mutate prod unless an explicit confirm input is set (mirror `CONFIRM_PROD_DEPLOY=YES`).

Until the workflow exists and §1–§5 are done, treat CD as **not configured**.

---

## 7. Rollback

| Method | When |
|--------|------|
| Workflow “rollback” / `workflow_dispatch` with rollback input | Preferred after CD lands |
| Script: `phase1-rollout.sh` rollback path / remote restore of `*.bak-fw-*` | Manual ops with Freigabe |
| Documented steps | `server/firmware-analysis/docs/phase22h-rollback-plan.md` |

Rules:

- Restore **code tree** only under `/opt/scootercheck/firmware-analysis`.
- Leave `/etc/scootercheck/*.env` and `/var/lib/scootercheck/**` alone unless ops explicitly rotates secrets.
- Re-check `curl -fsS http://127.0.0.1:8088/health` on the host after rollback.

---

## 8. Setup complete checklist

Setup is **NOT completed** until **all** of these are true:

- [ ] Environment `production` exists with **required reviewers**
- [ ] All secret **names** in §2 are present (values set by you — never by agents)
- [ ] Deploy key generated **once** by you; public key only on VPS
- [ ] Deploy user is **non-root** with limited sudo
- [ ] `DEPLOY_KNOWN_HOSTS` captured and verified
- [ ] Deploy workflow uses `workflow_dispatch` + environment protection
- [ ] You successfully ran a **dry** dispatch (no prod mutate) OR confirmed dry-run script path
- [ ] You know how to rollback (§7)

If any box is open → **setup incomplete**. Do not claim DEPLOYED / AVAILABLE.

---

## Related

- [`DEPLOY_SECURITY.md`](./DEPLOY_SECURITY.md) — auth, secrets, threat model summary  
- [`../server/firmware-analysis/docs/process-isolation.md`](../server/firmware-analysis/docs/process-isolation.md) — systemd hardening  
- [`../research/cycle12/agent_c/REPORT_SECURITY.md`](../research/cycle12/agent_c/REPORT_SECURITY.md) — Cycle 12 Agent C report  
