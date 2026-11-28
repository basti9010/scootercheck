# ScooterCheck Development Automation — Phase A Architecture Inventory

**Cycle:** Development Automation 1.0  
**Branch:** `cursor/development-automation-b100`  
**Agent:** B+F (MCP + Security foundation)  
**Status:** Phase A inventory (repo-grounded). No production deploy.  
**Claim ban:** Do **not** mark `CHATGPT_CONNECTION_VERIFIED` from this inventory alone.

---

## 1. Repository structure

| Path | Role |
|------|------|
| `ios/ScooterCheck/` | Native SwiftUI + Core Bluetooth app (read-only diagnosis) |
| `backend/` | Placeholder / thin Python tree (tests cache present; app package empty in this checkout) |
| `server/firmware-analysis/` | FastAPI firmware forensics worker (jobs, JWT/API tokens, Ghidra/TEA/YARA) |
| `server/firmware-analysis/deploy/` | Hetzner release scripts, smoke, rollback, CI gate matrix |
| `catalogs/` | Stock / reference catalog assets |
| `docs/` | Architecture, deploy security, Hetzner setup, CI autonomy, roadmaps |
| `.github/workflows/` | iOS XCTest, TestFlight, server firmware tests, Deploy Hetzner |
| `research/cycle7…12/` | Multi-agent research cycles + synthesis |
| `research/development-automation/` | **This initiative** — Phase A docs + agent reports |
| `development-memory/` | Derived project memory (git/CI remain source of truth) |
| `services/ai-bridge/` | Agent A orchestrator core (`ai_bridge/`) + Agent B `mcp/` surface |
| `.cursor/agents/` | Cursor IDE specialist prompts (PM, iOS, FW, BLE, forensic, UI, QA) |
| `codemagic.yaml` | Alternate iOS CI (Codemagic) |

### Layer sketch (product)

```
SwiftUI (iOS) ──BLE──► Scooter (read-only)
       │
       └──HTTPS──► firmware-analysis (Hetzner) ── jobs / diagnostics / catalogs
```

### Layer sketch (development automation — target)

```
ChatGPT (custom MCP) ─┐
Mobile Dev Center UI ─┼──► ai-bridge MCP (authz) ──► orchestrator stubs / Agent A core
Cursor Cloud Agents ──┘         │
                                ├── GitHub Actions status (read)
                                ├── Task create/start/cancel (write, gated)
                                └── Production deploy: NEVER direct — GitHub Environment approval only
```

---

## 2. Auth (product + automation)

### Product: `server/firmware-analysis`

| Mechanism | Use |
|-----------|-----|
| Bearer JWT (`JWT_SECRET`) | User-owned jobs; `role=admin` for admin routes |
| `X-ScooterCheck-Token` = `API_TOKEN` | Shared app/API token (non-admin by default) |
| `X-ScooterCheck-Token` = `ADMIN_API_TOKEN` | True admin (preferred) |
| `API_TOKEN_GRANTS_ADMIN` | Must stay `0` in prod (CRITICAL if `1`) |
| `TRUST_API_TOKEN_CLIENT_ID` | Must stay `0` (spoofable client id) |
| Open auth | Only when no tokens/JWT configured (dev) |

Diagnostics enforce **true-admin only** (stricter than generic admin). See `docs/DEPLOY_SECURITY.md`.

### Automation: `services/ai-bridge/mcp`

| Role | Capability |
|------|------------|
| `READ` | Status / list / CI / reports |
| `TASK_WRITE` | create / start / cancel tasks |
| `APPROVAL` | prepare_fix (human-gated fix prep) |
| `ADMIN` | All of the above + admin-only ops |

**Hard rule:** no anonymous **write**. Tool dispatch requires a bearer token; missing → `401`; insufficient role → `403`.  
Secrets must never appear in tool results (redact tokens, PEMs, env dumps).

---

## 3. Firmware analysis

- FastAPI app: `server/firmware-analysis/app.py`
- Job ownership: `job_auth.py` (JWT `user:<sub>` preferred)
- Capabilities: ZIP-safe upload, Capstone/YARA/Unicorn, optional angr/Ghidra, TEA decrypt via fixed argv (no shell API)
- Deploy layout: `/opt/scootercheck/releases/<sha>` + symlink; data dirs outside release
- Epistemics: encrypted without TEA → incomplete; ZIP ≠ installed vehicle FW

---

## 4. CI

| Workflow | Trigger | Notes |
|----------|---------|-------|
| `ios-unit-tests.yml` | PR/push iOS paths | macos-15 XCTest; Linux agents mark UNVERIFIED |
| `server-firmware-tests.yml` | server/deploy paths | Mandatory gate for deploy docs; no SSH/prod |
| `testflight.yml` | dispatch / main iOS | Apple secrets; separate from server CD |
| `deploy-hetzner.yml` | **workflow_dispatch only** | SHA + `confirm_deploy` + Environment `production` |

iOS XCTest is **non-blocking** for server deploy. Autonomy loop: `docs/CI_AUTONOMY_LOOP.md` (max 3 auto-fix attempts per failure class).

---

## 5. Deploy (Hetzner)

- Manual CD only; no push-triggered prod writes
- Secrets live in GitHub Environment `production` (names only in docs)
- Host: SSH as `scootercheck-deploy` (not root); host-key checking on
- Smoke + automatic rollback on failure
- Setup checklist: `docs/HETZNER_DEPLOYMENT_SETUP.md` (owner must complete; repo alone does not deploy)

**Automation constraint:** MCP/`prepare_fix` must **not** call live deploy. Production remains GitHub Environment approval only.

---

## 6. Agents

| Source | Role |
|--------|------|
| `.cursor/agents/*.md` | IDE agent personas |
| Cloud `Task` `subagent_type` | Parent maps specialists via prompt |
| `docs/AGENT_TASK_QUEUE.md` / `AGENT_PROGRESS.md` | PM coordination |
| Research cycles `research/cycleN/agent_*` | Parallel investigation reports |
| Development Automation | Agent A = orchestrator core; Agent B+F = MCP + security (this work) |

---

## 7. Phase A gaps / coordination

| Item | Status |
|------|--------|
| `services/ai-bridge/ai_bridge/` orchestrator core | Agent A owns; B places MCP under `mcp/` only |
| ChatGPT custom MCP connection | Documented capability; **not** live-verified here |
| Cursor Cloud/Agent API for external task drive | See capability matrix — many cells UNKNOWN until account probe |
| Mobile Development Center | Alternative path if ChatGPT MCP blocked (ACCOUNT_DEPENDENT) |

---

## 8. Evidence class legend

| Tag | Meaning |
|-----|---------|
| REPO | Present in this checkout |
| DOC | Official vendor docs cited |
| ACCOUNT_DEPENDENT | Needs workspace/plan/admin settings |
| UNKNOWN | Not probed this run |
| LIVE | Actually exercised against remote system |
| CHATGPT_CONNECTION_VERIFIED | **Forbidden claim** unless a specific chat proves plugin install + tool call |
