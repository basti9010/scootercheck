# Cycle 8 – Phase 1 / PM Baseline

Stand: 2026-11-23 Europe/Berlin

## CI (PR #105 / C7 tip)

| Run | SHA | Conclusion |
|-----|-----|------------|
| [45254685766](https://github.com/basti9010/scootercheck/actions/runs/45254685766) | `4e73931` | **FAILURE** — `FirmwareCryptoAssessor` missing |
| [45255389488](https://github.com/basti9010/scootercheck/actions/runs/45255389488) | `b60df88` | queued/in progress (FIX-1) |

### FIX-1 (applied, counts toward max-3)

Port `FirmwareCryptoAssessor.swift` from unified lineage; wire pbxproj.  
Tip: `b60df88`. Remaining budget: 2 fixes.

## Host / toolchain on this Cloud VM

| Probe | Result |
|-------|--------|
| `~/.ssh/hetzner_scootercheck` | **absent** |
| `/opt/ghidra`, `GHIDRA_HOME`, `analyzeHeadless` | **absent** |
| `/opt/scootercheck` | **absent** |
| FastAPI in system Python | **not installed** |
| Cursor app secrets | **empty list** |

**Verdict:** NO ACCESS TO HETZNER HOST FROM THIS ENVIRONMENT.  
DEPLOYED / END_TO_END_VERIFIED against production: **not claimable** from this VM.

## Deploy dry-run (local)

`CONFIRM_PROD_DEPLOY` unset → `deploy/phase1-rollout.sh` correctly aborted before remote:  
local unit tests `204` ran with **3 failures + 8 errors** (optional angr/capstone paths without packages) + 12 skipped.  
**No remote changes.** Treat full server suite as **INCOMPLETE** until deps installed in a controlled venv (Agent A/D).

## Parallel agents

| Agent | ID |
|-------|-----|
| A Server | bc-dbf93606-ec97-5a33-9eb7-2c065477e68a |
| B Ghidra | bc-97bfc305-0234-59c4-9155-86759480979c |
| C iOS | bc-f2116c4f-b9c9-56c3-a3d4-bb7e6d2af9c5 |
| D QA | bc-c8d1ac3c-9319-543b-8da4-72dd048bc579 |

PR #106: https://github.com/basti9010/scootercheck/pull/106 (stacked on #105)
