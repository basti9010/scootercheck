"""Firmware identity / IVT suggestion tests (Phase 2.2B)."""
from __future__ import annotations

import struct
import unittest
from pathlib import Path

import firmware_identify as fi


def _thumb_blob_with_ivt(base: int = 0x08000000) -> bytes:
    """Minimal Cortex-M image: SP + reset thumb + tiny handler."""
    reset_off = 0x10
    img = bytearray(64)
    struct.pack_into("<I", img, 0, 0x20001000)
    struct.pack_into("<I", img, 4, (base + reset_off) | 1)
    # reset_handler: bx lr
    img[reset_off : reset_off + 2] = b"\x70\x47"
    return bytes(img)


class FirmwareIdentifyTests(unittest.TestCase):
    def test_cortex_m_ivt_selected(self) -> None:
        blob = _thumb_blob_with_ivt()
        out = fi.identify_firmware_image(blob)
        self.assertTrue(out["ok"])
        self.assertEqual(out["baseAddr"], "0x08000000")
        self.assertTrue(out["thumbLikely"])
        self.assertFalse(out["architectureUnknown"])
        self.assertGreaterEqual(len(out["entryPoints"]), 1)
        self.assertEqual(out["entryPoints"][0]["name"], "reset")

    def test_unknown_layout_flagged(self) -> None:
        blob = b"\xff" * 32
        out = fi.identify_firmware_image(blob)
        self.assertFalse(out["ok"])
        self.assertTrue(out["architectureUnknown"])
        self.assertTrue(any("unsicher" in x.lower() or "uncertain" in x.lower() or "no-plausible" in x for x in (out.get("notes") or []) + (out.get("analysisLimitations") or [])))

    def test_fixture_version_a_identifies(self) -> None:
        path = Path(__file__).resolve().parent / "testdata" / "thumb_validation" / "bin" / "version_a.bin"
        if not path.is_file():
            self.skipTest("fixture missing")
        out = fi.identify_firmware_image(path)
        self.assertTrue(out["ok"])
        self.assertEqual(out["processor"], "ARM:LE:32:Cortex")
        self.assertTrue(str(out["baseAddr"]).lower().startswith("0x08"))


if __name__ == "__main__":
    unittest.main()
