# Active Tasks

**Cycle:** Development Automation 1.0  
**Branch:** `cursor/development-automation-b100`  
**Updated:** 2026-11-28

## In progress / this cycle

| ID | Task | Owner | Status |
|----|------|-------|--------|
| DA-B | Project memory under `development-memory/` | Agent C | IMPLEMENTED (derived) |
| DA-C | Eight `.cursor/skills/*/SKILL.md` | Agent C | IMPLEMENTED |
| DA-A | Architecture / AI bridge scaffolding | Agent A (parallel) | See `research/development-automation/agent_a/` |
| DA-B2 | Additional automation research | Agent B (parallel) | See `research/development-automation/agent_b/` |

## Standing constraints

- Stay on `cursor/development-automation-b100` (based on hetzner-deploy-cd).
- Do **not** touch PR #114 demo bypass.
- Do **not** deploy production.
- Do **not** claim ChatGPT/Cursor live API verified.

## Parallel product tracks (do not conflate)

| Track | Action |
|-------|--------|
| PR #117 auth recovery | Owner device-tested; wait for CI/merge verification — **do not merge #114** |
| Cycle 12 Hetzner CD | Workflow ready; user setup checklist open; no live deploy |
| ContentView Steps 3–6 | Backlog (P1) |
| Live Ghidra/TEA E2E | Blocked on Freigabe |

## Next for memory keepers

1. After #117 merges: refresh `PROJECT_STATE`, `COMPONENT_REGISTRY` (backend + auth paths), `TEST_STATUS` with CI run ids.  
2. After first Hetzner dry-run/deploy: refresh `DEPLOYMENT_STATUS` with evidence.  
3. When `services/ai-bridge/` lands: register in component JSON; keep live-gate labels honest.
