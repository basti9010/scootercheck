# ScooterCheck — Produkt- & Design-Brief (Ist-Stand)

Kopiervorlage für Design-Arbeit (Figma / ChatGPT / Designer). Beschreibt **Funktionen, Bildschirme, Abläufe und Look** der aktuellen iOS-App, nicht den Code.

---

## 1. Produkt in einem Satz

**ScooterCheck** ist eine native iOS-App für Kontrollkräfte: E-Scooter per Bluetooth finden, Diagnosedaten **nur lesen**, Manipulationen einschätzen und ein **offline speicherbares Protokoll** (PDF + JSON) erzeugen.

**Nicht Ziel:** Limits ändern, Firmware flashen, Unlock-Kombos vorschlagen/ausführen, Tuning verkaufen.

---

## 2. Zielgruppe & Nutzungssituation

| Aspekt | Beschreibung |
|--------|----------------|
| Nutzer | Kontrolleure, Prüfende im Außeneinsatz |
| Kontext | Straße / Parkplatz, oft mehrere Scooter nebeneinander, Zeitdruck, ggf. schlechtes Netz |
| Gerät | iPhone, Hochformat, eine Hand / Handschuhe möglich |
| Sprache | Deutsch (UI und Protokoll) |
| Offline | Kernfunktionen müssen ohne Netz funktionieren; Online nur als Katalog-Ergänzung |

---

## 3. Marke & Wortlaut

- **Name:** ScooterCheck (Wortmarke: „Scooter“ in Akzentfarbe + „Check“ in Weiß)
- **Iconografie:** Schild-Haken / Schutz-Check (SF Symbol `checkmark.shield.fill`)
- **Copyright:** schlicht „© YYYY Bastian Ellinghausen“ (ohne Tausenderpunkt im Jahr)
- **Ton:** sachlich, behördlich-tauglich, Alltagsdeutsch in der Kurzfassung; Technik nur in Details / PDF-Rohteil
- **Urteile vermeiden juristische Vorwürfe:** z. B. „technisch eindeutige Abweichung“, nicht „illegal“ / „Straftat“

---

## 4. Visuelles System (Ist)

### Farben (Dark Mode only)

| Token | Rolle | Ungefähr |
|-------|--------|----------|
| Background | App-Hintergrund | sehr dunkles Blaugrau `#12171C`-artig |
| Card | Flächen / Karten | etwas helleres Panel |
| Accent | Primäraktion, Marke, positive Signale | Türkis/Mint `#6BDBC2` |
| Muted | Nebentext | Weiß ~55 % |
| Line | Trennlinien | Weiß ~8 % |
| Danger | Fehler / schweres Urteil | Rot |
| Warn | Warnung / mittleres Urteil | Gelb |
| Ink | Text auf Accent-Buttons | fast schwarz |

### Urteil-Farben

- **Serienzustand** → Accent (Mint)
- **auffällig** → Gelb
- **Manipulationshinweise** → Orange
- **technisch eindeutige Abweichung** → Rot

### Form & Typo

- Karten: Radius ~16, Padding 16, dunkle Card-Fläche
- Primärbutton unten: volle Breite, Radius ~16, kräftige Fläche
- Felder: leicht aufgehellter Hintergrund, Radius ~10
- Schrift: System-SF (SwiftUI), Gewichtungen Semibold/Bold für Titel
- Kein Light Mode; `preferredColorScheme(.dark)`

### Signal- / Gerätezeile (Scan)

SHU-ähnliche Geräte-Karte:

- Links: Scooter-Thumbnail oder BLE-Antennen-Icon
- Mitte: kompakte Geräte-ID (z. B. Serien-/BLE-Name), Modellname, Badges
- Rechts: 4 Signalbalken (RSSI) + Chevron
- Optional: Alias „Name · Kennzeichen“ in Accent, Badge „bekannt“

---

## 5. Informationsarchitektur

Drei Haupt-Screens (intern `home` / `overview` / `result`):

1. **Scooter-Suche** (Home) — Scan, Geräte wählen, verbinden/auslesen
2. **Kontrollen** (Overview) — Liste gespeicherter Prüfungen
3. **Protokoll** (Result) — Auswertung + Details + Aktionen

