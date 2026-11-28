# Cycle 13 – Abschlussbericht

**Stand:** 2026-11-28 (Europe/Berlin)  
**PR:** [#116](https://github.com/basti9010/scootercheck/pull/116) `cursor/cycle13-prod-ghidra-b100`  
**Produktiv-Deploy (aktuell):** SHA `20c5d0ce423bd5a953dccdff02cda03a954d8f18` (Deploy #4)  
**Cycle-13-Code:** noch **nicht** auf Prod (Freigabe ausstehend)

---

## 1. Subagents (tatsächlich eingesetzt)

| Agent | Rolle | Status | Ergebnis |
|-------|-------|--------|----------|
| **A** | Server Engineer | fertig | Deploy-Infra (sudoers, sleep, migration fail-closed, env-key audit) |
| **B** | Ghidra Specialist | fertig | Report `research/cycle13/agent_b/`; Live = CONFIGURED ≠ VERIFIED |
| **C** | QA & Security | fertig | 138 pytest OK; P0 CI-Gate (Deploy-SHA) adressiert |

---

## 2. CI-Status

| Check | Grade | Epistemic |
|-------|-------|-----------|
| `server-firmware-tests` auf Branch HEAD | success (pytest job) | **CONFIRMED** |
| Deploy-CI-Gate prüft jetzt Deploy-SHA | IMPLEMENTED in PR #116 | **CONFIRMED** (Code); **INCOMPLETE** (noch nicht live deployed) |
| Soft-Skip Deploy #4 (Workflow fehlte auf Default) | historisch | **CONFIRMED** |

---

## 3. Produktives Deployment-SHA

| Item | Wert | Grade |
|------|------|-------|
| Live SHA | `20c5d0ce423bd5a953dccdff02cda03a954d8f18` | **DEPLOYED** / **CONFIRMED** |
| Layout | `/opt/scootercheck/releases/<sha>/` + Symlink `firmware-analysis` | **CONFIRMED** (Deploy-Logs #4) |
| Service | `scootercheck-fw` | **CONFIRMED** |

---

## 4. Server-Erreichbarkeit

| Probe | Ergebnis | Epistemic |
|-------|----------|-----------|
| `GET …/scootercheck-fw/health` | `ok:true` | **CONFIRMED** |
| Public URL | `https://api.tuningscanner.de/scootercheck-fw/health` | **CONFIRMED** |

---

## 5. Authentifizierungsstatus

| Flag (Health) | Wert | Epistemic |
|---------------|------|-----------|
| `authMode` | `separated` | **CONFIRMED** |
| `apiTokenGrantsAdmin` | `false` | **CONFIRMED** |
| `adminApiTokenConfigured` | `false` | **CONFIRMED** |
| `authSecurityOk` | `true` | **CONFIRMED** |
| Advisory | `ADMIN_API_TOKEN unset` → Admin nur via JWT `role=admin` | **CONFIRMED** |
| Diagnostics ohne Auth | HTTP **401** | **CONFIRMED** |
| Hyphen-Keys (`API-TOKEN-…`) | historisch falsch; Audit-Skript + Docs korrigieren | **IMPLEMENTED** (Repo); Prod-Env-Audit **INCOMPLETE** ohne Host-Freigabe |

**Keine produktiven Secret-Änderungen in diesem Cycle** (Policy).

---

## 6. NinebotTEA-Diagnose

| Stufe | Status | Epistemic |
|-------|--------|-----------|
| CONFIGURED | `decryptConfigured:true` | **CONFIRMED** |
| AVAILABLE | Pfad/Binary auf Host | **HYPOTHESIS** (Health-Flag; kein Host-Probe ohne SSH) |
| VERIFIED | Selftest decrypt | **INCOMPLETE** (kein Admin-Auth) |
| Format-Support | nicht aus Installation ableitbar | **CONFIRMED** (Policy) |

---

## 7. Ghidra-Installationsstatus

| Stufe | Status | Epistemic |
|-------|--------|-----------|
| CONFIGURED | `ghidraConfigured:true`, `ghidraEnabled:true` | **CONFIRMED** |
| AVAILABLE | Headless auflösbar | **HYPOTHESIS** (Health ⇒ resolvable) |
| VERIFIED | analyzeHeadless + Export | **INCOMPLETE** |
| Agent-VM Headless | absent → `MISSING_PREREQUISITE` | **CONFIRMED** |

---

## 8. Tatsächlich ausgeführte Ghidra-Analysen

| Umgebung | Ausführung | Ergebnis |
|----------|------------|----------|
| Cloud-Agent-VM | CLI selftest | `executed=false`, `MISSING_PREREQUISITE` — **CONFIRMED** |
| Unit-Tests (Mock) | pytest | Pass — **TESTED**, nicht Live |
| Hetzner Live | Selftest / Headless | **nicht ausgeführt** — Auth + kein SSH |

**Kein Live-VERIFIED. Keine Mock-Ergebnisse als Live-Erfolg.**

---

## 9. Ergebnisexporte

| Export | Live | Epistemic |
|--------|------|-----------|
| `diag.functions.json` / `diag.callgraph.json` Digests | nicht erzeugt (Live) | **INCOMPLETE** |
| Fixture SHA-256 | `3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea` | **CONFIRMED** (Repo + lokale Selftest-Metadaten) |

---

## 10. API-Ende-zu-Ende-Status

| Schritt | Status | Grade |
|---------|--------|-------|
| Health | OK | **DEPLOYED** / **CONFIRMED** |
| Diagnostics Routes auf Live-SHA | vorhanden (401≠404) | **DEPLOYED** / **CONFIRMED** |
| Admin Selftest | blockiert (`adminApiTokenConfigured:false`) | **INCOMPLETE** |
| Analyse-Job → Ghidra → JSON Abruf | nicht live bewiesen | **INCOMPLETE** |

---

## 11. iOS-Integrationsstatus

| Komponente | Status | Epistemic |
|------------|--------|-----------|
| `FirmwareServerDiagnosticsView` | IMPLEMENTED | **CONFIRMED** (Repo) |
| Settings → Serverdiagnose | IMPLEMENTED | **CONFIRMED** |
| Live iOS → Prod Selftest | braucht Admin-Token in App-Settings | **INCOMPLETE** |
| Device/TestFlight E2E | nicht in diesem Agent-Lauf | **INCOMPLETE** |

---

## 12. Sicherheitsbefunde

| Befund | Schwere | Status |
|--------|---------|--------|
| Shared Token ≠ Admin (`API_TOKEN_GRANTS_ADMIN=0`) | — | **CONFIRMED** OK |
| `ADMIN_API_TOKEN` unset | Advisory | **CONFIRMED**; Freigabe nötig |
| Diagnostics unauth → 401 | — | **CONFIRMED** OK |
| Deploy-CI Soft-Skip auf Default | P0 | **FIXED** in PR (noch nicht auf Prod) |
| Secrets in Logs/Git | — | keine ausgegeben — **CONFIRMED** |

---

## 13. Behobene Probleme (Repo / PR #116)

1. Bootstrap-Sudoers: `is-active --quiet`, `/usr/bin/systemctl`  
2. `release-deploy.sh`: Post-Restart-Sleep; First-Migration fail-closed ohne root  
3. `audit-env-key-names.sh` (Key-Namen only)  
4. CI-Gate: `server-firmware-tests.yml` + grüne Runs gegen **Deploy-SHA**  
5. Ghidra selftest: `ExportAllDecompiled.java` in `REQUIRED_SCRIPTS`; Cycle-13-Labels  
6. Smoke: optional `SMOKE_GHIDRA_SELFTEST=1` + Admin-Token → echte `executionVerified`-Prüfung  

---

## 14. Verbleibende Blockaden

1. **Freigabe:** Prod `ADMIN_API_TOKEN` setzen + Restart (`API_TOKEN_GRANTS_ADMIN=0` belassen)  
2. **Live Ghidra Selftest** (Host-CLI oder Admin-API) → JSON archivieren  
3. **Merge/Deploy** Cycle-13-SHA nur nach Reviewer + Environment `production`  
4. `server-firmware-tests.yml` auf Default-Branch landen (Gate fail-closed sonst)  
5. Optional: Env-Key-Audit auf Host (Unterstriche vs. Bindestriche)

---

## 15. Nächste Maßnahmen (konkret)

1. User-Freigabe für `ADMIN_API_TOKEN` auf Hetzner (Wert nur lokal/Secret Store; nie Chat).  
2. `systemctl restart scootercheck-fw` → Health: `adminApiTokenConfigured:true`.  
3. Host: `python3 diagnostics_ghidra.py | tee /tmp/ghidra-c13.json` **oder** API Selftest mit Admin-Token.  
4. Pass-Kriterium: `executed=true`, `grades.verified=true`, Export-Digests gesetzt.  
5. PR #116 mergen → Deploy-Workflow mit **voller SHA** + grünem Server-CI (kein `skip_ci_gate`).  
6. iOS: Admin-Token in Settings → Serverdiagnose Selftest.

---

## Qualitätsstufen (Gesamt)

| Ziel | Stufe | Epistemic |
|------|-------|-----------|
| Deploy-Infra / Auth-Gates (Repo) | **IMPLEMENTED** + **TESTED** | **CONFIRMED** |
| Prod Health / Auth separated | **DEPLOYED** | **CONFIRMED** |
| Ghidra Live Analyse | — | **INCOMPLETE** (nicht END_TO_END_VERIFIED) |
| Cycle-13 Erfolgskriterium | **nicht erfüllt** bis Live-Selftest | **CONFIRMED** |

**Cycle 13 ist vorbereitet und ehrlich unvollständig: Prod ist CONFIGURED/AVAILABLE (Health), nicht Ghidra-VERIFIED.**
