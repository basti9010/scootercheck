# BLE-Wächter & Scooter-Radar

## Neue Dateien
- `BLEWatchRadarCore.swift` — Modelle, Watch-/Radar-/Notification-Services, Deep Links, Live-Activity-Bridge
- `BLEWatchRadarUI.swift` — Wächter-Einstellungen, Watchlist, Radar-Controls/Banner
- `BLEWatchRadarTests.swift` — Unit-Tests (Cooldown, Fingerprint, Deep Links, Classifier-Regeln)

## Geänderte Dateien
- `BleClient.swift` — Restore Identifier, Watch-Scan ohne zweiten Central Manager
- `Info.plist` — `bluetooth-central`, URL-Scheme `scootercheck://`
- `ContentView.swift` / `BleDeviceDetailSheet` — Wächter-UI, Menü, Deep Links
- `ScooterFinderView.swift` / `BLESearchScreen.swift` — Radar starten / Controls
- `ScooterCheckApp.swift` — Notification-Delegate
- `testflight.yml` — Branch + Changelog

## Speicherung
`BLEWatchStore` persistiert `[BLEWatchTarget]` in UserDefaults (`bleWatchTargets.v1`).
Nur technische Watch-Daten (ID, Fingerprint, Optionen, Last-Seen) — kein GPS.

## Wiedererkennung
1. Exakte Peripheral-UUID
2. Fingerprint-Score ≥ 70 → sichere Notification
3. Score 45–69 → „mögliches Zielgerät“ (kein sicherer Alarm)
Name allein reicht nie.

## Scooter-Radar
Nur bei `looksLikeScooter` und Confidence ≥ medium (Service/Mfg/Modell + Heuristik).
Geglättetes RSSI, ≥3 Hits in 4 s, Cooldown 45 s/Gerät, Bundle bei mehreren Treffern.

## Background BLE
Ein `CBCentralManager` mit Restore Identifier. Watch-Scan nur wenn Targets aktiv und Phase idle/done/failed.
Kein garantierter Betrieb nach manuellem App-Kill (UI-Hinweis).

## Notifications
`BLENotificationService` → lokale UNNotifications; Cooldown pro Target; Deep Link `scootercheck://watch/<id>` / `://find`.

## Live Activity
Bridge (`BLESearchLiveActivityController`) während aktiver Suchsession.
Volle Lock-Screen-/Dynamic-Island-UI braucht ein Widget-Extension-Target (noch nicht im Projekt).

## iOS-Einschränkungen
- Background-Scan zeitlich/energiebedingt limitiert
- Kill durch Nutzer beendet Central Restoration oft
- AllowDuplicates im Background typisch aus
- Notifications brauchen User-Erlaubnis
