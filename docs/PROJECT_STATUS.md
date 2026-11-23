# ScooterCheck – Project Status

**Stand:** 2026-11-23 (Europe/Berlin)  
**Aktiver Multi-Agent-Branch:** `cursor/multi-agent-system-b100`  
**Basis dieses Checkouts:** `cursor/pedelec-auswerten-b100`  
**Hauptregel:** Nur lesende Diagnose – keine Limit-Änderung, kein Flash, keine Unlock-Kombos.

## Produkt

Native iOS-App (SwiftUI + CoreBluetooth), Bundle `com.scootercheck.app`.  
Pfad: `ios/ScooterCheck/ScooterCheck.xcodeproj`.

Kernablauf: Scooter suchen → verbinden → Manipulation prüfen → Bericht (PDF/JSON).

## Implementierter Stand (dieser Checkout)

| Bereich | Status |
|--------|--------|
| Ninebot Enc2 / Xiaomi / Navee Protokolle | vorhanden |
| BLE Identify + Capability + Device Analysis | vorhanden (`BLEIdentity/`) |
| Find / Radar / AR Signal Finder / Map | vorhanden |
| Firmware ZIP Inspector (read-only unlock hints) | vorhanden (`Integrity/`, `FirmwareZipInspectorView`) |
| Evidence / Attribution / Elevated Limit Verdict | vorhanden |
| ProtocolHistoryStore + PDF Export | vorhanden |
| Pedelec-Auswertung | vorhanden (`Pedelec/`) |
| Universal Diagnosis | vorhanden |
| Soft-Unlock UI (nur Anzeige/Settings, keine Schreib-Cmds) | vorhanden |
| Unified Investigation Hub / Flow 1.1 | **nicht in diesem Checkout** – liegt auf Stack `cursor/unified-investigation-flow-b100` (PR #102) |

## Stacked Fortschritt (andere Branches, nicht gemerged hier)

Lange Feature-Kette von BLE-Analyse über Firmware-Forensik Phase 2–2.3.4 bis Unified Investigation Flow 1.1 (Combined PDF, Archive/Resume, Identity Guards, Analysis Reuse). CI auf Tip `f306bf3` war grün nach Progress-Clamp-Fix.

## Multi-Agent-System

Konfigurationen unter `.cursor/agents/` (alle 7 angelegt).  
Gemeinsames Gedächtnis: diese Datei + `ARCHITECTURE.md`, `DEVELOPMENT_ROADMAP.md`, `AGENT_PROGRESS.md`, `OPEN_ISSUES.md`.

**Erst-Durchlauf:** fünf Spezialisten-Reviews parallel via Cloud `Task` (`explore`, inherit) + PM-Merge → priorisierte Roadmap (siehe `DEVELOPMENT_ROADMAP.md`, `AGENT_PROGRESS.md`).

## Autonomie / 4h-Zyklus

Ein Prompt allein garantiert **keine** vierstündige Ausführung. Verfügbare Hebel:

- Cloud-Agent-Follow-ups und `subscribe_timer` (event-getrieben)
- Parallele `Task`-Subagents (`explore` / `generalPurpose` / `security-review`)
- Custom Agents in `.cursor/agents/` für Cursor-IDE-Auswahl

Details: `AGENT_PROGRESS.md`.
