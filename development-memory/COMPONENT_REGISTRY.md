# Component Registry

Inventory of **this checkout** (`cursor/development-automation-b100`). Counts are approximate file inventories, not LOC.

## iOS (`ios/ScooterCheck/ScooterCheck/`)

| Component | Path | Role |
|-----------|------|------|
| App shell | `ScooterCheckApp.swift`, `ContentView.swift`, `ScootNavigation.swift` | Entry, routing, menu |
| Feature flags / settings | `AppFeatureFlags.swift`, `AppSettings.swift`, `SettingsView.swift` | Toggles + prefs |
| Design | `Theme.swift`, `ScootDesign.swift` | Tokens |
| FAQ / Privacy | `FAQ*.swift`, `Privacy*.swift` | Content screens |
| Find / Search | `ScooterFindHubView.swift`, `BLESearch*`, `ScooterFinder*` | Locate devices |
| Radar / Map | `BLEWatchRadar*`, `BLERadarSession.swift`, `RadarMap/` | Watch + map history |
| AR finder | `BLESearchAR*` | AR signal path |
| BLE identity | `BLEIdentity/` | Identify, capability, GATT, central coordinator |
| Ninebot | `Ninebot/` | BleClient, Enc2 lifecycle, write gate, telemetry, protocol |
| Xiaomi | `Xiaomi/` | Classic plaintext profiles |
| Universal / Navee / Pedelec | `UniversalDiagnosis/`, `Pedelec/` | Broader diagnose |
| Auslesen UI | `Auslesen/` | Device readout screens |
| Integrity | `Integrity/` | ZIP analyzer, stock/custom diff, evidence, PDF, pack integrity, history store |
| Firmware forensics | `FirmwareForensics/` | Local pipeline, server client, hub, diagnostics UI, PDF/scorer |
| Correlation | `Correlation/` | CrossSourceCorrelator + models |
| Investigation | `Investigation/` | Store, hub/detail, combined PDF, reuse prompt |
| History UI | `History/` | Protocol history overview |
| ZIP inspector (legacy surface) | `FirmwareZipInspectorView.swift` | Import UI |

**Tests:** `ios/ScooterCheck/ScooterCheckTests/` — ~48 suites, ~395 `test*` methods (inventory count).

## Server (`server/firmware-analysis/`)

| Area | Key files |
|------|-----------|
| App | `app.py` |
| Diagnostics | `diagnostics_*.py` |
| Job auth | `job_auth.py` |
| Static / semantic analysis | `capstone_extract.py`, `function_*.py`, `semantic_dataflow.py`, `activation_forensics.py`, `combo_*`, `plaintext_detect.py`, … |
| Ghidra bridge | `ghidra_decompile.py`, `ghidra_reproducibility.py`, `ghidra_scripts/` |
| Catalog / stock | `reference_catalog.py`, `stock_diff.py`, `import_rexzy_stock.py`, … |
| Deploy | `deploy/*` |
| Tests | `test_*.py` (~44 modules) + `testdata/` phase fixtures |

## Backend

| Path | Status on this checkout |
|------|-------------------------|
| `backend/app/*.py` | **Missing** (only `__pycache__`) |
| `backend/tests/*.py` | **Missing** (only `__pycache__`) |

Auth service sources are expected on the backend-auth / #117 line — record as registry gap.

## Ops / CI / docs

| Component | Path |
|-----------|------|
| iOS CI | `.github/workflows/ios-unit-tests.yml` |
| Server CI | `.github/workflows/server-firmware-tests.yml` |
| TestFlight | `.github/workflows/testflight.yml`, `docs/TESTFLIGHT.md`, `codemagic.yaml` |
| Hetzner CD | `.github/workflows/deploy-hetzner.yml`, `docs/HETZNER_DEPLOYMENT_SETUP.md`, `docs/DEPLOY_SECURITY.md` |
| Stock catalog | `catalogs/stock-firmware.json` |
| Agent roles | `.cursor/agents/{project-manager,ios-developer,firmware-analyst,bluetooth-specialist,forensic-expert,ui-ux-designer,qa-security}.md` |
| Skills | `.cursor/skills/scootercheck-*/SKILL.md` |
| Research cycles | `research/cycle{7..12}/`, `research/development-automation/` |

## Machine-readable

See `component_registry.json`.
