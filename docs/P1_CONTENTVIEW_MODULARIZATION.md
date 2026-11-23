# P1-2 ContentView Modularization Plan

Source: [Analyze ContentView modularization](bc-585c5d7b-f442-5641-8b6a-6b03b3a145db)  
Stand: 2026-11-23 Europe/Berlin

## Baseline

- `ContentView.swift` was ~3111 LOC navigation shell + auslesen orchestrator.
- Keep single `BleClient`, `AppScreen` routing, sheet flags, connect/finalize in shell.

## Extraction order

| # | Target | Status |
|---|--------|--------|
| 1 | Leaf views (device card, BLE detail, signal, FactRow, ScoreRing) | **DONE** (`AuslesenDeviceViews.swift`, `IntegrityResultChrome.swift`) |
| 2 | Protocol history overview | BACKLOG |
| 3 | Side menu shell | BACKLOG |
| 4 | Home/scan surface | BACKLOG |
| 5 | Result + subject | BACKLOG |
| 6 | Vergleichstest coordinator (optional) | BACKLOG — after Investigation Flow clarity |

## Constraints

- No behavior/UX change
- One `BleClient`; Watch/Radar attach only from shell
- Prefer file moves over new god-objects
- New files must stay in Xcode app target
