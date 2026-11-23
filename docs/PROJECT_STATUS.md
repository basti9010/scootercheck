# ScooterCheck – Project Status

**Stand:** 2026-11-23 ~20:20 Europe/Berlin  
**Aktiver Multi-Agent-Branch:** `cursor/multi-agent-system-b100` (PR #103) @ `a2c9329`  
**Research:** PR #104 Cycle 6 Firmware Lab (2 Dateien)  
**P0:** **VERIFIED** (`45239479743`, 324/0 @ `1a0012e`)  
**P1:** **CI VERIFIED** (`45245015142`, **350/0** @ `a2c9329`) — Hub/UI + History + Correlator inkl. Tests  
**Hauptregel:** Nur lesende Diagnose – keine Limit-Änderung, kein Flash, keine Unlock-Kombos.

## Produkt

Native iOS-App (SwiftUI + CoreBluetooth), Bundle `com.scootercheck.app`.  
Pfad: `ios/ScooterCheck/ScooterCheck.xcodeproj`.

Kernablauf: Scooter suchen → verbinden → Manipulation prüfen → Bericht (PDF/JSON).

## Implementierter Stand (dieser Checkout / multi-agent)

| Bereich | Status |
|--------|--------|
| Ninebot Enc2 / Xiaomi / Navee | vorhanden |
| BLE Identify + Capability + Device Analysis | vorhanden |
| Find / Radar / AR / Map | vorhanden |
| Firmware ZIP Inspector (legacy) | vorhanden |
| Evidence / Attribution | vorhanden |
| ProtocolHistoryStore + PackIntegrity | vorhanden (P0) |
| BLECentralCoordinator / Enc2Lifecycle / BleWriteGate | vorhanden (P0 VERIFIED) |
| Pedelec + Universal Diagnosis | vorhanden |
| ContentView modularization | Steps 1–2 DONE (~2196 LOC); Steps 3–6 pending |
| Investigation Store + Hub/UI + CombinedPDF | **MERGED** + CI green (`.investigate` menu) |
| BLE↔Firmware CrossSourceCorrelator | MVP **MERGED** + tests green |
| Cycle 6 ZT3 enc firmware lab | Reports on PR #104 (static; ISA incomplete) |

## Multi-Agent

`.cursor/agents/` · Docs: diese Datei, `AGENT_PROGRESS.md`, `AGENT_TASK_QUEUE.md`, `CI_AUTONOMY_LOOP.md`.

**Cycle 5 Agents (eingesetzt):** CI diagnose, Xiaomi protocol fix, QA, Investigation gap explore, ContentView analyze/QA, Correlation design, parallel P1-1/2/3 implementers.

## Offene Punkte

- CI auf HEAD nach Docs/Leaf-Merges beobachten (`c1262d3`+)
- Investigation Hub/UI + ContentView `.investigate` nach Foundation-Merge
- ContentView Steps 3–6
- Correlator an Forensics/Investigation anbinden nach MVP

## Cycle 11
Server diagnostics API + iOS Serverdiagnose (PR #110). Live Ghidra/TEA E2E still blocked without Freigabe.