**Seitliches Menü (Drawer von links):**

- Navigation: Scooter-Suche · Kontrollen (mit Zähler) · Aktuelles Protokoll (nur wenn vorhanden)
- Soft-Unlock-Einstellungen (Geste, Wiederholungen, Schwelle)
- **Trennen** nur sichtbar, wenn wirklich ein Scooter verbunden / im Ausleseablauf ist
- Copyright unten
- **☰-Button** in der NavBar löst sich auf, während das Menü offen ist; erscheint wieder beim Schließen
- Menü-X schließt den Drawer

**Kein** dauerhafter Profil-Picker und **keine** Demo-Beispiele mehr im Menü.

---

## 6. Kern-Userflows

### A) Erste Prüfung (Happy Path)

1. App starten → Home, Status „Bereit“ / leerer Scan
2. Primärbutton **„Scooter suchen“** → BLE-Scan
3. Geräteliste füllt sich (Filter „Nur Scooter“ / „Alle BLE“)
4. Nutzer tippt ein Gerät → Sheet **„Profil bestätigen“**
5. App schlägt Vergleichsprofil vor (z. B. Max G3 D, F3 …) → Nutzer kann ändern
6. **„Auslesen starten“** → Verbinden → Handshake → Register lesen
7. Bei Pairing ggf. Hinweis **Power-Knopf drücken**
8. Auswertung fertig → Sheet **Zuordnung** (Kennzeichen, Name, optional Geburtsdatum) — freiwillig
9. Weiter → **Protokoll-Screen** mit Klartext-Ergebnis
10. Speichern / Teilen (AirDrop); Liste „Kontrollen“ wächst

### B) Protokoll schließen

- Oben links **✕** auf dem Protokoll-Screen → zurück zur **Kontrollübersicht**
- Alternativ unten **„Zur Übersicht“**

### C) Bekannte Scooter wiedererkennen

- Wenn ein Scooter schon geprüft und mit Kennzeichen/Name gespeichert wurde:
  - In der Scanliste: `Geräte-ID · Name · Kennzeichen`
  - Badge „bekannt“, bekannte Geräte eher oben
- Match über Seriennummer und/oder BLE-UUID dieses iPhones

### D) Soft-Unlock / Geheimkombination (nach Tuning-Verdacht)

1. Nach Auswertung: Banner / Aktion **„Geheimkombination eingeben & auslesen“**
2. Nutzer trägt Geste im Menü ein (z. B. linker Bremshebel 6×) oder lädt gespeicherte Kombi für die SN
3. Geste am Scooter eingeben → erneut auslesen (Scan B)
4. Bei Erfolg: Kombination pro Seriennummer speichern

### E) Power-Cycle-Test

1. Scan A gespeichert
2. Scooter aus/ein
3. Scan B → Persistenzvergleich (was bleibt nach Neustart?)

### F) Historie öffnen

- Kontrollübersicht → Tippen auf Eintrag → Protokoll wieder öffnen
- Teilen / Löschen (Context-Menü)

---

## 7. Screen-für-Screen (UI-Inhalte)

### 7.1 Scooter-Suche (Home)

**NavBar:** ☰ (wenn Menü zu) · Wortmarke ScooterCheck  
**Inhalt:**

- Leerzustand: Logo, Wortmarke, „Kein Scooter verbunden“, Statuszeile, ggf. Button „Kontrollen öffnen“
- Verbindungszustand: Fortschritt, Titel („Verbinden“, „Authentifizieren“, „Diagnosefelder lesen“…), gelber Hinweis bei Power-Taste, Stack-Label
- Geräteliste:
  - Überschrift „Geräte“ + „sucht…“ / „in der Nähe“
  - Segment: Nur Scooter | Alle BLE
  - Karten wie oben; nächstes Gerät kann Badge „nächstes“ haben

**Bottom-Bar Primäraktion (kontextabhängig):**

- Scooter suchen / Suche stoppen
- Nach erfolgreicher Auslese ggf. „Manipulation prüfen“ (Analyse anstoßen, falls noch nötig)

### 7.2 Profil bestätigen (Sheet)

