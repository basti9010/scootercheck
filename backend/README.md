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
| GET | `/admin/users?status_filter=pending` | Admin |
| POST | `/admin/users/{id}/approve` | Admin |
| POST | `/admin/users/{id}/reject` | Admin |
| POST | `/admin/users/{id}/disable` | Admin |
| GET | `/admin/domains` | Admin |
| POST | `/admin/domains` `{ "domain": "polizei.bayern.de" }` | Admin |
| DELETE | `/admin/domains/{domain}` | Admin |

Registrierung nur mit freigegebener E-Mail-Domain (nach dem `@`). Ohne Domain-Einträge ist Registrierung gesperrt (Admin-Seed ausgenommen).

Produktion hinter nginx: `https://api.tuningscanner.de/scootercheck/…`
