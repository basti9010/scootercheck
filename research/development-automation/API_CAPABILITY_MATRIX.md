# API Capability Matrix — Development Automation 1.0

**Agent:** B+F  
**Branch:** `cursor/development-automation-b100`  
**Columns:** Documented | Available-in-account | Implemented-in-repo | Live-tested | Notes  

Legend for **Available-in-account**: `YES` / `NO` / `UNKNOWN` / `ACCOUNT_DEPENDENT`.  
**Live-tested** means this agent run exercised the remote surface — not “docs say it works.”  
**Do not claim `CHATGPT_CONNECTION_VERIFIED`.** An MCP server in-repo ≠ ChatGPT connected for a specific chat.

Sources (official, verified for writeup wording):

- [Add custom MCP server](https://developers.openai.com/api/docs/guides/custom-mcp-server) — Plugins → Add custom MCP; SSE / streaming HTTP; OAuth / no-auth / mixed; workspace permissions & Lockdown apply.
- [MCP authentication (OAuth 2.1)](https://developers.openai.com/plugins/build/auth) — MCP auth spec; `/.well-known/oauth-protected-resource`; PKCE S256; redirect `https://chatgpt.com/connector_platform_oauth_redirect` (or connector oauth callback form); CIMD / DCR / static client.
- Repo: `.github/workflows/deploy-hetzner.yml`, `docs/HETZNER_DEPLOYMENT_SETUP.md`, `docs/DEPLOY_SECURITY.md`.

---

## 1. Cursor API / Cloud Agents

| Capability | Documented | Available-in-account | Implemented-in-repo | Live-tested | Notes |
|------------|------------|----------------------|---------------------|-------------|-------|
| Cloud Agent Task / subagents | YES (product) | UNKNOWN | Partial (`.cursor/agents/`, research cycles) | NO | Agent personas in-repo; external drive API not wired in MCP yet |
| Cursor IDE agent prompts | YES | ACCOUNT_DEPENDENT | YES | NO | Local IDE; not MCP |
| Background / Cloud Agent MCP host tools | YES (runtime) | ACCOUNT_DEPENDENT | N/A (host) | NO | This run uses host MCP; not ScooterCheck product API |
| Public Cursor “start agent via REST” for ScooterCheck automation | UNKNOWN | UNKNOWN | NO (Agent A may stub client) | NO | Treat as UNKNOWN until official API + account entitlement confirmed |
| PR / CI observation from Cursor GitHub integration | YES | ACCOUNT_DEPENDENT | YES (workflows exist) | NO | Observation ≠ deploy |

---

## 2. ChatGPT / OpenAI MCP

| Capability | Documented | Available-in-account | Implemented-in-repo | Live-tested | Notes |
|------------|------------|----------------------|---------------------|-------------|-------|
| Custom MCP via ChatGPT Plugins → Add custom MCP server | YES | ACCOUNT_DEPENDENT | Scaffold (`services/ai-bridge/mcp/`) | NO | Workspace permissions / Lockdown may block — **ACCOUNT_DEPENDENT** |
| Transport: SSE | YES | ACCOUNT_DEPENDENT | Planned / stub HTTP tool surface | NO | Official: SSE and streaming HTTP supported |
| Transport: streaming HTTP | YES | ACCOUNT_DEPENDENT | Stub FastAPI tool dispatch | NO | Production MCP URL typically ends in `/mcp` |
| Auth: OAuth 2.1 + MCP auth spec | YES | ACCOUNT_DEPENDENT | Role model + bearer scaffold (not full IdP) | NO | Resource metadata `/.well-known/oauth-protected-resource`; PKCE S256 |
| OAuth redirect `https://chatgpt.com/connector_platform_oauth_redirect` | YES | ACCOUNT_DEPENDENT | Documented only | NO | Auth server must support `iss` when using stable redirect |
| Auth: no-auth | YES | ACCOUNT_DEPENDENT | **Rejected for writes** | NO | ScooterCheck policy: no anonymous write; prefer OAuth for prod |
| Auth: mixed (initialize/list open; tools gated) | YES | ACCOUNT_DEPENDENT | Tools always gated in scaffold | NO | Mixed is optional; our scaffold still requires token on tool calls |
| CIMD / DCR / static OAuth client | YES | ACCOUNT_DEPENDENT | NO (IdP out of scope Phase A) | NO | Wire when hosting behind public HTTPS |
| `readOnlyHint` / write confirmation UX | YES | ACCOUNT_DEPENDENT | Annotations on tool defs | NO | ChatGPT treats non-readOnly as write → user confirm |
| Install plugin + `@` in a chat + successful tool call | YES | ACCOUNT_DEPENDENT | NO | NO | **≠ CHATGPT_CONNECTION_VERIFIED** until proven in a specific chat |
| MCP server alone proves ChatGPT connection | NO (anti-claim) | N/A | N/A | N/A | Explicitly false |

---

## 3. GitHub

| Capability | Documented | Available-in-account | Implemented-in-repo | Live-tested | Notes |
|------------|------------|----------------------|---------------------|-------------|-------|
| Actions workflows (iOS / server / TestFlight / Deploy) | YES | UNKNOWN | YES | NO | Present under `.github/workflows/` |
| `workflow_dispatch` Deploy Hetzner | YES | UNKNOWN | YES | NO | Requires Environment secrets + reviewers |
| Environment `production` approval gate | YES | UNKNOWN | Documented + workflow `environment: production` | NO | Owner setup checklist; MCP must not bypass |
| Read check runs / workflow status via API | YES (GitHub REST/GraphQL) | UNKNOWN | Stub `get_ci_status` | NO | Treat GH/CI text as untrusted (prompt injection) |
| Create issues / PRs from automation | YES | UNKNOWN | NO (out of MCP write set for Phase A) | NO | Prefer human/PM for merges |
| Secrets in Environment | YES | UNKNOWN | Names only in docs | NO | Never return secret values via MCP tools |
| `gh` CLI write from agents | Policy: read-only in cloud agents | N/A | N/A | N/A | Cloud agent `gh` is read-only |

---

## 4. Hetzner

| Capability | Documented | Available-in-account | Implemented-in-repo | Live-tested | Notes |
|------------|------------|----------------------|---------------------|-------------|-------|
| SSH release deploy via GitHub Actions | YES (`docs/HETZNER_*`, workflow) | UNKNOWN | YES (scripts + workflow) | NO | Not exercised this run |
| Direct MCP → SSH / host shell | NO (forbidden) | N/A | NO | NO | Hard ban: no shell API; no MCP deploy |
| Health / diagnostics on VPS | YES | UNKNOWN | YES (server code) | NO | Admin-only diagnostics |
| Console / Cloud API server lifecycle | Hetzner product docs | UNKNOWN | NO in ai-bridge MCP | NO | Ops outside MCP |
| Bootstrap deploy user | YES (script in deploy/) | UNKNOWN | YES | NO | One-time host setup |

---

## 5. ScooterCheck ai-bridge MCP tools (implemented scaffold)

| Tool | Documented | Available-in-account | Implemented-in-repo | Live-tested | Notes |
|------|------------|----------------------|---------------------|-------------|-------|
| `scootercheck_get_project_status` | YES (this matrix) | N/A (local scaffold) | YES | YES (pytest) | Role: READ |
| `scootercheck_create_task` | YES | N/A | YES | YES (pytest) | Role: TASK_WRITE |
| `scootercheck_start_task` | YES | N/A | YES | YES (pytest) | Role: TASK_WRITE; READ → 403 |
| `scootercheck_get_task_status` | YES | N/A | YES | YES (pytest) | Role: READ |
| `scootercheck_get_task_report` | YES | N/A | YES | YES (pytest) | Role: READ; sanitized |
| `scootercheck_list_tasks` | YES | N/A | YES | YES (pytest) | Role: READ |
| `scootercheck_get_ci_status` | YES | N/A | YES | YES (pytest) | Role: READ; untrusted text tagged |
| `scootercheck_prepare_fix` | YES | N/A | YES | YES (pytest) | Role: APPROVAL |
| `scootercheck_cancel_task` | YES | N/A | YES | YES (pytest) | Role: TASK_WRITE |

---

## 6. Cross-cutting security rows

| Control | Documented | Available-in-account | Implemented-in-repo | Live-tested | Notes |
|---------|------------|----------------------|---------------------|-------------|-------|
| No anonymous write | YES (policy) | N/A | YES | YES (pytest 401) | |
| Role gates READ vs TASK_WRITE | YES | N/A | YES | YES (pytest 403) | |
| No secrets in tool results | YES | N/A | YES (redaction helper) | YES (unit) | |
| Prompt-injection treatment of GH/CI text | YES | N/A | YES (untrusted envelope) | YES (unit) | |
| Prod deploy only via GH Environment approval | YES | UNKNOWN | Enforced by workflow design; MCP has no deploy tool | NO | |

---

## Summary (Phase A)

| Surface | Verdict |
|---------|---------|
| ChatGPT MCP | **Documented**; account availability **ACCOUNT_DEPENDENT**; scaffold **in-repo**; connection **not verified** |
| Cursor external API | Mostly **UNKNOWN** / account-dependent; personas in-repo |
| GitHub | Workflows **implemented**; account secrets/reviewers **UNKNOWN** this run |
| Hetzner | CD path **implemented** in repo; **not** live-tested; MCP must not SSH |
| ai-bridge MCP tools | Nine tools stubbed + authz tests (see Agent B report) |