- Navigationstitel „Profil bestätigen“, Abbrechen
- Abschnitt Gerät: Anzeigename, erkanntes Modell / Kurzbadge, Hinweis wenn unklar
- Abschnitt Vergleichsprofil: Picker aller Profile (Familie · Kurzlabel · km/h), Support-Hinweis
- Footer: Vorschlag aus BLE/SN; ändern nur wenn Erkennung falsch
- Primär: **Auslesen starten**

### 7.3 Zuordnung (Sheet, vor Protokoll)

- Kennzeichen, Nachname, Vorname, optional Geburtsdatum
- Hinweis: freiwillig, nicht bewertungsrelevant
- Zurück-Chevron → Kontrollübersicht (ohne Protokoll-Zwang)
- „Weiter zum Protokoll“ / „Überspringen“
- Copyright unten

### 7.4 Protokoll / Ergebnis

**NavBar:** ✕ schließen · Titel „Protokoll“

**Kopfkarte:**

- Score-Ring (0–100 „Seriennähe“) + Urteilstext farbig
- Score-Erklärung in einer Zeile
- Optional: Track-Label (z. B. Web-App-/SHU-Heuristik), BLE-Stack, Katalogversionen
- Klartext-Block:
  - Überschrift „Was ist aufgefallen?“ oder „Ergebnis in Klartext“
  - Bullet-Liste der Auffälligkeiten (keine Doppelung unten)
  - Optional Attribution: „Vermutete Art der Veränderung“ + Disclaimer

**Darunter:**

- Hinweis: Oben Kurzfassung, darunter nur Messwerte
- Zuordnungskarte (nachträglich editierbar)
- Detailgruppen (Messwerte): u. a. Seriennummern, Geschwindigkeit, Firmware, Flags, Historie, Power-Cycle — **ohne** erneutes Gesamteindruck-/Attribution-Echo

**Bottom-Bar:**

- Primär: Bericht speichern (Farbe am Urteil)
- Geheimkombination eingeben & auslesen
- Power-Cycle-Test
- Teilen / AirDrop
- Zur Übersicht

### 7.5 Kontrollübersicht

**NavBar:** ☰ · „Kontrollen“

Liste gespeicherter Einträge:

- Protokollnummer, Urteil, Profil, SN, Zuordnungszeile, Datum
- Tippen = öffnen; Teilen; Löschen
- Leer: Tray-Icon + „Noch keine Kontrollen“

**Bottom:** „Neue Prüfung“ → zurück zur Suche

### 7.6 Seitenmenü

- Wordmark + X
- Navigation (siehe IA)
- Soft-Unlock: Bedienung (Bremshebel/Tasten/…), Wiederholungen, Schwelle km/h, Anzeige der aktuellen „Geheimkombination“-Kurzform  
  *(Erkennung ist immer aktiv — kein Ein/Aus-Schalter mehr)*
- Trennen (bedingt)
- Copyright

---

## 8. Fachliche Funktionen (für Design-Labels)

### Vergleichsprofile

Familien u. a.:

- Ninebot Max G3 / MAX3 (DE / EU / US)
- Max G2, Max G30, ZT3 Pro
- F2 / F-Serie, F3, E-Serie, D-Serie
- Xiaomi Classic (M365/Pro2/…), Xiaomi 3/4

Jedes Profil: Soll-Tempo (20 / 25 / ~37 km/h), Verdachtsschwellen, Registerkarte (G3 vs. Legacy), Support-Hinweis.

### Auslese-Tiefe (Kurz)

| Modellklasse | Realität in der App |
|--------------|---------------------|
| Max G3 | Tiefste Enc2-Auslese + G3-Register + Firmware-Katalog |
| G2 / G30 / ZT3 / F/E/D | Enc2 möglich, Katalog dünner oder fehlend |
| Xiaomi Classic | Klartext oft ok |
| Xiaomi 3/4 | oft verschlüsselt → eingeschränkt / fehlgeschlagen |

### Firmware-Katalog

- Offline-Basis in der App
- Optional Online-Erweiterung; Herkunft im UI: „Bundled“ oder „Online …“
- Unterscheidet: im Katalog / nicht im Katalog / Custom-Kennung

