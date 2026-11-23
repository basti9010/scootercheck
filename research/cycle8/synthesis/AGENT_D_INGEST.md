# Agent D ingest

Source: [QA & Security](bc-c8d1ac3c-9319-543b-8da4-72dd048bc579)  
Branch: `cursor/qa-security-cycle8-c579` @ `6e9ae1d`

## Verdict
10/10 checklist items PASS (isolation host-side INCOMPLETE).  
Pytest light suite: 113 passed, 6 skipped (no angr/yara/unicorn/Ghidra/TEA).  
Added: `test_upload_integrity_sha256.py` + `.gitignore` hardening.

## Top residuals (Medium)
1. Open-auth if tokens unset  
2. Analyzer UID isolation  
3. Plaintext download path confinement  
4. Absolute paths in API responses  
5. Upload memory DoS without nginx body limit
