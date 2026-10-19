# Radar-UI: kompakte Oberfläche

## Geändert

| Datei | Änderung |
|-------|----------|
| `BLEWatchRadarUI.swift` | Statuskarte ohne Zahnrad; Wartezustand mit Puls; Settings nur Display |
| `ScooterFinderView.swift` | Header-Untertitel ehrlich; ein Zahnrad; Waiting-View |
| `BLERadarSession.swift` | `compactTitle` / `compactSubtitle` / `headerCapabilityLine`; kürzere Display-Labels |
| `BLEWatchRadarTests.swift` | Persistenz + Status-Copy |
| `testflight.yml` | Branch-Whitelist |

## Entfernt von der Haupt-/Settings-UI

- Zweites Einstellungszahnrad neben dem Status
- Untertitel „Session bleibt aktiv beim Verlassen…“
- Technische Zeile „CoreBluetooth meldet…“ auf der Hauptseite
- „Radar aktiv“-Toggle im Settings-Sheet
- Verschachtelte Settings (Benachrichtigungen, Signal, Cooldown, langer Hintergrund-Text) aus dem Sheet — Werte bleiben in `BLERadarUserSettings` gespeichert und wirksam

## Bottom Sheet

`presentationDetents([.height(260)])` + inset-grouped List mit zwei Display-Optionen und Mint-Haken. Footer: „Die manuelle Displaysperre bleibt jederzeit möglich.“

## Keep-Awake

`UIApplication.shared.isIdleTimerDisabled` in `BLERadarSessionStore.applyDisplayMode()` — nur wenn Session angefordert, Modus `.keepAwake` und `applicationState == .active`. Bei „Radar beenden“ oder Hintergrund: Timer wieder normal.

## Hintergrundstatus

`BLERadarService.refreshScanState()` setzt `BLERadarScanState`; UI liest nur die kompakten Strings. `UIBackgroundModes` / `bluetooth-central` entscheidet, ob „Radar läuft im Hintergrund weiter“ gezeigt wird.
