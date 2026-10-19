# Universelle E-Scooter-Diagnose

## Ziel

Herstellerübergreifende, **ausschließlich lesende** Diagnose für bekannte und bisher unbekannte E-Scooter — ohne Fake-Online-Treffer und ohne simulierte Messwerte.

## Architektur (Wiederverwendung)

| Komponente | Rolle |
|---|---|
| `BleClient` | Einzige BLE-Verbindungsverwaltung (Enc2 / Xiaomi Dump) |
| `ScooterProtocolRegistry` | Gebündelte + signierte Online-Profile |
| `ProtocolCompatibilityEngine` | Advertising/GATT-Merkmale ↔ Profile |
| `UniversalScooterDetectionService` | Passive Stufen 1–2 + lokale Stufe 4 |
| `OnlineProtocolDiscoveryService` | Optionale Recherche (`SCOOTER_PROTOCOL_DISCOVERY_ENDPOINT`) |
| `GenericGATTReader` / `BLEGattDeepAnalysis` | Nur sichere GATT-/DIS-Reads |
| `ReadOnlyDiagnosticEngine` | Snapshot nur aus empfangenen Werten |
| `ScooterEvidenceEngineBridge` | Metadaten in `IntegrityReading.physicalMarks` |
| `VehicleApprovalCatalog` | Deutscher Zulassungsstatus nach Modellzuordnung |

Keine zweite `CBCentralManager`-Diagnose-Schicht.

## Unterstützungsgrade

1. **fullNative** — Ninebot Enc2 / Xiaomi Plaintext über bestehenden `BleClient`
2. **gattReadonly** — Device Information Service (SIG)
3. **researchHintOnly** — Hersteller erkannt (z. B. KuKirin, Navee, VMAX, …), **kein** freigegebenes Lesprotokoll
4. **none** — kein kompatibles Profil

Die Nennung eines Herstellers in der Profil-JSON bedeutet **nicht**, dass Diagnose möglich ist.

## Signierte Online-Profile

- Payload: `ScooterDiagnosticProfileFile` JSON
- Signatur: Header `X-ScooterCheck-Signature` (HMAC-SHA256 Hex über Rohbytes)
- Nur `verified: true` + App-Build-Kompatibilität werden übernommen
- Unsignierte / ungültige Antworten → verworfen oder nur als Recherchehinweis angezeigt
- Keine ausführbaren Skripte, keine Schreibbefehle in Profilen

Ohne konfiguriertes Backend: ehrliche Meldung, **keine** simulierten Treffer.

## Radar

- Passiv: Alarm / Zulassungshinweis / Trefferliste
- **Kein** automatischer Diagnose-Connect im Hintergrund
- Aktion „Diagnose / Protokoll prüfen“ startet `UniversalDiagnosisView` auf Nutzerwunsch

## Grenzen

- Verschlüsselte / auth-geschützte Protokolle werden nicht umgangen
- Fehlende Werte → „Nicht verfügbar“
- Unbekannte Referenzwerte werden nicht als Serien-Soll ausgegeben
- iOS-Hintergrund-Scan bleibt service-gefiltert (siehe Radar-Doku)

## Backend (optional)

`SCOOTER_PROTOCOL_DISCOVERY_ENDPOINT` — POST mit technischen Kennungen (Herstellerhinweis, Service-UUIDs, Namenspräfix). Antwort: signierte Profildatei oder Recherchehinweis-JSON.

## Tests

`UniversalDiagnosisTests` deckt u. a. ab: natives Ninebot-Matching, Research-only, GATT-DIS, Signatur-Reject/Accept, Plan-Block für Research-only.
