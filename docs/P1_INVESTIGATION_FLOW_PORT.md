# P1-1 Investigation Flow 1.1 – Port Plan

Source: [Explore Investigation Flow branch](bc-8471e07b-d057-5dbf-a2d8-55a10357d2a2)  
Stand: 2026-11-23 Europe/Berlin

## Verdict

Investigation Flow 1.1 is **entirely absent** on `cursor/multi-agent-system-b100`.  
Tip unified: `f306bf3` · Tip multi: current HEAD · Do **not** wholesale-merge unified (carries forensics/auth lineage noise).

## Missing capabilities

- `InvestigationStore` + packs, progress/resume, identity guards
- Combined PDF + share, firmware archive into packs
- Reuse-readout / append flows
- Menu screen `.investigate` („E-Scooter untersuchen“)
- Modern `FirmwareForensicsHubView` + inspector callbacks
- Unit tests (store / combined PDF / flow logic)

## Hard dependencies also missing

Entire `FirmwareForensics/*` (esp. `FirmwareForensicReport`, `FirmwareForensicPDF`, hub/orchestrator).  
Legacy `FirmwareZipInspectorView` on multi is ZIP-only (~211 LOC); unified inspector is forensics-grade.

## Conflict risk

| File | Risk | Guidance |
|------|------|----------|
| `ContentView.swift` | **HIGH** | Surgical splice only — keep multi `.pedelec` / P0 chrome |
| `ProtocolHistoryStore` | LOW if surgical | Flow commits do not edit it; keep PackIntegrity seal |
| `BleClient` | LOW if surgical | Keep Enc2/write-gate; do not take LiveCheck from unified |
| `ProtocolPDF` | LOW | Combined PDF is separate module |

## Minimal port order

1. Firmware forensics foundation (compile set for `FirmwareForensicReport` + PDF)
2. `InvestigationModels` + `InvestigationStore` + store tests
3. Hub/Detail/Reuse/Summary UI + Flow/PDF tests
4. Inspector/Hub callbacks `(Report, Data?)` / preload
5. Surgical `ContentView` integration (`.investigate`, attach hooks)
6. `pbxproj` after each layer

## Cherry-pick candidates (prefer file checkout)

1. `44debf6` — Unify hub flow  
2. `9bd79b0` — Flow 1.1 combined PDF / archive / resume / identity  
3. `f306bf3` — progress clamp + flush-before-reload  

## Explicit non-goals

Auth gate, Ghidra phases, LiveCheck-on-BleClient, Protocol export picker, radar notification gating in `ScooterCheckApp`.
