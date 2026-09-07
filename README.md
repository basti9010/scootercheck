# ScooterCheck

Native **iOS**-App (SwiftUI + Core Bluetooth) zur **nur lesenden** Diagnose gängiger E-Scooter
(Ninebot Max G2/G30/G3, ZT3 Pro, F2/F3, E-/D-Serie, Xiaomi M365/Pro 2/Essential/3/4).

1. Scooter suchen → verbinden  
2. Manipulation prüfen  
3. Bericht speichern (PDF + JSON)

Keine Limit-Änderungen, kein Firmware-Flash, keine Unlock-Kombos.

## Bundle

- Bundle-ID: `com.scootercheck.app` (eigenständig, nicht TuningScanner)
- Display-Name: ScooterCheck
- Xcode: `ios/ScootProof/ScootProof.xcodeproj`
- Soll-Profile: Max G2/G30/G3, ZT3 Pro, F2/F3, E-/D-Serie, Xiaomi Classic & 3/4 (je D 20 / E 25 km/h)
- BLE-Auslese: am tiefsten für Ninebot Enc2 (Max G3 mit eigener Registerkarte); Xiaomi Klartext (55 AA); Xiaomi 3/4 oft 55 AB und dann eingeschränkt

## TestFlight ohne Mac

Siehe `docs/TESTFLIGHT.md`. Kurz:

1. GitHub Secrets setzen (`APPLE_TEAM_ID`, API-Key-Felder)
2. **Actions → TestFlight → Run workflow**

Oder Push auf `main` unter `ios/ScootProof/**`.
