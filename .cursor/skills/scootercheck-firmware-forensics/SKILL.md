---
name: scootercheck-firmware-forensics
description: Defensive ScooterCheck firmware forensics — ZIP/BIN analysis, local/server pipelines, Ghidra artifacts, evidence tiers. Never implement illegal tuning activation or vehicle unlock writes.
---

# scootercheck-firmware-forensics

## Purpose

Improve **read-only** firmware analysis and documentation of manipulation indicators for examiners. Defensive / forensic posture only.

## When to use

- Firmware ZIP inspector, local analysis pipeline, server job client.
- Function diff / semantic dataflow / activation **forensics** (detection & reporting).
- Stock/catalog compare, YARA/Capstone hints, evidence tiers, PDF export.
- Cycle research under `research/cycle*` / `server/firmware-analysis/docs/phase*`.

## Inputs

- Package type (ZIP/BIN/ENC) and whether decrypt is available.
- Existing job/report IDs to reuse when possible.
- Design docs: phase23/231–234 docs, `docs/FIRMWARE_ZIP_INSPECTOR.md`, correlator docs.
- Companion agent: `.cursor/agents/firmware-analyst.md`, `forensic-expert.md`.

## Workflow

1. Label inputs honestly: import artifact ≠ installed vehicle FW.
2. Prefer reusing completed server/Ghidra jobs over re-running heavy analysis.
3. Extend existing orchestrator/models (`FirmwareForensics/`, server modules) — no second engine.
4. Mark INCOMPLETE when plaintext/decrypt/Ghidra missing; never invent keys.
5. Keep Dual-Source / Investigation attach semantics compatible.
6. Tests: fixture-based pytest + iOS forensics/PDF tests where applicable.
7. Document epistemic grade (CONFIRMED vs HYPOTHESIS) in reports/UI copy.

## Outputs

- Analysis code/docs/tests.
- Explicit limitations list (PARTIAL / missing decrypt / synthetic-only).

## Safety limits

- **Defensive only** — no illegal tuning activation, no limit unlock tooling, no flash helpers.
- No “enable speed” BLE writes wrapped as forensics.
- Do not claim live Ghidra host verification without Freigabe evidence.
- Do not ship TEA keys, decrypt.env, or stock binaries in git.
- SoftUnlock / combo detection remains observational documentation.
