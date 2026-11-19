"""Tests for already-plaintext firmware detection (skip TEA/XTEA)."""
from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

import plaintext_detect


def _cortex_m_blob(n: int = 512) -> bytes:
    blob = bytearray(n)
    struct.pack_into("<I", blob, 0, 0x20020000)
    struct.pack_into("<I", blob, 4, 0x08000101)
    return bytes(blob)


class FilenameHintTests(unittest.TestCase):
    def test_dec_bin_is_plain(self) -> None:
        self.assertTrue(plaintext_detect.filename_suggests_plaintext("ZT3 VCU_panicsystem.dec.bin"))
        self.assertTrue(plaintext_detect.filename_suggests_plaintext("FIRM.dec.bin"))

    def test_enc_is_not_plain(self) -> None:
        self.assertFalse(plaintext_detect.filename_suggests_plaintext("FIRM.bin.enc"))
        self.assertFalse(plaintext_detect.filename_suggests_plaintext("payload.enc"))

    def test_looks_like_from_dec_filename(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "noise.bin"
            # High-entropy-ish without IVT — filename alone must win.
            path.write_bytes(bytes(range(256)) * 4)
            ok, reason = plaintext_detect.looks_like_plaintext_firmware(
                path, original_name="ZT3 ⚡ VCU_panicsystem.dec.bin"
            )
            self.assertTrue(ok)
            self.assertIn("filename_hint", reason)


class IvtAndEntropyTests(unittest.TestCase):
    def test_cortex_m_ivt(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "dump.bin"
            path.write_bytes(_cortex_m_blob())
            ok, reason = plaintext_detect.looks_like_plaintext_firmware(path)
            self.assertTrue(ok)
            self.assertEqual(reason, "cortex_m_ivt")

    def test_high_entropy_enc_not_plain(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "FIRM.bin.enc"
            # Near-random bytes
            path.write_bytes(bytes((i * 37 + 11) % 256 for i in range(4096)))
            ok, reason = plaintext_detect.looks_like_plaintext_firmware(path)
            self.assertFalse(ok)
            self.assertIn("encrypted_or_unknown", reason)

    def test_ignore_filename_still_accepts_ivt(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "FIRM.bin.enc"
            path.write_bytes(_cortex_m_blob())
            ok, reason = plaintext_detect.looks_like_plaintext_firmware(
                path, ignore_filename=True
            )
            self.assertTrue(ok)
            self.assertEqual(reason, "cortex_m_ivt")


if __name__ == "__main__":
    unittest.main()
