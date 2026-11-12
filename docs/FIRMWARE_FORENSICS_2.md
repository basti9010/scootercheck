# Firmware-Forensik 2.0

Stand: 2026-11-12

Read-only lokale Analyse von Firmwaredateien in ScooterCheck.

## Formate

ZIP / ScooterHacking ZIPv3, BIN, BIN.ENC, JSON, TXT

## Module

| Modul | Aufgabe |
|-------|---------|
| `FirmwarePackageLoader` | Container & Metadaten |
| `FirmwareCryptoAssessor` | Verschlüsselungsstatus |
| `FirmwareBinaryStaticAnalyzer` | Strings / ARM-Hinweise (nur Klartext) |
| `FirmwareReferenceStore` | Referenzimport |
| `FirmwareComparer` | SHA-256 / Byte-Diff |
| `FirmwareForensicScorer` | GRÜN/GELB/ROT/GRAU |
| `FirmwareForensicPDF` | PDF & JSON |

## Entschlüsselung

Nicht verfügbar — kein rechtmäßiges Transfer-Schlüsselmaterial in der App. Verschlüsselte Images werden erkannt; Funktionsanalyse wird als nicht verfügbar ausgewiesen.

## ZT3-Beispiel

`ZT3⚡VCU_ panicsystem.zip` → Modell `zt3`, Typ `VCU`, Board `zt3_VCU_AT32`, Payload `FIRM.bin.enc`, Status verschlüsselt; „panic“ nur unverifizierter Dateiname-Hinweis.
