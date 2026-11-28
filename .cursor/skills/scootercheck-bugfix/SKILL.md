---
name: scootercheck-bugfix
description: Diagnose and fix ScooterCheck regressions with evidence-first triage, minimal diffs, and CI honesty (especially iOS XCTest and server pytest).
---

# scootercheck-bugfix

## Purpose

Fix bugs with the smallest correct change: reproduce (or cite failing CI), locate owning module, patch, add regression coverage when practical.

## When to use

- Red GitHub Actions / Codemagic / pytest.
- User-reported crash, wrong verdict, nav glitch, auth failure (on branches that contain auth).
- Flaky BLE/session lifecycle or ContentView type-checker timeouts.

## Inputs

- Symptom + expected behavior.
- Failing job URL / logs / xcresult if available.
- Branch tip SHA; related PR number.
- Memory: `KNOWN_ISSUES.md`, `TEST_STATUS.md`.

## Workflow

1. Classify layer: iOS UI, BLE stack, Integrity/Forensics, Investigation, server API, deploy scripts, auth (often **other branch** — check registry).
2. Reproduce via CI logs or local `pytest` / macOS `xcodebuild` (Linux: cannot XCTest).
3. Find owner module via `COMPONENT_REGISTRY` + code search; read surrounding tests.
4. Fix root cause; avoid drive-by refactors.
5. Add or extend a regression test when the bug is deterministic.
6. Respect CI autonomy budget (max 3 auto-fix attempts per distinct failure — `docs/CI_AUTONOMY_LOOP.md`).
7. Record residual risk in `KNOWN_ISSUES.md` if blocked.

## Outputs

- Minimal PR/commit with fix + test.
- Citation of green/red CI when available.
- Explicit UNVERIFIED if only reasoning, no run.

## Safety limits

- Do not “fix” by disabling `BleWriteGate`, auth, or path confinement tests.
- Do not silence failing assertions to greenwash CI.
- Do not touch PR #114 demo bypass as a “login fix” — use #117 line instead.
- Do not deploy prod to validate a bugfix.
