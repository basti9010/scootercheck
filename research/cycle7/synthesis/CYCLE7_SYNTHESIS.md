# Cycle 7 – PM Synthesis (interim → implementation)

Stand: 2026-11-23 Europe/Berlin  
Branch: `cursor/server-fw-analysis-c7-b100`

## Parallel agents (started)

| Agent | ID | Focus |
|-------|-----|--------|
| A Server Infra | bc-0a42638c… | ninebottea / FastAPI / Ghidra / auth |
| B Firmware Forensics | bc-14205bc2… | Cycle-6 A/B encrypted ZIPs |
| C Ghidra Integration | bc-f9967ef9… | Headless + synthetic |
| D iOS Integration | bc-f58e7be5… | PackageLoader / ServerClient / Hub gaps |

## Inventory (CONFIRMED before agent returns)

| Component | On multi-agent before C7 | On unified | Action taken |
|-----------|--------------------------|------------|--------------|
| `server/firmware-analysis/` | missing | full FastAPI worker | **ported** (no keys) |
| `FirmwarePackageLoader` | missing | present | **ported** + tests |
| `FirmwareBinaryStaticAnalyzer` | missing | present | **ported** |
| `FirmwareServerAnalysisClient` | missing | present | **ported**; AuthSession JWT → `nil` until Auth port |
| AppSettings FW URL/token/LLM | missing | present | **ported** |
| Ghidra on this VM | absent | deploy docs | synthetic script **SKIP** without GHIDRA_HOME |
| ninebottea binary / keys | absent | `DECRYPT_CMD` on server | **not** invented; `.env.example` placeholders only |
| Cycle-6 enc plaintext | INCOMPLETE | — | unchanged policy |

## Target pipeline (documented)

```
iOS → secure API → PackageLoader → integrity → format
  → authorized plaintext (DECRYPT_CMD/ninebottea on server)
  → Ghidra headless → static analysis → forensic JSON
  → Investigation Hub
```

Encrypted local payloads: **never** treated as machine code (BinaryStaticAnalyzer `performed=false`).

## Highest-value next steps (post-merge)

1. Deploy/config verify against live `api.tuningscanner.de/scootercheck-fw` with user secrets (not in git)
2. Port `FirmwareForensicsHubView` + job poll UI
3. AuthSessionStore JWT wiring
4. CI job for synthetic Ghidra when runner has GHIDRA_HOME
