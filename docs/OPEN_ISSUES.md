# ScooterCheck – Open Issues

Aktualisiert nach Multi-Agent-Erstanalyse (2026-11-23 Europe/Berlin).

## P0

- [x] BLE: sekundäre CBCentralManager vs BleClient serialisieren (`BLECentralCoordinator`) — QA-Nachbesserungen Lease-Leak/Preempt erledigt
- [x] Enc2: Session bei Disconnect invalidieren (`Enc2SessionLifecycle`)
- [x] Forensik: Pack-Manifest + SHA (`PackIntegrity`) — ensurePack seal + Thumbs ausgeschlossen
- [x] Write/Manipulation Gate (`BleWriteGate`, default deny) — Transport-Reads bleiben UART-TX
- [ ] Kein Merge nach `main` ohne Freigabe
- [ ] XCTest auf macOS/CI ausführen — Workflow existiert; **BLOCKED** nach 3 Auto-Fixes (Xcode 26 Test-Compile: LiveTelemetryTests, BLESearchMotionCoreTests, BLEWatchRadarTests `minHitsForAlarm`)
- [ ] P0 CI-Verifikation (BLECentralCoordinator / Enc2 / PackIntegrity / BleWriteGate) — UNVERIFIED

## P1

- [ ] Unified Investigation Flow 1.1 integrieren (`cursor/unified-investigation-flow-b100`)
- [ ] ContentView Navigation-Shell extrahieren
- [ ] ZIP↔BLE Korrelations-Hints; String-Heuristiken entschärfen — **Design:** `docs/P1-3_BLE_FIRMWARE_CORRELATION.md` (Implementierung offen)
- [ ] XCTest Write-Disable Gate (Ninebot/Xiaomi)
- [ ] macOS CI: `xcodebuild test` Job
- [ ] Identify: ein Find/Piep-Pfad statt Multi-Board-Blast

## P2

- [ ] Stock-Catalog Hygiene; Catalog-Miss ≠ Custom
- [ ] Pedelec Flag-Entscheidung
- [ ] ENC2 Passwort → Keychain
- [ ] Dual-Source / Firmware-Forensik-Stack konsolidieren (Remote-Branches)
- [ ] Photos in Pack hashen; Examiner-Metadaten
- [ ] UI/Nav Smoke-Tests

## Branch-/Integrationslage

- Unified Investigation Flow und Dual-Source **nicht** in diesem Checkout.
- Firmware hier = ZIP Inspector + Stock/CustomDiff; tiefere Forensik auf Phase-2.x-Branches.
- Linux Cloud Agent: **keine** lokale XCTest-Ausführung.

## Bekannte Fixes (Kontext anderer Branches)

- Investigation progress clamp / flush (`f306bf3` auf Unified-Branch) – nach Integration relevant.
