---
name: scootercheck-ios
description: ScooterCheck iOS specialist workflow for SwiftUI, CoreBluetooth integration points, Investigation/Find/Firmware surfaces, persistence, and XCTest.
---

# scootercheck-ios

## Purpose

Implement or review iOS work inside `ios/ScooterCheck/` using real module boundaries and the read-only product posture.

## When to use

- SwiftUI navigation (`ContentView`, `ScootNavigation`, hubs).
- BLE identify / search / radar / AR / Ninebot Enc2 client usage.
- Investigation Store/UI, Protocol history/PDF, Firmware inspector/forensics UI.
- XCTest under `ScooterCheckTests`.

## Inputs

- Screen or bug scope.
- Branch instructions.
- Design tokens: `Theme.swift`, `ScootDesign.swift`.
- Agents companion: `.cursor/agents/ios-developer.md` (role prompt).

## Workflow

1. Map `AppScreen` / menu entry and state owners (`AppSettings`, stores).
2. Reuse services: `BleClient`, `BLECentralCoordinator`, `BleWriteGate`, `InvestigationStore`, `FirmwareServerAnalysisClient`, correlator — no second BLE stack.
3. Prefer additive Swift files + pbxproj membership consistent with existing groups (FirmwareForensics, Investigation, …).
4. Keep UX unless redesign requested; ContentView extractions must preserve behavior (see modularization docs).
5. Tests: place in `ScooterCheckTests`; ensure scheme TestAction includes new suites (historical empty TestAction pitfall on auth line).
6. Push → rely on `ios-unit-tests.yml` for VERIFIED; mark UNVERIFIED on Linux-only agents.

## Outputs

- iOS code + XCTest changes.
- Notes: navigation hazards, persistence, BLE lease/session impact.

## Safety limits

- Default deny writes; never enable unlock/limit commands.
- Do not embed demo credentials or port `#114` `DemoAuthBootstrap`.
- Auth/login sources may be absent on hetzner-deploy lineage — check out #117 line if the task is auth.
- No secrets in Info.plist / source; fail closed.
