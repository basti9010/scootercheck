# FIRMWARE_RESEARCH_ROADMAP – Cycle 6

Ziel: aus der Zwei-Datei-Untersuchung wiederverwendbare ScooterCheck-Fähigkeiten ableiten — **ohne** Unlock-/Flash-/Write-Pfade.

## Ist-Zustand (ehrlich)

Vorhanden und nutzbar: Forensic Models/PDF, InvestigationStore/Hub, CrossSourceCorrelator MVP, ReadoutMatch + DualSourcePanic, ZIP Inspector, Evidence tiers.  
**Fehlt** auf multi-agent: PackageLoader, BinaryStaticAnalyzer, ServerAnalysisClient, lokales Ghidra.  
Encrypted Packs (wie A/B) stoppen Deep-ISA-Analyse lokal.

## Wiederverwendbares Analysemodul (Vorschlag)

Name-Arbeitstitel: `FirmwareStaticLab` (unter `FirmwareForensics/`)

| Stufe | Fähigkeit | Epistemik | Abhängigkeit |
|-------|-----------|-----------|--------------|
| L0 | Import ZIP/bin, SHA-256/MD5, Entropie, Member-Liste | CONFIRMED | lokal |
| L1 | Parse `info.json` / Meta → `FirmwarePackageMeta` | CONFIRMED | lokal |
| L2 | Filename heuristics (km/h, panic, cfw) als **Hypothesis**-Evidence | HYPOTHESIS | lokal |
| L3 | Byte-Diff zweier Enc-Images (Prefix/Diff-Count) | CONFIRMED Diff | lokal |
| L4 | Optional: rechtmäßige Server-Decrypt → Klartext | gated | ServerClient (fehlt) |
| L5 | Optional: Ghidra headless → Funktionen/XRefs | gated | Ghidra (fehlt) |
| L6 | Event/FSM-Katalog nur aus Klartext/Decompile | CONFIRMED wenn belegt | L4+L5 |
| L7 | CrossSource + DualSource + Investigation export | mixed | vorhanden |

Jede Fundstelle speichert: `fileName`, `sha256`, `offsetOrAddress`, `observation`, `interpretation`, `alternative`, `confidence` / tier.

## Integrationspfad in bestehende Architektur

1. L0–L3 als reines Swift-Modul + Unit Tests (keine BLE-Writes).  
2. Results in `FirmwareForensicReport.evidence[]` mit `.filenameHint` / `.crypto` / neuer Kategorie `.containerDiff`.  
3. InvestigationStore: Lab-Run als FirmwareRef + JSON-Nebenartefakt.  
4. UI: Investigation Detail „Lab-Zusammenfassung“ (Confirmed vs Hypothesis getrennt).  
5. L4/L5 hinter Feature-Flag + explizite Nutzerfreigabe; nie Auto-Flash.

## Nächste Entwicklungsaufgaben (priorisiert)

1. **L0/L1 Lab pipeline** + Tests mit den Cycle-6-Fixtures (nur Hashes/Meta, Blobs gitignored).  
2. PackageLoader von unified-Branch kontrolliert portieren.  
3. ServerAnalysisClient nur mit Policy-Gates.  
4. Reference-Store für OEM-Images (wenn rechtmäßig beschafft) — sonst kein fingierter Stock-Diff.  
5. ContentView unverändert lassen außer opt-in Lab-Entry später.

## Nicht-Ziele

Fahrzeugmanipulation, Limit-Bypass-Anleitungen, unkontrollierte BLE-Writes, Flash, Entfernen von Sicherheitsgrenzen.
