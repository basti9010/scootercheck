# Öffentliche Protokoll-Quellen (Recherche)

Stand: 2026-11-12. Nur **read-only**-relevante Quellen für ScooterCheck.  
Keine Unlock-/Tuning-Schreibpfade, keine Bezahlungspflichtigen App-Backends.

## Priorität für ScooterCheck

| Prio | Quelle | Was sie liefert | Status in der App |
| --- | --- | --- | --- |
| 1 | [NootNooot segway-ninebot-ble](https://nootnooot.codeberg.page/segway-ninebot-ble/) | 66 Gerätefamilien, ~8 693 Commands, Enc2/Proto1/2, Board-Maps, Speed/Limit-Register | Enc2-Handshake + Teil-Maps (G3/F3/ZT3/…) bereits; **viele Familien noch nicht als eigene Lesekarten** |
| 2 | [HeckerHeckt Max-G3-Flasher](https://github.com/HeckerHeckt/Ninebot-Max-G3-Firmware-Flasher) | G3 Board/Versionsregister (BLE/VCU/MCU/BMS) | Weitgehend übernommen |
| 3 | [CamiAlfa M365-BLE-PROTOCOL](https://github.com/CamiAlfa/M365-BLE-PROTOCOL) | Xiaomi classic 55 AA Register | Plaintext-Pfad vorhanden; 55 AB verschlüsselt bewusst nicht |
| 4 | [scooter-tuning-db](https://github.com/jx-grxf/scooter-tuning-db) | JSON-Karten Xiaomi/Ninebot klassisch, Neoline plaintext; KuKirin ohne BLE-Map | Als Katalog-Hinweis; nur **R**-Felder für Telemetrie relevant |
| 5 | [ha-ninebot](https://github.com/BobMcGlobus/ha-ninebot) | Praxis: G30, F40, F3, Max G2/G3, Register-Scan-Methode | Methodik + Plausibilisierung |
| 6 | [scootscoot](https://pypi.org/project/scootscoot/) | Enc2-Client, GT3-Pro-Profil | Kandidat für GT3-Erweiterung |
| 7 | ScooterHacking / NinebotCrypto | Framing, Crypto, klassische Boards | Bereits Basis der Enc2-Schicht |
| 8 | [Navee ST3 Pro RE](https://github.com/pepperonas/navee-st3-pro) | BLE/UART-Protokollbeschreibung Navee | Research only — noch kein nativer Stack |
| 9 | SoFlow SOHacks | BLE vorhanden, Fokus Tuning | Nur als Marken-Hinweis; **kein** Write-Import |
| — | Dualtron/Kaabo/Inokim/Zero/Apollo/NIU | Laut Community oft geschlossen / unvollständig | Research only |

## Segway-Ninebot: dokumentierte Kick-Scooter (Auszug)

Aus der Geräteübersicht (Enc2 = AES wie Max G3; Proto2 = älteres XOR/Plain-ähnlich):

| Modellfamilie | HW-ID | Protokoll | Commands | In ScooterCheck |
| --- | --- | --- | --- | --- |
| MAX G3 / G3 Plus | 258 | Enc2 | 192 | ja (nativ) |
| ZT3 Pro | 256 | Enc2 | 191 | ja |
| F3 | 259 | Enc2 | 192 | ja |
| MAX G2 | 131 | Enc2 | 121 | ja (Familie) |
| SuperScooter GT3 | 257 | Enc2 | 192 | Profil/Board teils, **keine eigene Telemetrie-Karte** |
| GT1 / GT2 | 112 / 113 | Enc2 | 86 / 83 | nein |
| F2 / F2 Plus / F2 Pro | 127–129 | Proto2 | 104 | teilweise F-Familie |
| D18 / D28 / D38 | 116/114/115 | Enc2 | ~46 | D-Familie grob |
| E2 / E2 Plus / E2 Pro | 125 / 141 | Proto2 | 69 / 107 | E-Familie grob |
| P65 / P100S | 118 / 119 | Enc2 | 91 | nein |
| ST2 Pro | 136 | Enc2 | 83 | nein |
| Segway E-bike / Xyber | diverse | Enc2 | ~160 | nein (Pedelec-Pilot separat) |

Volle Tabellen:  
https://nootnooot.codeberg.page/segway-ninebot-ble/devices/

## Was als Nächstes sinnvoll ist (read-only)

1. **GT3 / P65 / ST2**: Enc2-Handshake existiert → Board-Map + Leseregister aus NootNooot-Device-Pages als `DiagnosticMap`-Erweiterung (nur Read).
2. **F2 Pro / Max G2**: Register-Listen gegen ha-ninebot und NootNooot abgleichen, fehlende Limit/Peak/SN-Felder ergänzen.
3. **Neoline (E-Ride)**: plaintext BLE laut scooter-tuning-db — eigener kleiner Stack denkbar.
4. **Navee**: PROTOCOL.md auswerten → eigener Stack oder Research→verified wenn SN/Limit/FW lesbar.
5. **KuKirin / Vsett / Dualtron**: vorerst GATT-DIS; keine erfundenen Registerkarten.

## Abgrenzung

- Quellen beschreiben oft auch **Writes** (Limit, Mode, OTA). ScooterCheck importiert davon nur **Lesepfade**.
- „Alle Register scannen“ bleibt Heuristik (ha-ninebot): ohne Modellkarte keine belastbare Bewertung.
- Hersteller-Handbücher mit vollständigen BLE-Registern sind öffentlich praktisch nicht verfügbar.
