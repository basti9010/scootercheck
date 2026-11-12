# Recherche: Häufig / „gut“ getunte E-Scooter (Priorisierung Auslese)

Stand: 2026-11-12  
Zweck: **Priorisierung der ScooterCheck-Diagnose** (was lohnt sich auszulesen), **keine** Tuning-Anleitung.

## Methodik (Proxy, keine Polizeistatistik)

Es gibt **keine öffentliche Rangliste „Top 100 getunte Scooter“** mit Fallzahlen. Diese Liste ist eine **Heuristik** aus:

1. **Tooling-Reife** — ScooterHacking Utility / SHFW / CFW-Kompatibilität ([Joey’s Wiki](https://joeybabcock.me/wiki/ScooterHacking_Utility), [bastelpichi compatibility](https://wiki.bastelpichi.de/compatibility.html))
2. **Marktangebot** — WebApp-/Chip-Kompatibilität in DACH-Angeboten (Ninebot Software vs. Xiaomi Hardware)
3. **Community-Volumen** DE — z. B. G30-Gruppe ~11 k, Xiaomi ~6 k, Tuning-Gruppe ~8,5 k (Stand ~06/2025, Community-Übersichten)
4. **Aktuelle Verkaufs-/Diskussionspräsenz** — Max G3 als „Scooter des Jahres 2025“-Favorit in DE-Foren
5. **„Gut“ getunt** = in der Szene **häufig + technisch gut unterstützt** (viele Lösungen, viele Berichte), nicht „legal“ oder „empfehlenswert“

**Einschränkung:** Viele getunte Hochleistungsroller (Dualtron, Kaabo, VSETT) sind ab Werk schnell / anders gedrosselt; offene BLE-Karten fehlen oft — hohe Tuning-Motivation, aber schwer auslesbar.

---

## Tier A — höchste Priorität (sehr häufig + starkes Tooling)

Ninebot/Segway Software-Pfad dominant; Xiaomi Hardware/CFW stark.

| # | Modell / Variante | Warum hoch |
| --- | --- | --- |
| 1 | Ninebot Max G30 / G30D / G30D II / G30LP | Historischer Tuning-Klassiker, riesige DE-Community, SHFW |
| 2 | Ninebot Max G2 / G2D | Enc2, SHU/SHFW, Nachfolger G30 |
| 3 | Ninebot Max G3 / G3D / G3 Plus | 2025 Massenmodell + aktuelles Tooling (x3) |
| 4 | Ninebot F2 / F2 Plus / F2 Pro | Sehr verbreitet, SHFW |
| 5 | Ninebot F3 / F3 Pro | x3-Familie, SHU/CFW-Pfad |
| 6 | Segway ZT3 Pro | x3, stark nachgefragt |
| 7 | Segway GT3 / GT3 Pro | Leistungssegment + x3-Tooling |
| 8 | Ninebot F25 / F30 / F40 / F45 / F60 / F65 | F-Serie Klassiker, SHFW |
| 9 | Xiaomi M365 / Pro / Pro 2 / 1S / Essential / Lite | CFW/SHFW-Ökosystem |
| 10 | Xiaomi Mi Scooter 3 | SHFW |
| 11 | Xiaomi 4 / 4 Lite / 4 Pro / 4 Ultra | Chip/CFW (Brightway/LEQI), aktuell relevant |
| 12 | Xiaomi 5 / 5 Pro / 5 Max / 5 Plus | Neuere CFW-Pfade |
| 13 | Xiaomi 6 / 6 Lite / 6 Max / 6 Ultra | Neu, CFW-Hinweise vorhanden |
| 14 | Ninebot E22 / E25 / E45 | SHFW |
| 15 | Ninebot ES1 / ES2 / ES4 | Legacy, weiterhin im Bestand |
| 16 | Ninebot D18 / D28 / D38 | SHU, DE-Markt |
| 17 | Ninebot E2 / E2 Plus / E2 Pro | Community-Tuning (teils ST-Link) |
| 18 | Ninebot E3 / E3 Pro | x3, Tooling wächst |
| 19 | Ninebot P65 / P100S | SHU-unterstützt |
| 20 | Ninebot Air T15 | SHU |

---

## Tier B — hoch (häufige Marken / wachsende Szene)

| # | Modell / Variante | Hinweis |
| --- | --- | --- |
| 21–30 | Navee N65 / XT5 / XT5 Ultra / UT5 / Max-Varianten | Viele DE-Tuning-Anfragen; BLE-Protokoll teilweise RE |
| 31–38 | SoFlow SO4 / SO4 Pro / SO4 Pro GT / SO4 Pro Max / SO ONE / Lite / Pro | DE-Markt; inoffizielle Tools, kein Hersteller-Freischaltcode |
| 39–48 | KuKirin / Kugoo G2 / G2 Pro / G2 Max / G3 / G3 Pro / G4 / V3 / A1 | Oft Controller-/Menü-Tuning, wenig offene BLE-Map |
| 49–55 | Vmax VX2 / VX4 / VX8 / new-Serie | DE-ABE-Modelle, Community-Tuning |
| 56–60 | Trittbrett Hilde / Paul u. a. | DE-Nische, Hardware-lastig |
| 61–65 | Egret X / GT / Ultra | DE-Präsenz |
| 66–70 | Hitway H10 / H11 u. ä. | Preissegment, Foren |
| 71–75 | RCB D5 / D7 u. ä. | Foren 2025 |
| 76–80 | IO Hawk / Legacy / Legend | DE-Handel |

---

## Tier C — Performance / „stark getunt“, aber schwer auslesbar

| # | Marke / Modelle (Beispiele) | Hinweis |
| --- | --- | --- |
| 81–88 | Dualtron (Thunder, Ultra, Mini …) | Extreme Performance; geschlossene Minimotors-Stacks |
| 89–93 | Kaabo (Wolf, Mantis …) | ähnlich geschlossen |
| 94–97 | VSETT 8 / 9 / 10 / 11 | Performance-Segment |
| 98–100 | Apollo / NAMI / Inokim / Zero | Teils App-locked; wenig offene Registerkarten |

---

## „Top 100“ als Familien-Expansion (praktisch für ScooterCheck)

Statt willkürlicher 100 SKUs: **~100 Varianten** = Familien × Regionen (D/E/US) × Lite/Pro/Plus.

### Ninebot / Segway (~55 Varianten)

G30D, G30E, G30LP, G30D II · G2D, G2E · G3D, G3E, G3US, G3 Plus · F2, F2+, F2 Pro (D/E) · F3, F3 Pro (D/E) · F25–F65 · ZT3 Pro D/E · GT3, GT3 Pro · GT1, GT2 · E22/25/45 · ES1–ES4 · D18/28/38 · E2/E2+/E2 Pro · E3/E3 Pro · P65, P100S · Air T15 · SNSC 1.x/2.x

### Xiaomi (~25 Varianten)

M365, Pro, Pro2, 1S, Essential, Lite · Mi 3 · 4, 4 Lite, 4 Pro, 4 Pro Max/Plus, 4 Ultra · 5, 5 Pro, 5 Max, 5 Plus · 6, 6 Lite, 6 Max, 6 Ultra · Elite

### Sonstige DE-relevant (~20)

Navee XT5/N65/UT5-Familie · SoFlow SO4/SO ONE-Familie · KuKirin G2/G3/G4 · Vmax VX2/VX4 · Egret · Hitway · Dualtron/Kaabo/VSETT (Erkennung, kaum Register)

---

## Was „am besten“ getunt heißt (für Kontrollen)

| Typ | Typische Modelle | Nachweisbarkeit für ScooterCheck |
| --- | --- | --- |
| Software / WebApp / Soft-Unlock | Ninebot G/F/ZT/GT | **Hoch**, wenn Enc2-Dump + Limit/Peak/Region lesbar |
| Custom Firmware (SHFW/CFW) | G30, F2, Xiaomi klassisch | **Hoch** bei FW-String/Register-Auffälligkeiten |
| Hardware-Chip / Controller-Tausch | Xiaomi 4/5/6, KuKirin, SoFlow | **Mittel–niedrig** (Chip oft unsichtbar; Controller-SN/FW-Brüche) |
| Menü / Region-Codes | Manche KuKirin/Navee | **Niedrig** ohne Protokoll |
| Ab-Werk-Performance | Dualtron/Kaabo | Oft **kein** eKFV-Scooter oder andere Rechtslage |

---

## Quellen (Auswahl)

- ScooterHacking Utility Kompatibilität — Joey’s Wiki / bastelpichi  
- [scooterhelden.de – Tuning 2026 Überblick](https://scooterhelden.de/2026/05/28/e-scooter-tuning-2026-software-hardware-risiken-und-die-besten-modelle-im-ueberblick/)  
- DACH Tuning-Kompatibilitätsartikel (Ninebot G/F/ZT/GT, Xiaomi 3–4)  
- DE Community-Größen (escooter.blog Community-Übersicht, ~06/2025)  
- Stammtisch-Umfrage 2025 (Max G3 dominant)  
- `docs/PROTOCOL_SOURCES.md` — technische Lesequellen  
- scooter-tuning-db — offene Registerkarten vs. „not covered“

---

## Empfehlung für ScooterCheck

1. **Kern halten:** G30/G2/G3, F2/F3, ZT3, Xiaomi plaintext + bekannte CFW-Signale.  
2. **Als Nächstes:** GT3-Telemetrie-Map, Xiaomi 4/5/6 Erkennung (auch wenn Dump begrenzt), Navee/SoFlow Research→Read.  
3. **Nicht erwarten:** vollständige Dualtron/Kaabo-Registerkarte aus offenen Quellen.  
4. **Kontrolle:** Rohdaten-PDF + Profil/App-Version; Urteil = Heuristik.
