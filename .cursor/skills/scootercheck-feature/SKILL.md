---
name: scootercheck-feature
description: Implement or extend ScooterCheck product features on cursor/* branches while preserving read-only diagnosis posture and existing module boundaries.
---

# scootercheck-feature

## Purpose

Ship additive product features (iOS and/or server) that fit the real architecture — Investigation, BLE identify/find, integrity/ZIP, firmware forensics UI, correlator — without inventing parallel engines or write/manipulation paths.

## When to use

- New screen/flow that extends an existing hub (Find, Investigation, Firmware, Settings).
- Wiring existing services (e.g. attach readout → InvestigationStore) rather than greenfield stacks.
- Docs + tests for a scoped feature PR on `cursor/<name>-b100` (or the active automation branch when instructed).

## Inputs

- Feature brief (user-visible goal, non-goals).
- Target branch / base (default: current checkout; do not retarget to `main`).
- Relevant memory: `development-memory/ARCHITECTURE.md`, `COMPONENT_REGISTRY.md`, `DECISIONS.md`.
- Optional: related `docs/P1-*.md` design notes.

## Workflow

1. Inventory existing entry points (`ContentView` / `AppScreen`, module folders under `ios/ScooterCheck/ScooterCheck/`, server routes if needed).
2. Prefer reuse: BLEIdentity, Integrity, FirmwareForensics, Investigation, Correlation — do not duplicate.
3. Implement additively; keep Theme/ScootDesign tokens; no redesign unless asked.
4. Add/adjust XCTest or pytest beside the change; never weaken security gates (`BleWriteGate`, pack integrity).
5. Update `development-memory/ACTIVE_TASKS.md` / registry if the component map changes.
6. Commit on the assigned branch; push when tests/docs are ready. Do not merge to `main` without Freigabe.

## Outputs

- Code + tests on the feature branch.
- Short note of screens/modules touched and test impact.
- Memory touch-up if components/status changed.

## Safety limits

- **No** BLE speed/limit/unlock writes; SoftUnlock remains observational.
- **No** firmware flash / illegal tuning activation.
- **Do not** merge or port PR **#114** demo login bypass.
- **Do not** production-deploy.
- Do not claim CI green without run evidence; Linux agents mark iOS tests UNVERIFIED.
