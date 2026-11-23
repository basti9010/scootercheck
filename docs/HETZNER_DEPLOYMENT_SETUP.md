# Hetzner Deployment Setup (einmalig)

Für jemanden, der vor allem am **iPad** arbeitet: die Schritte nutzen die **GitHub-Weboberfläche** und die **Hetzner-Webkonsole**. Lange Terminal-Sessions sind nur für den einmaligen SSH-Setup nötig (Mac/PC oder Hetzner Console).

**Status:** Diese Einrichtung ist **nicht** erledigt, bis du die Checkliste unten abhakst. Das Repo allein deployt nichts.

---

## Was du danach kannst

1. In GitHub **Actions → Deploy Hetzner** einen Commit-SHA eingeben  
2. Freigabe im Environment **production** tippen  
3. Der Runner installiert die Version auf dem bestehenden Server  
4. Bei Smoke-Fehler: automatischer Rollback

Keine zweiten Server. Keine automatischen Deploys bei Push.

---

## Checkliste (einmalig)

### 1) GitHub Environment `production`

1. Repo → **Settings → Environments → New environment** → Name: `production`  
2. **Required reviewers**: dich selbst (und ggf. Vertrauensperson)  
3. Optional: Deployment branches auf die Deploy-Branches einschränken  

### 2) Environment Secrets (nur Namen – Werte nie in Chat/Issues)

| Secret | Zweck |
|--------|--------|
| `HETZNER_SSH_PRIVATE_KEY` | Privater Schlüssel des Deploy-Users |
| `HETZNER_SSH_KNOWN_HOSTS` | Ausgabe von `ssh-keyscan` (Host-Key!) |
| `HETZNER_SSH_HOST` | z. B. `api.tuningscanner.de` |
| `HETZNER_SSH_USER` | z. B. `scootercheck-deploy` (**nicht** root) |
| `HETZNER_DEPLOY_PATH` | optional, Default `/opt/scootercheck/firmware-analysis` |
| `HEALTH_URL` | optional, Default `http://127.0.0.1:8088/health` |

### 3) SSH-Schlüssel + Deploy-User (einmal auf dem Server)

In der **Hetzner Console** (als root):

1. Schlüsselpaar erzeugen (auf dem Mac) und **nur den Public Key** auf den Server legen  
2. Skript im Repo ausführen (nach Code-Stand):  
   `CONFIRM_BOOTSTRAP=YES DEPLOY_PUBKEY_FILE=/path/to/key.pub bash deploy/bootstrap-deploy-user.sh`  
3. `known_hosts` mit `ssh-keyscan -H api.tuningscanner.de` erzeugen → Secret `HETZNER_SSH_KNOWN_HOSTS`  
4. Private Key → Secret `HETZNER_SSH_PRIVATE_KEY`  

**Host-Key-Prüfung bleibt an.** Nie `StrictHostKeyChecking=no`.

### 4) Server-Auth härten (manuell in `/etc/scootercheck/firmware-analysis.env`)

Empfohlen:

- `API_TOKEN_GRANTS_ADMIN=0`  
- `ADMIN_API_TOKEN=` (langer Zufallswert)  
- `JWT_SECRET=` wie Auth-Service  

Secrets **nicht** ins Git.

### 5) Erster Dry-Run

Actions → **Deploy Hetzner (firmware-analysis)**  

- `git_sha` = **voller 40-Zeichen-Commit-SHA** (keine Branch-Tips) mit grünem **Server Firmware Tests**  
- `confirm_deploy` = **false**  
- optional `remote_dry_run` = **true** für SSH-Plan ohne Writes  

Erst wenn Dry-Run und Reviewer-OK: `confirm_deploy=true`.  
iOS XCTest ist **nicht** blockierend für Server-Deploy.

---

## Künftig deployen

1. PR mergen / Commit wählen  
2. Warten bis **Server Firmware Tests** grün  
3. Workflow Dispatch mit SHA + `confirm_deploy=true`  
4. Environment-Freigabe tippen  

iOS XCTest ist **nicht** Pflicht für Server-Deploy.

## Rollback

- Automatisch bei fehlgeschlagenem Smoke nach erfolgreichem Release  
- Manuell auf dem Host:  
  `CONFIRM_PROD_DEPLOY=YES bash /opt/scootercheck/firmware-analysis/deploy/release-rollback.sh`

Daten unter `/var/lib/scootercheck` werden dabei **nicht** gelöscht.

---

## Noch nicht erledigt (ehrlich)

- [ ] Environment `production` angelegt  
- [ ] Secrets gesetzt  
- [ ] Deploy-User gebootstrappt  
- [ ] `API_TOKEN_GRANTS_ADMIN=0` + `ADMIN_API_TOKEN`  
- [ ] Erster Dry-Run erfolgreich  
- [ ] Erster echter Deploy (nur mit bewusster Freigabe)
