# ScooterCheck

Native **iOS**-App (SwiftUI + Core Bluetooth) zur **nur lesenden** Diagnose gängiger E-Scooter (Ninebot ZT3 Pro, Max G30, F-/D-Serie, Xiaomi M365/Pro 2/3/4).

1. Scooter suchen → verbinden  
2. Manipulation prüfen  
3. Bericht speichern (PDF + JSON)

Keine Limit-Änderungen, kein Firmware-Flash, keine Unlock-Kombos.

## Bundle

- Bundle-ID: `com.scootercheck.app` (eigenständig, nicht TuningScanner)
- Display-Name: ScooterCheck
- Xcode: `ios/ScootProof/ScootProof.xcodeproj`
- Soll-Profile: ZT3 Pro, Max G30, F-Serie, D-Serie, Xiaomi Classic & 3/4 (je D 20 / E 25 km/h)
- BLE-Auslese: optimiert für Ninebot Enc2; Xiaomi ggf. eingeschränkt

## TestFlight ohne Mac

Siehe `docs/TESTFLIGHT.md`. Kurz:

1. GitHub Secrets setzen (`APPLE_TEAM_ID`, API-Key-Felder)
2. **Actions → TestFlight → Run workflow**

Oder Push auf `main` unter `ios/ScootProof/**`.
