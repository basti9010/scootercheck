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

`IndoorMotionTracker` kombiniert:

1. **CLHeading (Kompass)** bevorzugt → geglättetes Heading (stärkeres EMA)
2. **Device Motion (Yaw)** nur als Fallback, wenn kein Kompass (kein Mischen)
3. **CMPedometer** → Schritte; Heading wird **pro Schritt** gelesen (Kurven sichtbar)
4. **Fallback User-Acceleration** → Peak-Detektor, wenn Pedometer fehlt
5. **GPS-Position** nur bei Genauigkeit ≤ 8 m (Outdoor) — Indoor-GPS zerstört den Laufweg sonst

Stehen bleiben erzeugt **keine** künstliche Bewegung (nur Heading-Updates ohne Schritte).

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
- Zellgröße = `viewport.spanMeters / cols` → Heatmap und Pfad teilen denselben Viewport
- Weiche lokale Füllung nur in Nachbarschaft gemessener Zellen (keine weite Extrapolation)
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
