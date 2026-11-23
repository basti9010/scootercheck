# Agent D ingest

Source: [Security & QA](bc-aeba23c0-e2e0-528f-914e-99241b7595a6)  
Branch: `cursor/security-qa-cycle9-b100` @ `2e14826`

## Merged (3-way with UnboundLocal fix)
- `_confined_stored_file` for plaintext/decompile downloads
- basename-only client paths; open-auth CRITICAL health warning
- zip backslash reject (Z1); `_secure_mkdir` 0o750
- `test_path_confinement.py` + zip_safe backslash case

## Closed
S2 path confinement · S1 abs path disclosure · Z1 backslash · related lows

## Still open
I1 process isolation · A1 open-auth if secrets unset (warned) · U1 full-body buffer
