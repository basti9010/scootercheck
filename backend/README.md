# ScooterCheck Auth API

Leichtes User-Management für die iOS-App:

- Registrierung → Status `pending`
- Login (auch im Pending-Zustand, App zeigt Wartebildschirm)
- Admin in der App: User freischalten / ablehnen / deaktivieren
- Web-Admin später

## Endpoints

| Method | Path | Auth |
| --- | --- | --- |
| GET | `/health` | — |
| POST | `/auth/register` | — |
| POST | `/auth/login` | — |
| GET | `/auth/me` | Bearer |
| POST | `/auth/change-password` `{ "current_password", "new_password" }` | Bearer |
| GET | `/admin/users?status_filter=pending` | Admin |
| POST | `/admin/users/{id}/approve` | Admin |
| POST | `/admin/users/{id}/reject` | Admin |
| POST | `/admin/users/{id}/disable` | Admin |
| POST | `/admin/users/{id}/enable` | Admin |
| PATCH | `/admin/users/{id}` `{ display_name?, role?, status?, email? }` | Admin |
| DELETE | `/admin/users/{id}` | Admin |
| POST | `/admin/users/{id}/reset-password` optional `{ "new_password" }` | Admin |
| POST | `/admin/users/{id}/make-admin` | Admin |
| GET | `/admin/domains` | Admin |
| POST | `/admin/domains` `{ "domain": "polizei.bayern.de" }` | Admin |
| DELETE | `/admin/domains/{domain}` | Admin |

**Kein** `POST /auth/refresh` — Access-JWT (Default 14 Tage) muss nach Ablauf per erneutem Login ersetzt werden.

Registrierung nur mit freigegebener E-Mail-Domain (nach dem `@`). Ohne Domain-Einträge ist Registrierung gesperrt (Admin-Seed ausgenommen).

Produktion hinter nginx: `https://api.tuningscanner.de/scootercheck/…`

### Fehlerform

Auth-Fehler liefern `{ "detail": "<menschlich>", "code": "<stabil>" }` (HTTP-Status bleibt maßgeblich):

| code | typ. Status | Bedeutung |
| --- | --- | --- |
| `invalid_credentials` | 401 | Login / Passwort falsch |
| `not_authenticated` | 401 | Kein Bearer |
| `token_invalid` | 401 | JWT kaputt / falsch signiert |
| `token_expired` | 401 | JWT abgelaufen → Re-Login |
| `user_unknown` | 401 | `sub` nicht in DB |
| `account_not_active` | 403 | pending/rejected/disabled |
| `forbidden` | 403 | kein Admin |
| `email_taken` | 409 | Registrierung |
| `domain_not_allowed` / `registration_locked` | 403 | Domain-Gate |

Validierung (Pydantic) bleibt **422** mit `detail` als Array — unterscheidbar von 401 `invalid_credentials`.
5xx / nginx HTML-Fehler haben keinen Auth-`code` (Client: Status ≥ 500 → Serverfehler).

### JWT (Kompatibilität scootercheck-fw)

HS256, Claims: `sub`, `email`, `role`, `status`, `iat`, `exp`. Firmware-Worker akzeptiert denselben Bearer wenn `status=active` (oder `X-ScooterCheck-Token`). **Kein** zweites User-Auth-System.

## Tests

```bash
cd backend
pip install -r requirements.txt
PYTHONPATH=. python -m pytest tests/ -v
```
