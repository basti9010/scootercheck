# DarknessBot ↔ ScooterCheck (Livedaten / Register)

Stand: 2026-11-12  
Quellen: [DarknessBot App Store](https://apps.apple.com/us/app/darknessbot/id1108403878), [Play Store Feature-Liste](https://play.google.com/store/apps/details?id=com.darknessproduction.darknessbot), [NootNooot Max G3](https://nootnooot.codeberg.page/segway-ninebot-ble/devices/segway-ekickscooter-ninebot-max-g3max-g3-plus/), CSV-Exporter (EUCtelemetry/rednessbot).  
Nur **Lesen**. DarknessBot-**Schreib**-Funktionen (Limit, Mode, Lock, FW-Update …) werden bewusst nicht nachgebaut.

## DarknessBot: angezeigte BLE-Metriken (KickScooter)

Laut Store-Beschreibung (Ninebot KickScooter inkl. G30/G2/G3/GT3/F3/ZT3):

| Metrik | KickScooter-Relevanz | ScooterCheck (Enc2 / x3) |
| --- | --- | --- |
| Aktuelle Geschwindigkeit | ja | VCU `0x57` + Live-Poll |
| Maximalgeschwindigkeit | ja (Trip-Peak / Limit) | DIS `0x24` Peak, VCU `0x46` Limit |
| Durchschnittsgeschwindigkeit | ja | DIS `0x27` |
| Gesamtkilometer | ja | VCU `0x62` (0.1 km) |
| Restreichweite | ja | VCU `0x5F` |
| Trip-Kilometer | ja | VCU `0x68` |
| Gesamtlaufzeit | ja | VCU `0x64` |
| Trip-Laufzeit | ja | VCU `0x69` / `0x6A` |
| Batterie % | ja | VCU `0x55`, BMS `0x8F` |
| Controller-Temperatur | ja | VCU `rBodyTemp` `0x6B` |
| Batterie-Temperatur | ja | BMS `0x96` (4 B) |
| Leistung (W) | ja | aus BMS U·I berechnet |
| Spannung (V) | ja | BMS `0x8C` |
| Strom (A) | ja (wenn vom BMS) | BMS `0x8D` |
| Pitch / Roll | typ. EUC | nicht für KickScooter |
| PWM | typ. EUC | nicht für KickScooter |
| Reichweiten-Prognose NN | App-seitig | nicht (kein Cloud-/NN-Modell) |
| Lade-/Entladezeit-Prognose | App-seitig | BMS `rTimeFull` `0x94` optional |

## Abgrenzung

- DarknessBot pollt **kontinuierlich** für Dashboard/Graphen. ScooterCheck macht einen Diagnosedump und hält danach optional einen **Live-Telemetrie-Poll** (gleiche Read-Register).
- Pitch/Roll/PWM und EUC-spezifische Felder zählen nicht zur KickScooter-Parität.
- Schreibpfade (Speed-Limit setzen, Lock, OTA …) bleiben ausgeschlossen.
