# ScooterCheck – Development Memory (Phase B)

**Derived** project memory for agents and humans. Not a second source of truth.

## Source of truth

| Layer | Authority |
|-------|-----------|
| Git history / branch tips | Code & docs that exist |
| GitHub Actions / Codemagic | Test & CI outcomes |
| Deploy workflows + host state | Production / Hetzner |
| Owner device tests | UX claims that CI cannot prove |

This directory **summarizes** the above. If memory disagrees with git/CI/deploy, **git/CI/deploy win**. Record the conflict in [`KNOWN_ISSUES.md`](./KNOWN_ISSUES.md) and refresh the relevant memory file.

## Files

| File | Role |
|------|------|
| `PROJECT_STATE.md` / `project_state.json` | Branch, cycle, PRs, epistemic labels |
| `ARCHITECTURE.md` | Real layers on this checkout |
| `COMPONENT_REGISTRY.md` / `component_registry.json` | Inventory of modules |
| `DECISIONS.md` | Locked product/security decisions |
| `KNOWN_ISSUES.md` | Open risks, conflicts, gaps |
| `TEST_STATUS.md` | What is VERIFIED vs UNVERIFIED |
| `DEPLOYMENT_STATUS.md` | Hetzner / TestFlight readiness |
| `ACTIVE_TASKS.md` | Current automation / cycle work |

## Honesty labels

Use only: `PLANNED` | `IMPLEMENTED` | `TESTED` | `END_TO_END_VERIFIED` | `DEPLOYED`  
Epistemic: `CONFIRMED` | `HYPOTHESIS` | `INCOMPLETE` | `NOT VERIFIED`

Do **not** claim from this tree alone:

- `CURSOR_API_LIVE_VERIFIED`
- `MCP_CLIENT_VERIFIED`
- `CHATGPT_CONNECTION_VERIFIED`
- `CHATGPT_TO_CURSOR_E2E_VERIFIED`

## Refresh rule

After a meaningful merge, CI green/red, or deploy: update JSON + the matching markdown in the same PR/commit when practical.
