# TestFlight ohne eigenen Mac

ScooterCheck ist eine native Xcode-App. Build und Upload laufen über einen **Cloud-Mac** (GitHub Actions oder Codemagic) — analog zu EAS bei TuningScanner.

## Variante A — GitHub Actions (empfohlen)

Dateien:
- `.github/workflows/testflight.yml`
- `ios/ScootProof/fastlane/*`
- `ios/ScootProof/Gemfile`

### 1. App Store Connect API Key

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Users and Access** → **Integrations** → **App Store Connect API**
2. Key mit Rolle **Admin** oder **App Manager** anlegen
3. `.p8` einmalig herunterladen; Key-ID und Issuer-ID notieren

### 2. GitHub Secrets

Im Repo unter **Settings → Secrets and variables → Actions**:

| Secret | Inhalt |
|--------|--------|
| `APPLE_TEAM_ID` | 10-stellige Team-ID (developer.apple.com → Membership) |
| `APP_STORE_CONNECT_API_KEY_ID` | Key-ID (z. B. `AB12CD34EF`) |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer-UUID |
| `APP_STORE_CONNECT_API_KEY_P8` | kompletter Text der `.p8` (inkl. `-----BEGIN PRIVATE KEY-----`) |
| `APP_STORE_CONNECT_API_KEY_IS_BASE64` | leer lassen, oder `true` wenn du die `.p8` als Base64 speicherst |

Optional: Wenn die `.p8` in Secrets kaputtgeht (Zeilenumbrüche), Base64 nutzen:

```bash
base64 -i AuthKey_XXXXX.p8 | pbcopy
```

Secret `APP_STORE_CONNECT_API_KEY_P8` = Base64-String, `APP_STORE_CONNECT_API_KEY_IS_BASE64` = `true`.

### 3. App in App Store Connect

Die App mit Bundle-ID `com.scootproof.zt3check` muss existieren (wie bei TuningScanner). Sonst zuerst eine neue iOS-App anlegen; Display-Name kann **ScooterCheck** sein.

### 4. Starten

- Push auf `main` / `master` / `cursor/dual-tuning-detection-133a` (nur wenn sich `ios/ScootProof/**` ändert), oder
- **Actions → TestFlight → Run workflow**

Nach dem Upload erscheint der Build in TestFlight (Verarbeitung oft 5–20 Minuten).

### 5. Signing-Hinweis

Die Lane holt Zertifikat und App-Store-Profil über die API (`get_certificates` / `get_provisioning_profile`). Beim **ersten** Lauf muss ggf. in [developer.apple.com](https://developer.apple.com) noch kein widersprüchliches manuelles Profil für dieselbe Bundle-ID blockieren. Der API-Key braucht Rechte, Zertifikate zu erzeugen.

## Variante B — Codemagic

1. Repo bei [codemagic.io](https://codemagic.io) verbinden
2. Root-Datei `codemagic.yaml` nutzen
3. App Store Connect Integration „ScooterCheck“ anlegen und API Key hinterlegen
4. Code signing: Bundle-ID `com.scootproof.zt3check`, Distribution **App Store**
5. Workflow **testflight** starten

## Was diese Cloud-Umgebung nicht kann

Der Cursor-Agent läuft unter Linux ohne Apple-Zugang. Er kann die Pipeline **anlegen**, aber den Build nicht selbst ausführen. Der erste Upload passiert, sobald die Secrets gesetzt sind und der Workflow einmal gelaufen ist.
