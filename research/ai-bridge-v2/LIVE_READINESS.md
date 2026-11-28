# AI Bridge 2.0 — Live Readiness Audit

**Date (UTC):** 2026-11-28  
**Branch:** `cursor/ai-bridge-v2-b100` (from `cursor/development-automation-b100` @ `11547e8`)  
**Prior cycle:** Development Automation 1.0 / PR #118

## A1. Repository

| Item | Status |
|------|--------|
| PR #118 | OPEN, MERGEABLE, head `11547e8`, base `cursor/hetzner-deploy-cd-c12-b100`, AI Bridge Tests SUCCESS |
| PR #117 | OPEN, MERGEABLE, head `305a362`, XCTest + TestFlight SUCCESS (auth recovery) |
| PR #114 | Must **not** merge (demo bypass) |
| Default product lineage | Cycle 12 / Hetzner CD stack |
| AI Bridge path | `services/ai-bridge/` (reuse — no second bridge) |

## A2. Cursor Cloud Agents API (official docs)

Source: https://cursor.com/docs/cloud-agent/api/endpoints (public beta v1)

| Capability | Documented | Notes |
|------------|------------|-------|
| Auth | YES | Bearer or Basic; API key from Dashboard → API Keys |
| `POST /v1/agents` | YES | Create agent + initial run; `prompt.text` required; `repos[]`, `autoCreatePR` |
| `GET /v1/agents` | YES | List |
| `GET /v1/agents/{id}` | YES | Agent detail |
| `GET /v1/agents/{id}/runs/{runId}` | YES | Run status: CREATING, RUNNING, WAITING_FOR_BACKGROUND_WORK, FINISHED, ERROR, CANCELLED, EXPIRED |
| `POST .../runs/{runId}/cancel` | YES | Cancel active run; 409 if not cancellable |
| `POST /v1/agents/{id}/runs` | YES | Additional runs / steer |
| Stream endpoints | YES | Rate limits on open streams (429) |
| Webhooks | Coming soon (v1); legacy v0 still has statusChange | Treat as optional |

**Custom IDE agents:** not selectable by name via this API — a coordinating Cloud Agent prompt must delegate roles in-text.

## A3. Secrets

| Secret | Present in this agent env | Storage target (owner) |
|--------|---------------------------|-------------------------|
| `CURSOR_API_KEY` | **NO** | Server-only env / Hetzner systemd `EnvironmentFile` / GitHub Environment secret for deploy — **never** iOS, dashboard JS, git, chat |
| `AIBRIDGE_TOKENS` / session secrets | Prototype bearer map | Same server-only store |
| `GITHUB_TOKEN` (read) | Optional for PR/CI status | Fine-scoped token or GitHub App — server only |

**CURSOR_API_LIVE = BLOCKED_MISSING_CREDENTIAL** until the owner places `CURSOR_API_KEY` in the protected server env and a live smoke succeeds.

## Integration conflicts

- Do not merge #114 into this line.
- #117 auth line is independent; do not regress demo bypass.
- AI Bridge must remain a **separate** process from firmware-analysis.

## Epistemic gates (end of cycle 2.0)

| Gate | Value |
|------|-------|
| CURSOR_API_LIVE_VERIFIED | false (`BLOCKED_MISSING_CREDENTIAL`) |
| MCP_CLIENT_VERIFIED | false |
| CHATGPT_CONNECTION_VERIFIED | false |
| CHATGPT_TO_CURSOR_E2E_VERIFIED | false |
| MOBILE_DASHBOARD_VERIFIED | false (local HTTP smoke only) |
| MOBILE_DEVICE_VERIFIED | false |
| PRODUCTION_DEPLOYED | false |

Live smoke evidence path (no secrets): `services/ai-bridge/data/live_evidence/live_smoke_result.json` when run with default dirs, or `AI_BRIDGE_LIVE_EVIDENCE_DIR`.
