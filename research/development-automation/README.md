# ScooterCheck Development Automation 1.0

Orchestration layer: ChatGPT/MCP ↔ AI Bridge ↔ Cursor Cloud Agents API ↔ GitHub/CI.

## Status labels

Use only: PLANNED | IMPLEMENTED | TESTED | END_TO_END_VERIFIED | DEPLOYED  
Epistemic: CONFIRMED | HYPOTHESIS | INCOMPLETE | NOT VERIFIED

Live gates (must not be claimed from mocks alone):

- CURSOR_API_LIVE_VERIFIED
- MCP_CLIENT_VERIFIED
- CHATGPT_CONNECTION_VERIFIED
- CHATGPT_TO_CURSOR_E2E_VERIFIED

## Layout (target)

- `development-memory/` — derived project memory (git/CI remain source of truth)
- `.cursor/skills/` — reusable ScooterCheck skills
- `services/ai-bridge/` — Task Orchestrator + Cursor client + MCP
- `research/development-automation/` — architecture, matrix, reports

## Related

- PR #117 — P0 auth recovery (device login tested by owner; CI/merge verify separately)
- PR #114 — demo bypass — **do not merge**
