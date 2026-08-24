# ScooterCheck — CI-Paket (TestFlight)

Dieses Verzeichnis enthält die **TestFlight-Pipeline** für ScooterCheck.
In der aktuellen Cursor-Session war das App-Repo nicht ausgecheckt.

## Inhalt

| Pfad | Zweck |
|------|--------|
| `.github/workflows/testflight.yml` | GitHub Actions: macOS-Build → TestFlight |
| `ios/ScootProof/fastlane/` | Fastlane `beta` Lane |
| `ios/ScootProof/Gemfile` | Fastlane-Abhängigkeiten |
| `codemagic.yaml` | Alternative ohne GitHub Actions |
| `docs/TESTFLIGHT.md` | Secrets und Setup |

## In dein ScooterCheck-Repo übernehmen

Auf dem Mac oder in einer Agent-Session **mit Repo-Zugriff**:

```bash
# Beispiel: Dateien in den bestehenden Clone kopieren
cp -R .github ios docs/TESTFLIGHT.md codemagic.yaml .gitignore /pfad/zu/scootercheck/
cd /pfad/zu/scootercheck
git checkout -b cursor/testflight-ci-133a
git add .github ios/ScootProof/fastlane ios/ScootProof/Gemfile codemagic.yaml docs/TESTFLIGHT.md .gitignore
git commit -m "Add TestFlight CI via Fastlane and GitHub Actions"
git push -u origin cursor/testflight-ci-133a
```

Danach GitHub Secrets setzen (siehe `docs/TESTFLIGHT.md`) und Workflow starten.

Bundle-ID: `com.scootproof.zt3check` · Scheme: `ScootProof`
