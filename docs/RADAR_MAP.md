# Radar-Karte

Interaktive MapKit-Ansicht dokumentierter BLE-Sichtungen während Radar-Sessions.

## Wichtige Grenzen

- Die Karte zeigt den **Smartphone-Standort** beim Empfang, nicht die Scooter-Position.
- Keine Standorte aus RSSI ableiten.
- Speicherung und Standort sind **opt-in** (Einstellungen).
- Alarmschwelle steuert nur Benachrichtigungen, nicht die Erfassung.
- Keine simulierten Fahrzeugbewegungen im Zeitverlauf.

## Dateien

| Datei | Rolle |
|---|---|
| `RadarMap/RadarMapModels.swift` | Sessions, Sightings, Identities, Filter, Hidden |
| `RadarMap/RadarMapStore.swift` | Application-Support JSON Persistenz |
| `RadarMap/RadarMapRecorder.swift` | Aggregation, Location, Repeat-Notify |
| `RadarMap/RadarMapKitCanvas.swift` | MKMapView (iOS 16) |
| `RadarMap/RadarMapView.swift` | UI, Filter, Löschen, Ausblenden |
| `RadarMapTests.swift` | Aggregation, Repeat-Filter, Hide/Delete |

## Aggregation

Zusammenhängende Empfänge innerhalb von `sightingGapMinutes` (Default 15) = **eine** Sichtung. Der Wiederholungsfilter zählt nur getrennte Sichtungen mit `identityMatchConfidence == confirmed`.

## Löschen vs. Ausblenden

- Löschen entfernt Radar-Sichtungsdaten (nicht Prüfberichte / bekannte Scooter / Wächter).
- Ausblenden behält Historie, unterdrückt Kartenanzeige und normale Radar-Alarme; BLE-Scan bleibt aktiv.

## Hub

`ScooterFindDestination.radarMap` → Karte „Radar-Karte“ unter „E-Scooter finden“.
