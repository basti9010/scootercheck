"""Detect firmware payloads that are already plaintext (no TEA/XTEA needed).

Used when the app uploads a locally-classified Klartext dump such as
`…panicsystem.dec.bin`. Running ninebottea on those files fails with exit 4.
"""
from __future__ import annotations

import math
from collections import Counter
from pathlib import Path

from cortex_m_ivt import parse_ivt


def shannon_entropy(data: bytes) -> float:
    if not data:
        return 0.0
    counts = Counter(data)
    n = len(data)
    return -sum((c / n) * math.log2(c / n) for c in counts.values() if c)


def filename_suggests_plaintext(name: str) -> bool:
    """True for already-decrypted dumps (.dec.bin), false for .enc packages."""
    base = Path(name or "").name.lower()
    if not base:
        return False
    if base.endswith(".bin.enc") or base.endswith(".enc"):
        return False
    if base.endswith(".dec.bin") or base.endswith(".dec"):
        return True
    # Common ScooterHacking / case dump naming
    if ".dec.bin" in base or base.endswith("_dec.bin"):
        return True
    return False


def looks_like_plaintext_firmware(
    path: Path,
    *,
    original_name: str | None = None,
    data: bytes | None = None,
    ignore_filename: bool = False,
) -> tuple[bool, str]:
    """Return (is_plain, reason). Conservative: filename hint or Cortex-M IVT."""
    name = original_name or path.name
    if not ignore_filename and filename_suggests_plaintext(name):
        return True, f"filename_hint={Path(name).name}"

    blob = data if data is not None else path.read_bytes()
    if len(blob) < 8:
        return False, "too_small"

    ivt = parse_ivt(blob)
    if ivt.get("likely"):
        return True, "cortex_m_ivt"

    # Secondary: moderate entropy without .enc naming — soft signal only.
    base = Path(name).name.lower()
    sample = blob[: min(len(blob), 65_536)]
    ent = shannon_entropy(sample)
    if (
        not ignore_filename
        and ent < 6.5
        and len(blob) >= 256
        and not (base.endswith(".enc") or base.endswith(".bin.enc"))
    ):
        # Require some zero bytes so pure noise is excluded.
        zero_ratio = sample.count(0) / max(len(sample), 1)
        if zero_ratio >= 0.02:
            return True, f"low_entropy={ent:.2f}+zeros"

    return False, f"encrypted_or_unknown entropy={ent:.2f}"
