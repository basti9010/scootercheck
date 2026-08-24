# ScooterCheck

Native **iOS**-App (SwiftUI + Core Bluetooth) zur **nur lesenden** Diagnose von Ninebot ZT3 Pro (D/E).

1. Scooter suchen → verbinden  
2. Manipulation prüfen  
3. Bericht speichern (PDF + JSON)

Keine Limit-Änderungen, kein Firmware-Flash, keine Unlock-Kombos.

## Bundle

- Bundle-ID: `com.tuningscanner`
- Display-Name: ScooterCheck
- Xcode: `ios/ScootProof/ScootProof.xcodeproj`

## TestFlight ohne Mac

Siehe `docs/TESTFLIGHT.md`. Kurz:

1. GitHub Secrets setzen (`APPLE_TEAM_ID`, API-Key-Felder)
2. **Actions → TestFlight → Run workflow**

Oder Push auf `main` unter `ios/ScootProof/**`.
