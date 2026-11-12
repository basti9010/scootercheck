# Firmware-ZIP-Inspektor (Read-Only)

Stand: 2026-11-12

ScooterCheck kann Flash-/Firmware-ZIPs vom iPhone **nur lesen** — kein Flashen, keine Schreibzugriffe auf den Scooter.

## Unterstütztes Format

Primär [ScooterHacking ZIPv3.2](https://wiki.scooterhacking.org/doku.php?id=zip3):

- `info.json` — displayName, models, type, compatible, md5
- `FIRM.bin` — Image (MD5-Abgleich)
- optional `params.txt` — Changelog / Parameter

Andere ZIPs: Einträge werden trotzdem auf ASCII-Strings gescannt.

## Was die Auswertung liefert

- Metadaten und MD5-Konsistenz
- Speed-/Region-/Compat-Zeilen aus params.txt
- Custom-FW-Hinweise (SHFW/CFW/COMPAT)
- Gesten-/Freischalthinweise (z. B. „throttle and brake“, „profile at boot“, „brake 6x“)

Treffer sind **Datei-Hinweise**. Wirkung am Fahrzeug nur über BLE-Auslese / Vergleichstest.

## Einstieg in der App

„E-Scooter auslesen“ → „Firmware-ZIP auswerten“ oder Menüeintrag gleichen Namens.
