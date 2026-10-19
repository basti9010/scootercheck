# Globales Proportions-Refinement

## Tokens (`Theme.swift`)

| Bereich | Vorher (ca.) | Nachher |
|--------|--------------|---------|
| pageTitle | 25 | 21 |
| sectionTitle | 18 | 16 |
| cardTitle | 16.5 | 15 |
| body / caption / meta | 15.5 / 13 / 12 | 14.5 / 12.5 / 11.5 |
| Card-Padding | 16 | 12 |
| Seitenrand | 20 | 18 |
| Section-Spacing | 24 | 18 |
| Button-Höhe | 48 | 44 |
| Radius medium | 16 | 12 |
| App-Header | 68 | 58 |
| Segment | normal | `.controlSize(.small)` via `scootSegmented()` |

## Komponenten

- `FindSubpageHeader` — Default-Titel = `sectionTitle` (weniger dominant)
- `ScootFunctionCard` — flacher, Meta-Untertitel
- `ScootEmptyStateCard` — neuer kompakter Leerzustand
- `ScootPrimaryButton` / `ScootSecondaryButton` — schlanker
- `scootCard()` — weniger Padding
- Copyright auf Funktionsseiten (Signal-Finder) entfernt

## Geprüfte / angepasste Flächen

Signal-Finder, Gerätesuche, Find-Hub, ContentView-Leerzustände, Segment-Controls (ContentView, BLESearchScreen), Radar-Menüs (via Theme-Propagation).
