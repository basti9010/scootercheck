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

Getrennte Funktionen — nie vermischt.

### Löschen
- ⋯-Menü → „Einzelne Sichtung“ / „Gesamte Gerätehistorie“ + Bestätigung.
- Entfernt nur Radar-Sichtungsdaten (nicht Prüfberichte / bekannte Scooter / Wächter).
- Erneute Erkennung danach ist erlaubt.

### Ausblenden
- ⋯ → „Gerät dauerhaft ausblenden“.
- Historie bleibt; Karte und normale Radar-Alarme unterdrückt; BLE-Scan + Wächter unverändert.
- **Identity-bound** nur bei `confirmed` Match; sonst **nur Peripheral-ID** (Hinweis im UI).
- Setting „Sichtungen ausgeblendeter Geräte weiterhin speichern“ (Default aus).
- Liste unter Radar-Karten-Einstellungen → „Ausgeblendete Geräte“ (Einblenden / Sichtungen löschen).
- Filter „Ausgeblendete Geräte anzeigen“ → graue Marker.

## Hub

`ScooterFindDestination.radarMap` → Karte „Radar-Karte“ unter „E-Scooter finden“.
