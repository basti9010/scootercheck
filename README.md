# ScooterCheck

Native **iOS**-App (SwiftUI + Core Bluetooth) zur **nur lesenden** Diagnose gängiger E-Scooter
(Ninebot Air T15, ESx, D/E/F/F2/F3, Max G2/G30/G3/G65, GT1/GT2/GT3, P65/P100, ZT3;
Xiaomi M365/Pro/Pro2/1S/Lite/3/4).

1. Scooter suchen → verbinden  
2. Manipulation prüfen  
3. Bericht speichern (PDF + JSON)

Keine Limit-Änderungen, kein Firmware-Flash, keine Unlock-Kombos.

OEM-Firmwares liegen chronologisch unter `server/firmware-analysis/stock-archive/`
(`sync_stock_firmwares.py`, Deploy auf den FW-Host: `deploy_stock_archive.sh`).

## Bundle

- Bundle-ID: `com.scootercheck.app` (eigenständig, nicht TuningScanner)
- Display-Name: ScooterCheck
- Xcode: `ios/ScooterCheck/ScooterCheck.xcodeproj`
- Soll-Profile: SH-Utility-Modelle (Ninebot + Xiaomi), Markt D 20 / E 25 km/h (Max G3 zusätzlich US)
- BLE-Auslese: Ninebot Enc2 (G3/F3/GT3/ZT3 mit x3-Karte); Xiaomi Klartext (55 AA); Xiaomi 3/4 oft 55 AB und dann eingeschränkt

## TestFlight ohne Mac

Siehe `docs/TESTFLIGHT.md`. Kurz:

1. GitHub Secrets setzen (`APPLE_TEAM_ID`, API-Key-Felder)
2. **Actions → TestFlight → Run workflow**

Oder Push auf `main` unter `ios/ScooterCheck/**`.
