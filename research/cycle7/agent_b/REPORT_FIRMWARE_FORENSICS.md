# Agent B – Firmware Forensics (PM interim from Cycle 6)

Files: ZT3_VCU_48KMH_5d51.zip · ZT3_________panicsystem_9646.zip

CONFIRMED: encrypted VCU packs, MD5 match, entropy≈8, 2008-byte shared prefix, 56288 diffs.
HYPOTHESIS: filename 48KMH / panicsystem.
INCOMPLETE: plaintext ISA/FSM/events — do not feed enc to Ghidra.

See PR #104 reports for full tables.
