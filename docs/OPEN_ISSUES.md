# ScooterCheck – Open Issues

Aktualisiert nach Multi-Agent-Erstanalyse (2026-11-23 Europe/Berlin).

## P0

- [ ] BLE: sekundäre CBCentralManager vs BleClient serialisieren
- [ ] Enc2: Session bei Disconnect invalidieren
- [ ] Forensik: Pack-Manifest + SHA über Export-Artefakte; sealed packs
- [ ] Write/Manipulation dauerhaft gated (QA-Policy)
- [ ] Kein Merge nach `main` ohne Freigabe

## P1

- [ ] Unified Investigation Flow 1.1 integrieren (`cursor/unified-investigation-flow-b100`)
- [ ] ContentView Navigation-Shell extrahieren
- [ ] ZIP↔BLE Korrelations-Hints; String-Heuristiken entschärfen
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
