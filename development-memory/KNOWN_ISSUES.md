# Known Issues & Conflicts

## Merge / PR hazards

| ID | Issue | Severity |
|----|-------|----------|
| PR-114 | Demo login bypass (`authGateEnabled=false`, `DemoAuthBootstrap`). **Do not merge.** | P0 policy |
| PR-117 | Auth recovery open; owner device-tested login, but **merge/CI still independent**. Do not treat as fully green from memory. | P0 track |
| AUTH-SRC | This checkout has **no** `backend/**/*.py` and no Login/Auth Swift files — auth is on other branches. Memory must not invent presence. | Gap |
| DOC-LAG | `docs/PROJECT_STATUS.md` / `OPEN_ISSUES.md` / `AGENT_*` still speak as if on multi-agent tip (2026-11-23). Prefer live git + this memory; update docs when convenient. | Conflict |

## Security / ops

| ID | Issue | Severity |
|----|-------|----------|
| DEPLOY-SETUP | Hetzner Environment `production`, secrets, deploy-user bootstrap, first dry-run — checklist in `docs/HETZNER_DEPLOYMENT_SETUP.md` still open. | Blocks DEPLOYED |
| AUTH-GRANTS | Live `apiTokenGrantsAdmin=true` historically CRITICAL if present; target is grants=0 + dedicated `ADMIN_API_TOKEN` (`docs/DEPLOY_SECURITY.md`). Live host state **NOT VERIFIED** from this agent. | P0 if live |
| ENC2-KEYCHAIN | ENC2 password still roadmap toward Keychain (P2 in docs). | P2 |

## Product / eng

| ID | Issue | Severity |
|----|-------|----------|
| CV-MOD | ContentView modularization Steps 3–6 backlog. | P1 |
| IOS-CI-LINUX | Linux Cloud Agents cannot run XCTest — mark UNVERIFIED until macOS CI. | Process |
| GHIDRA-LIVE | Live Ghidra/TEA E2E blocked without Freigabe / host readiness (cycles 10–12). | Ops |
| WRITE-ASSERT | Extra XCTest coverage for SoftUnlock never calling speed/lock writes — partial via `WriteDisableRegressionTests` / `BleWriteGateTests`; keep regression. | P1 hygiene |

## Memory conflicts rule

If a statement here disagrees with:

1. Current git tip on the branch in question, or  
2. A GitHub Actions / Codemagic result, or  
3. A confirmed host deploy/smoke log  

→ **trust (1)/(2)/(3)**, annotate the conflict in this file, then refresh `PROJECT_STATE` / `TEST_STATUS` / `DEPLOYMENT_STATUS`.