### Urteile (Verdict)

1. Serienzustand  
2. auffällig  
3. Manipulationshinweise  
4. technisch eindeutige Abweichung  

Score 0–100 = „Seriennähe“ (Erklärungstext: Urteil folgt Regeln, nicht dem Score).

### PDF-Protokoll (Export)

Struktur (kompakt gehalten):

- **I. Zusammenfassung** — Urteil, Kurztext, Bullets, Fahrzeugdaten, optionale Zuordnung
- **II. Messwerte zu den Auffälligkeiten** — nur Zahlen (Festgestellt / Erwartet), keine erneute Prosa
- **III. Vermutete Art der Veränderung** — Heuristik + Disclaimer
- **IV.** technische Roh-/Registerteile (u. a. Dump-Hinweise Limit vs. Peak)

Plus JSON-Pack für Archivierung.

---

## 9. Interaktionsmuster & Motion (Ist)

- Drawer: Slide von links + Dimmer; Dauer ~0,22 s easeOut
- ☰-Button: Opacity-Dissolve beim Öffnen/Schließen des Menüs
- Sheets: Profil bestätigen, Zuordnung (Medium/Large Detents)
- Bottom-Bar immer sichtbar (Safe-Area Inset)
- Busy: ProgressView im Primärbutton; Gerätezeilen disabled während Connect/Dump

---

## 10. Inhalte, die Design **nicht** verdoppeln soll

Bewusst kompaktiert:

- Klartext-Bullets nur **einmal** oben
- Kein zweites „Gesamteindruck“ in den Details
- Attribution nicht als langer Fließtext nochmal unter Messwerten
- Speed-/Gang-Diffs nicht zusätzlich als „Diff:“-Zeilen, wenn schon als Messwert da

Neue Designs sollten diese Hierarchie behalten: **1) Urteil + Bullets → 2) Aktionen → 3) Messwerte → 4) Technik aufklappen**.

---

## 11. Geplante / diskutierte Features

- **Identifizieren / Piepton** — in Maske „Profil bestätigen“: Button „Identifizieren“ verbindet kurz, sendet Find/Piep (Ninebot), Session bleibt für „Auslesen starten“. Xiaomi: oft kein Piep, nur Verbindungshinweis.
- Vollständige F3-Pro-G3-Karte auf allen Builds (teilweise eigener Branch)
- Stärkerer Online-Katalog für Modelle ohne Bundled-Eintrag

---

## 12. Prompt-Hilfe für ChatGPT / Designer

Du kannst z. B. so starten:

> Entwirf ein modernes iOS-UI (Dark, mint accent) für „ScooterCheck“, eine App für Straßenkontrollen von E-Scootern. Nutze den folgenden Ist-Brief als Funktionsumfang. Ziele: weniger visuelles Rauschen, klare Hierarchie Urteil → Klartext → Aktionen → Messwerte, große Touch-Targets, eine Hand, offline-tauglich. Keine Gaming-/Tuning-Ästhetik. Screens: Suche mit Gerätecards, Profil-Bestätigung, Protokoll, Kontrollliste, Side-Drawer. [Brief einfügen]

---

## 13. Kurzliste aller „Buttons / Aktionen“ (Ist)

- Menü öffnen / schließen  
- Scooter suchen / Suche stoppen  
- Filter Nur Scooter / Alle BLE  
- Gerät tippen → Profil bestätigen → Auslesen starten / Abbrechen  
- Zuordnung weiter / überspringen / zurück Übersicht  
- Protokoll schließen (✕)  
- Bericht speichern  
- Teilen / AirDrop  
- Geheimkombination eingeben & auslesen / erneut auslesen / abbrechen  
- Power-Cycle starten / Scan B / abbrechen  
- Zur Übersicht / Neue Prüfung / Kontrollen öffnen  
- Trennen (nur wenn verbunden)  
- Soft-Unlock: Bedienung, Wiederholungen, Schwelle  
- Historie: öffnen, teilen, löschen  

---

*Stand: Branch mit kompakteren Berichten, Online-Katalog-Ergänzung, Alias-Wiedererkennung, Side-Drawer-Navigation — TestFlight-Serie ~Build 39+.*
