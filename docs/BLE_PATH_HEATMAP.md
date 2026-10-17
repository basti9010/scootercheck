# BLE-Suche: Pfadrekonstruktion & Heatmap

Funktionale Überarbeitung der Indoor-/Outdoor-Suchdarstellung. Visuell bleibt die ScooterCheck-CI (Dark Theme, Mint). Verhalten orientiert sich an klarer Laufweg-Darstellung (Pfad, Wendungen, Strecke, Zentrierung, Heatmap entlang des Wegs).

## Neue Dateien

| Datei | Rolle |
|-------|--------|
| `BLESearchMotionCore.swift` | `IndoorMotionTracker`, `SearchPathReconstructor`, `SearchViewportController`, `HeatmapPlacementEngine`, `OutdoorMapTracker`, Surface-Mode |
| `BLESearchMotionCoreTests.swift` | Geradeaus, Kurve, Kehrtwendung, Stillstand, Heatmap-an-Pfad, Viewport, Strecke |
| `docs/BLE_PATH_HEATMAP.md` | Diese Doku |

## Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `BLESearchEngine.swift` | Path-Snapshot, Relativ/Karte, PDR-Sync, GPS-Fusion, Streckenmetriken, Auto-Karten-Vorschlag |
| `BLESearchScreen.swift` | Relativ/Karte-Umschalter, Pfad-Heatmap-Canvas, MapKit-Overlay, Zentrieren, Messungen/Strecke/Dauer |
| `project.pbxproj` | Neue Sources/Tests eingebunden |

## Indoor-Pfadrekonstruktion

`IndoorMotionTracker` + optional `IndoorVisualTracker` (ARKit):

1. **Kamera / ARKit World Tracking** (optional, Standard an) → Meter & Drehungen auf der Bodenebene, wie bei WLAN-Analyzer-Apps
2. **Gyro / Device-Motion** als Fallback bzw. Ergänzung bei eingeschränktem Tracking
3. **Kompass** nur Initial-Heading + weiche Ankerung
4. **CMPedometer.distance** kalibriert Schrittlänge; bei aktivem Kamera-Tracking keine Doppelzählung
5. **Stillstand** → kein Drift; GPS-Fusion nur outdoor ≤ 8 m

UI: Toggle **Kamera-Tracking** mit Kamerasymbol (grün = aktiv, rot = inaktiv z. B. zu dunkel).  
Messpunkte (`BLEBreadcrumb`) behalten RSSI vom Aufnahmezeitpunkt.

Neue Datei: `BLESearchVisualTracker.swift`

### Karten-Zoom & Heatmap (Feedback-Fixes)

- Region folgt dem **Bounding-Box des PDR-Pfads** (Start ~18 m, wächst mit Strecke) — kein fixer 90-m-Stadtblick
- Heat-/Messpunkte kommen aus **relativer ENU-Position**, nicht aus rohem Indoor-GPS (verhindert Kritzel-Haufen)
- Auto-Kartenmodus nur bei GPS ≤ 8 m

## Richtungswechsel

- Heading wird mit Mindestwinkel gefiltert (`minHeadingChangeDegrees`)
- `SearchPathReconstructor` verdichtet den Rohpfad: Mindestabstand + Winkel-Schwellwert
- 3-Punkt-Glättung liefert lesbare Kurven statt Sensornamen-Zacken

Ergebnis: Geradeaus → gerade Linie; Rechtsdrehung → sichtbarer Knick; Kehrtwendung → zurücklaufender Ast.

## Heatmap am Bewegungsverlauf

`HeatmapPlacementEngine`:

- Messpunkte nutzen `relativeX` / `relativeY` vom rekonstruierten Tracker
- **Feste Welt-Zellgröße** (`cellSizeMeters`) — Farben wandern nicht mit dem Zoom
- Pro Rasterzelle gilt der **letzte Messwert**; ältere Orte bleiben unverändert, bis du denselben Platz erneut misst
- Weiche lokale Füllung nur in leeren Nachbarzellen (überschreibt nie gemessene Zellen)
- Trail = geglättete Polyline des Laufwegs

## Zentrierung

`SearchViewportController`:

- Bounding-Box über bisherigen Pfad + aktuellen Punkt
- Soft-Follow (EMA) gegen hektisches Springen
- Button **Zentrieren** → `recenterViewport()` auf aktuellen Punkt (Indoor + Map-Region)

## Apple Map (Outdoor)

- Umschalter **Relativ / Karte**
- `OutdoorMapTracker` projiziert ENU-Pfad auf `CLLocationCoordinate2D` relativ zum GPS-Origin
- `BLESearchMapCanvas` (MapKit): dunkle Karte, reduzierte POIs, Mint-Polyline, Heat-Annotations, aktueller Punkt
- Bei brauchbarem GPS (≤ 15 m) einmaliger Auto-Vorschlag Kartenmodus; manuell überschreibbar

## Limits (bewusst)

- Indoor ist **relative Annäherung**, keine Zentimeter-Ortung
- Magnetometer/Yaw kann in Gebäuden driften
- Schrittlänge ist Heuristik
- Schlechter GPS: Relative Ansicht bleibt nutzbar; keine exakte Position behauptet
- UI-Hinweis: „Relative Suchfläche – keine exakte Ortung“
