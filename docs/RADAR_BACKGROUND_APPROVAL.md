# Scooter-Radar: Hintergrundsuche, Display & Zulassungshinweise

## Ziel

Radar einmal starten, iPhone sperren dürfen, Session logisch aktiv halten und bei tatsächlich von iOS gelieferten Scooter-Advertising-Ereignissen benachrichtigen — inklusive sachlicher Zulassungshinweise für konkret identifizierte Ausführungen (z. B. bestimmte KuKirin-Varianten).

## Session vs. Scan

| Zustand | Bedeutung |
|---------|-----------|
| Radar aktiviert | Nutzer-Session angefordert (`BLERadarSessionStore`) |
| BLE-Scan aktiv | `CBCentralManager` scannt (Vordergrund oft `withServices: nil`) |
| Hintergrundscan eingeschränkt | Scan mit bekannten Service-UUIDs (Ninebot/Xiaomi) |
| Bluetooth aus | Kein Scan |
| Radar beendet | Nur über „Radar beenden“ |

Zurück-Navigation beendet die Session **nicht**.

## Hintergrundstrategie (ehrlich)

1. **Vordergrund:** `scanForPeripherals(withServices: nil)` — volle Discovery.
2. **Hintergrund:** Filter auf dokumentierte Scooter-Service-UUIDs (`NbUUID`, `XiaomiUUID`). Uneingeschränkte `nil`-Suche im klassischen `bluetooth-central`-Hintergrund wird **nicht** als zuverlässig behauptet.
3. **Live Activity:** Controller hält Session-Text; sichtbare Lock-Screen-UI braucht Widget-Extension (noch nicht im Target). iOS-26-Erweiterungen werden nicht vorgetäuscht.
4. **State Restoration:** `CBCentralManagerOptionRestoreIdentifierKey` + Fortsetzen bei persistierter Session.

Keine Silent-Audio- oder Fake-Standort-Umgehungen.

## Display

Zahnrad → Einstellungen:

- Display darf ausgehen (Standard)
- Display während der Suche eingeschaltet lassen → `isIdleTimerDisabled` nur im Vordergrund

## Zulassungskatalog

`vehicle_approval_catalog.json` + `VehicleApprovalCatalog`:

- `approved` / `noGermanApprovalDocumented` / `unconfirmed` / `modelUnidentified`
- Keine pauschale KuKirin-Familie als „unzugelassen“
- Keine erfundenen ABE-Nummern
- Fall A/B/C Notifications in `BLERadarService.prepareAlarm`

## Dateien

- `BLERadarSession.swift` — Settings, Persistenz, Display
- `VehicleApprovalCatalog.swift` + JSON
- `BLEWatchRadarCore.swift` / `BLEWatchRadarUI.swift` — Alarme, UI
- `BleClient.swift` — Radar-Scan-Modi
- Tests: `VehicleApprovalTests.swift`

## Grenzen

- Echtes iPhone / gesperrter Zustand erforderlich für Hintergrund-Validierung
- KuKirin ohne klare BLE-Namen bleibt unsicher (Fall C)
- Notifications unterliegen iOS Fokus/Berechtigungen
- Haptik nicht bei gesperrtem Display erzwungen
