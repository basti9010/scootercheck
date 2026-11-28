# P0 Auth Recovery — Abschlussbericht

**Stand:** 2026-11-28 (Europe/Berlin)  
**PR:** [#117](https://github.com/basti9010/scootercheck/pull/117) `cursor/p0-auth-recovery-b100`  
**Base:** `cursor/login-paste-caps-b100`

## Subagents

| Agent | ID | Ergebnis |
|-------|-----|----------|
| A iOS | bc-4be3a27a-f8ed-5796-b8e6-9ab154f67a71 | Keychain, Bootstrap, Offline-Gate |
| B Server | bc-63876ef9-7e5d-54b0-a357-c252d9b9a472 | Error-codes, Refresh absent, pytest |
| C Security/QA | bc-3c058d90-0b89-5499-8bf2-5fc195e31858 | Bypass purged, role tests, report |

## Qualitätsstufen

| Ziel | Stufe | Epistemic |
|------|-------|-----------|
| Demo-Bypass auf Recovery-Branch entfernt | **IMPLEMENTED** + Regressionstests | **CONFIRMED** |
| Keychain + Migration | **IMPLEMENTED** | **CONFIRMED** (Code); Device **INCOMPLETE** |
| Netz ≠ Logout | **IMPLEMENTED** | **CONFIRMED** (Code) |
| Offline lokal vs Server vs Admin | **IMPLEMENTED** | **CONFIRMED** (Code) |
| Server Error-`code` | **IMPLEMENTED** + **TESTED** | **CONFIRMED**; Prod **INCOMPLETE** ohne Deploy |
| Backend pytest | **TESTED** (19 pass) | **CONFIRMED** |
| XCTest auf macOS/Gerät | authored | **INCOMPLETE** (kein Xcode auf Agent-VM) |
| Echter iPhone-Login | — | **INCOMPLETE** |
| END_TO_END_VERIFIED | — | **NEIN** |

## 1–11 Kickoff-Punkte

Siehe kopierbaren Block in der Nutzerantwort / `research/p0-auth/`.

## Nächste Schritte

1. XCTest auf macOS / CI mit Xcode  
2. TestFlight Build von #117  
3. Gerät: Login → Restart → Offline-Banner → Server-Aktion  
4. Freigabe: Backend-Deploy (`code`-Feld)  
5. Ops: Credentials aus PR #114 rotieren; #114 nicht mergen  
6. Optional später: Token-Denylist / Refresh
