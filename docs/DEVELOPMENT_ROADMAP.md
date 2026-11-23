# ScooterCheck – Development Roadmap

**Aktualisiert:** 2026-11-23 (Europe/Berlin)  
**Quelle:** Project-Manager-Merge der parallelen Spezialisten-Reviews (iOS / Firmware / BLE / Forensik / QA).

## Widersprüche / Klärungen

| Thema | Befund |
|-------|--------|
| Investigation Hub | In Agent-Briefs / späteren PRs beschrieben; **fehlt** auf diesem Checkout – kein Widerspruch in Code, sondern Branch-Lag. |
| Dual-Source | Auf Remote-Branches vorhanden; **hier absent**. |
| Soft-Unlock | Alle Agenten einig: Detection/Observational, **kein** Unlock-BLE-Write. |
| Firmware ZIP vs BLE | Zwei getrennte Pfade; ZIP ≠ installierte Fahrzeug-FW (einhellig). |

## P0 – Sofort / Integrität

1. **Write-Disable Gate** – `BleWriteGate` (default deny) implementiert; CI-Lauf der Tests noch offen.
2. **BLE Central Ownership** – `BLECentralCoordinator` implementiert; Residual: Integrationstests Capability/GATT-Lease.
3. **Enc2 Session Lifecycle** – `Enc2SessionLifecycle` implementiert.
4. **Forensik Pack Integrity** – `PackIntegrity` implementiert; Residual: Store-Integrationstests.
5. **Hauptbranch schützen** – nur `cursor/*-b100`; kein Merge nach `main` ohne Freigabe.
6. **macOS XCTest** – Suites geschrieben, auf Linux nicht ausgeführt.

## P1 – Produktwert

1. **Investigation Flow 1.1 integrieren** (`cursor/unified-investigation-flow-b100`) – Hub, Combined PDF, Resume, Identity Guards, Analysis Reuse; kein paralleler Flow in `ContentView`.
2. **ContentView Navigation Shell extrahieren** (~3.1k LOC God-Object) ohne UX-Änderung.
3. **ZIP↔BLE Korrelation** – optionale MD5/Size-Hints (kein zweites Engine); String-Heuristiken entschärfen.
4. **XCTest Write-Disable Gate** – Assert: SoftUnlock/Integrity rufen keine Speed/Lock-Writes.
5. **macOS CI Test-Job** – `xcodebuild test` getrennt vom TestFlight-Upload.
6. **Identify Write Policy** – ein dokumentierter Find/Piep-Pfad, kein Multi-Board-Blast.

## P2 – Polish / Hygiene

1. Stock-Catalog Hygiene (F3/GT3); Catalog-Miss ≠ „Custom“.
2. Pedelec: freigeben oder bewusst prunen (`AppFeatureFlags`).
3. ENC2 Passwort Richtung Keychain statt UserDefaults.
4. Navee Read-Dump nur mit verifiziertem Profil; Xiaomi 55 AB klar als nicht auslesbar.
5. UI/Nav Smoke-Tests; Examiner-Metadaten im Export.
6. Docs/Agent-Gedächtnis nach jedem Zyklus aktualisieren.

## Autonomer Arbeitszyklus

Reihenfolge: P0 → P1 → P2 aus dieser Datei.  
Nach Teilaufgabe: nächste offene Priorität, solange die Agentenausführung/Follow-ups laufen.  
Zwischenbericht am Zyklusende. **Kein Prompt = keine 4h-Garantie.**
