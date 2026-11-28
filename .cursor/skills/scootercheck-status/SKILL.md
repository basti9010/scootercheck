---
name: scootercheck-status
description: Produce an honest ScooterCheck project status snapshot from git/CI/deploy and derived development-memory — never invent live ChatGPT/Cursor API verification.
---

# scootercheck-status

## Purpose

Summarize where the project actually is: branch tip, open PRs, test/deploy labels, conflicts between docs and reality.

## When to use

- Start of a cycle / automation run.
- User asks “what’s done / blocked?”
- Before planning features that depend on auth, Ghidra, or CD.
- After merges — refresh memory.

## Inputs

- Current `git` branch + SHA.
- Open PRs (especially **#117**, **#114**).
- Latest CI run ids if available.
- `development-memory/*` and `docs/PROJECT_STATUS.md` (docs may lag).

## Workflow

1. Read `PROJECT_STATE.md`, `ACTIVE_TASKS.md`, `TEST_STATUS.md`, `DEPLOYMENT_STATUS.md`, `KNOWN_ISSUES.md`.
2. Reconcile with live git/PR/CI; if conflict → trust git/CI/deploy, note in KNOWN_ISSUES.
3. Report using only allowed labels: PLANNED | IMPLEMENTED | TESTED | END_TO_END_VERIFIED | DEPLOYED; epistemic CONFIRMED | HYPOTHESIS | INCOMPLETE | NOT VERIFIED.
4. Explicitly state PR #117 owner device-tested login vs independent CI/merge verification.
5. Explicitly state PR #114 must not be merged.
6. Refresh JSON/markdown memory when status changed and you are allowed to commit.

## Outputs

- Short status briefing (branch, P0 blockers, deploy readiness, auth line).
- Optional memory file updates.

## Safety limits

- **Never** claim `CHATGPT_CONNECTION_VERIFIED`, `CURSOR_API_LIVE_VERIFIED`, `MCP_CLIENT_VERIFIED`, or `CHATGPT_TO_CURSOR_E2E_VERIFIED` from mocks/docs alone.
- Never claim DEPLOYED / E2E without evidence.
- Do not treat historical CI greens on old SHAs as current tip status.
- Memory is derived — do not override git as source of truth.
