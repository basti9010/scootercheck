# Cursor-API Live-Smoke

Harmlose Verifikation, dass ein über die Cursor-API gestarteter Cloud Agent das ScooterCheck-Repository lesen, eine isolierte Forschungsnotiz schreiben und als Pull Request liefern kann.

Datum: 2026-11-28 (UTC).

## Ergebnis

Der Live-Pfad ist bis zum Schreiben dieser Datei erfolgreich:

| Prüfung | Beobachtung |
| --- | --- |
| Startquelle | `api` |
| Lauf | [bc-2d348346-f60b-4bb9-92e5-1ee6d5119259](https://cursor.com/agents/bc-2d348346-f60b-4bb9-92e5-1ee6d5119259) |
| Repository | `github.com/basti9010/scootercheck` |
| Modell | `grok-4.7` |
| Branch | `cursor/scootercheck-ai-bridge-live-smoke-bcc8` |
| Basis | `cursor/testflight-ci-133a` @ `d9ceba6` |
| Arbeitsbaum vor dem Test | sauber, identisch mit der Basis |
| Artefakt | nur diese Datei unter `research/ai-bridge-live-smoke/` |

Commit, Push und Pull Request gegen `cursor/testflight-ci-133a` sind die Auslieferung desselben Laufs. Die Datei im Pull Request ist der Nachweis, dass der API-Start bis zum Repository-Write durchgelaufen ist.

## Umfang

Bewusst nicht angefasst:

- iOS-App, BLE-Diagnose, Fastlane, Codemagic und GitHub-Workflows
- Deployments, TestFlight-Uploads und Hetzner
- Benutzerkonten, Secrets und Sicherheitskonfiguration

Die Notiz liegt außerhalb der produktiven Pfade (`ios/`, `.github/`, `docs/`, `codemagic.yaml`).
