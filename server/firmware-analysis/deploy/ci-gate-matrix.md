# CI gate matrix for Hetzner CD

| Check | Mandatory for server deploy? | Notes |
|-------|------------------------------|-------|
| Server Firmware Tests (Python) | **YES** | auth, path confinement, diagnostics, zip_safe, deploy smoke/manifest |
| Deploy workflow validate job | **YES** | SHA format + CI gate |
| iOS XCTest | **NO** | Optional quality; must not block server CD |
| TestFlight | **NO** | Signing / release train |
| Live Ghidra/TEA E2E | **NO** (Freigabe) | CONFIGURED ≠ VERIFIED |

Deploy refuses branch names; immutable SHA only.
