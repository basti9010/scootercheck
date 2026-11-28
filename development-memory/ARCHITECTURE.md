# Architecture (inventory of this checkout)

Derived from repo layout + `docs/ARCHITECTURE.md`. Prefer code paths over older docs when they conflict.

## Top-level layout

```
ios/ScooterCheck/          # SwiftUI app + XCTest
server/firmware-analysis/  # FastAPI analysis worker + deploy scripts
backend/                   # Auth service sources ABSENT here (pycache only)
catalogs/                  # stock-firmware.json
docs/                      # human/agent docs
research/                  # cycle7–12 labs + development-automation
.github/workflows/         # iOS tests, server tests, TestFlight, Hetzner CD
.cursor/agents/            # role prompts
.cursor/skills/            # Automation 1.0 skills (Phase C)
development-memory/        # this derived memory (Phase B)
```

## iOS layers (CONFIRMED)

```
SwiftUI screens (ContentView, Settings, FAQ, Find Hub, Radar, Firmware*, Investigation, …)
        │
        ├── BLEIdentity / Search / Radar / AR
        ├── Ninebot / Xiaomi / Navee / Pedelec / UniversalDiagnosis (read-oriented)
        ├── Integrity (FirmwareZipAnalyzer, Stock catalog, CustomFirmwareDiff, Evidence)
        ├── FirmwareForensics (local pipeline + server client + diagnostics UI)
        ├── Correlation (CrossSourceCorrelator)
        ├── Investigation (Store + Hub/UI + Combined PDF)
        └── History / ProtocolPDF / PackIntegrity
```

### Entry points

| Role | Path |
|------|------|
| `@main` | `ios/.../ScooterCheckApp.swift` |
| Navigation | `ContentView.swift`, `ScootNavigation.swift` |
| Theme | `Theme.swift`, `ScootDesign.swift` (dark `#12161C`, accent `#6BDBC2`) |
| BLE Enc2 | `Ninebot/BleClient.swift`, `Enc2SessionLifecycle.swift`, `BleWriteGate.swift` |
| Central ownership | `BLEIdentity/BLECentralCoordinator.swift` |
| Server jobs | `FirmwareForensics/FirmwareServerAnalysisClient.swift` |
| Serverdiagnose | `FirmwareForensics/FirmwareServerDiagnosticsView.swift` |

## Server layers (CONFIRMED)

| Area | Modules (examples) |
|------|---------------------|
| HTTP app | `app.py` (includes diagnostics router) |
| Diagnostics (C11) | `diagnostics_routes.py`, `diagnostics_status.py`, `diagnostics_tea.py`, `diagnostics_ghidra.py`, `diagnostics_models.py` |
| Auth helpers | `job_auth.py` (+ tests `test_api_auth_security.py`, `test_job_auth.py`) |
| Analysis | Capstone/YARA, function match/diff, semantic dataflow, activation forensics, combo policy, plaintext detect, LLM enrich/verify |
| Ghidra | `ghidra_*.py`, `ghidra_scripts/`, headless scripts under `scripts/` |
| Deploy | `deploy/release-deploy.sh`, `release-rollback.sh`, `phase1-rollout.sh`, `post-deploy-smoke.sh`, `validate-release-config.sh`, `bootstrap-deploy-user.sh` |
| Unit | systemd `scootercheck-fw.service`, nginx examples |

Runtime layout (ops docs): immutable `/opt/scootercheck/releases/<sha>/` with symlink `firmware-analysis`; data under `/var/lib/scootercheck`; env under `/etc/scootercheck/` — **outside** release tarballs.

## CI / CD

| Workflow | Trigger | Role |
|----------|---------|------|
| `ios-unit-tests.yml` | PR/push (ios paths), dispatch | macOS XCTest |
| `server-firmware-tests.yml` | PR/push (server paths), dispatch | Pytest gate for deploy |
| `testflight.yml` | dispatch / main ios paths | TestFlight upload |
| `deploy-hetzner.yml` | **workflow_dispatch only** | Prod CD; Environment `production`; no push auto-deploy |

## Investigation / correlator notes

- Investigation Hub + Combined PDF + CrossSourceCorrelator are **present** on this lineage (ported into multi-agent / later cycles).
- ZIP import ≠ installed vehicle firmware (policy).
- Soft-unlock UI is observational; `BleWriteGate` default deny.

## Not on this checkout

- Auth/login Swift sources and `backend/**/*.py` (see PR #117 line).
- Demo bypass (`AppFeatureFlags.authGateEnabled=false`) — PR #114 only; do not port here.
- Live ChatGPT↔Cursor bridge services (`services/ai-bridge/` target layout; may be empty until other agents land code).
