# P0 Auth — iPhone Testplan (TestFlight)

All steps below are **NOT VERIFIED** on a real device until executed on hardware.

| # | Schritt | Erwartung | Status |
|---|---------|-----------|--------|
| 1 | Login mit gültigem aktivem Benutzer | AuthGate → ContentView | **NOT VERIFIED** |
| 2 | App vollständig schließen (App-Umschalter, wegwischen) | Prozess beendet | **NOT VERIFIED** |
| 3 | App erneut öffnen | Kein Login-Formular wenn Session gültig | **NOT VERIFIED** |
| 4 | Sitzung erhalten | Keychain-JWT + `/auth/me` oder Offline-Cache | **NOT VERIFIED** |
| 5 | Flugmodus aktivieren | Offline-Banner möglich | **NOT VERIFIED** |
| 6 | Lokale Funktionen prüfen | Prüfungen/lokale Daten nutzbar | **NOT VERIFIED** |
| 7 | Serverfunktion offline aufrufen | Verweigerung / verständlicher Fehler, **kein** Crash, **kein** stiller Bypass | **NOT VERIFIED** |
| 8 | Flugmodus deaktivieren | Banner weg / Sync möglich | **NOT VERIFIED** |
| 9 | Serververbindung erneut testen | Server-Decrypt/API mit Bearer OK | **NOT VERIFIED** |
| 10 | Abmelden und erneut anmelden | Keychain leer → Login → neue Session | **NOT VERIFIED** |

Zusatz (empfohlen, ebenfalls **NOT VERIFIED**): falsches Passwort; Caps-Lock-Paste; pending User sieht Warte-UI; non-admin sieht keine Admin-API.
