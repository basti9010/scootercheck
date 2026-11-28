# P0 Auth Recovery — Bestandsaufnahme

**Stand:** 2026-11-28 (Europe/Berlin)  
**Arbeitsbranch:** `cursor/p0-auth-recovery-b100` (ab `cursor/login-paste-caps-b100`)  
**Nicht** auf Cycle-13/Hetzner-Firmware-Stack — Auth lebt auf Backend-Auth-Linie.

## 1. Wann wurde die Anmeldung deaktiviert?

| Fakt | Wert | Epistemic |
|------|------|-----------|
| Commit Gate aus | `e5bf66c` — `feat(ios): temporarily skip auth gate for 13:00 demo TestFlight` | **CONFIRMED** |
| Commit Silent JWT | `9b857b1` — `fix(ios): silent demo login so server decrypt works without AuthGate` | **CONFIRMED** |
| PR | [#114](https://github.com/basti9010/scootercheck/pull/114) offen, Base `cursor/backend-auth-b100` | **CONFIRMED** |
| Zeitpunkt | 2026-11-26 (~11:14 Europe/Berlin PR-Erstellung) | **CONFIRMED** |
| Mechanismus | `AppFeatureFlags.authGateEnabled = false` + `DemoAuthBootstrap` | **CONFIRMED** |

## 2. Ursprüngliche Fehlermeldung (vor Demo-Bypass)

| Aussage | Status |
|---------|--------|
| User/PM: Anmeldung nicht mehr möglich; unterwegs keine Serverkonsole | Kontext **CONFIRMED** (Task) |
| PR #113: „E-Mail oder Passwort falsch“ bei Caps-Lock-Paste | **CONFIRMED** (separater Fix) |
| Exakte Server-Root-Cause (JWT_SECRET, DB down, 5xx, …) zum Deaktivierungszeitpunkt | **INCOMPLETE** — nicht in Commit-Message belegt; Hypothesen unzulässig als CONFIRMED |

## 3. Notlösung (PR #114)

1. Login-UI übersprungen (`authGateEnabled=false`)  
2. `DemoAuthBootstrap`: stiller Login mit hartcodierten Demo-Zugangsdaten im Quelltext  
3. Zweck: Präsentation + Bearer für Server-Decrypt ohne 401  

**Security:** Hartcodierte Credentials in `DemoAuthBootstrap.swift` auf Branch `cursor/demo-skip-login-b100` — **CONFIRMED** vorhanden; Werte hier **nicht** wiederholt. Rotation nach Cleanup empfohlen (**HYPOTHESIS** ob noch gültig).

## 4. Was funktioniert noch (Branch login-paste / Recovery-Base)

| Komponente | Status | Epistemic |
|------------|--------|-----------|
| `AuthGateView` als App-Root | aktiv (kein `authGateEnabled`-Flag auf diesem Branch) | **CONFIRMED** |
| `AuthSessionStore` Login/Register/Logout/`/auth/me` | vorhanden | **CONFIRMED** |
| `AuthCredentialsNormalizer` Caps-Lock-Retry | vorhanden (PR #113) | **CONFIRMED** |
| `AuthAPIClient` → `https://api.tuningscanner.de/scootercheck` | vorhanden | **CONFIRMED** |
| Backend FastAPI unter `backend/app/` | vorhanden | **CONFIRMED** |
| Token-Speicher | **UserDefaults**, nicht Keychain | **CONFIRMED** |
| Refresh-Token | Server: kein `/auth/refresh` (live 404); Client: kein Refresh-Call | **CONFIRMED** absence → Re-Login nach JWT-Expiry (Default 14d); siehe `agent_b/REPORT_SERVER_AUTH.md` |

## 5. Was wiederhergestellt / gehärtet werden muss

1. Sicherstellen: kein produktiver Pfad mit `authGateEnabled=false` / `DemoAuthBootstrap`  
2. Token in Keychain statt UserDefaults  
3. Bootstrap: Netzwerkfehler ≠ automatische Abmeldung; nur bei 401/403/revoked clear  
4. Fehler-Taxonomie (offline / unreachable / timeout / invalid / expired / revoked / 5xx / forbidden)  
5. Offline: lokale Funktionen vs. Server-API vs. Admin trennen  
6. Tests + CI; Demo-Credentials rotieren (Ops)  
7. Kein Merge von PR #114 unverändert in produktive Dauerlinie  

## 6. Branch-Topologie

```
cursor/backend-auth-b100     PR #83  (Auth komplett)
├── cursor/login-paste-caps-b100   PR #113  ← Recovery-Base (Gate AN, Caps-Fix)
└── cursor/demo-skip-login-b100    PR #114  ← Demo-Bypass (Gate AUS) — NICHT übernehmen
cursor/p0-auth-recovery-b100       ← dieser Zyklus
```

Firmware/Cycle-13-Stack enthält **kein** `Auth/`-Paket (**CONFIRMED** auf vorherigem Checkout).
