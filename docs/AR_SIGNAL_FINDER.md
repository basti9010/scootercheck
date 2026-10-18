# AR Signal-Finder

Native iOS-Erweiterung des ScooterCheck Signal-Finders: Bluetooth-RSSI wird an ARKit-Posen (iPhone-Standort) verankert und als weiche, bodennahe Signalfläche dargestellt.

## Implementierte Komponenten

| Komponente | Datei | Rolle |
|------------|-------|--------|
| Surface-Modes | `BLESearchMotionCore.swift` | `Live` · `Heatmap` · `AR` (+ optionale Outdoor-`Karte`) |
| Gemeinsame ARSession | `BLESearchVisualTracker.swift` | Eine Session für Pose + ARSCNView; horizontale Planes im AR-Modus; `sessionEpoch` bei Neuausrichtung |
| AR-Daten / Farben / Hinweise | `BLESearchARCore.swift` | Feste RSSI-Farbskala, Best-Zone mit Hysterese, Guidance, Floor-Textur, Settings/Onboarding |
| AR-UI | `BLESearchARView.swift` | ARSCNView-Heatmap, Pfad, bester Messbereich, Minikarte, Onboarding |
| Orchestrierung | `BLESearchEngine.swift` | Gleiche BLE-Sitzung; AR-Samples nur bei gesundem Tracking; Pause; keine zweiten Scanner |
| Integration | `BLESearchScreen.swift` | Segment `Live \| Heatmap \| AR`, Optionen, Wechsel ohne Neustart |

## Wichtige Grenzen (kein Fake-Ortung)

- RSSI liefert **keine Peilrichtung**. AR-Punkte = iPhone-Pose zum Messzeitpunkt.
- Keine exakte Scooter-Position, keine Meter-Entfernung zum Sender.
- Bei eingeschränktem Tracking werden **keine neuen** AR-Samples gespeichert.
- Nach `sessionEpoch`-Wechsel (Neuausrichten) keine ungeprüfte Fusion alter/neuer Koordinatensysteme für die Best-Zone.
- Floor-Heatmap interpoliert nur lokal um gemessene Zellen; ungemessene Bereiche bleiben transparent.

## Noch auf einem realen iPhone zu prüfen

1. Normale Bewegung → Heatmap folgt dem Weg, Spur stabil.
2. Drehung auf der Stelle → Flächen bleiben raumfest.
3. Zurücklaufen → Farben bleiben, lokale Updates möglich.
4. Stark schwankendes RSSI → Live reagiert, AR-Fläche ruhig; Best-Zone springt nicht.
5. Trackingverlust (dunkel / zu schnell) → Hinweis, keine Fehlanker.
6. Wechsel Live ↔ Heatmap ↔ AR → eine Sitzung, ein BLE-Scan.
7. Gerät kurz unsichtbar → kein erfundener RSSI; Historie bleibt.
8. Performance / Thermik bei längerer AR-Nutzung.
9. Kamera-Berechtigung und Erst-Onboarding (3 Schritte).

## Bedienung (Kurz)

- Segment **AR** öffnet die Kameraansicht.
- Minikarte antippen → Heatmap (Messung läuft weiter).
- Optionen: Heatmap/Pfad/Best-Zone/Minikarte, Transparenz, Rohwerte, Neu ausrichten.
