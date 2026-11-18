"""ZIP upload safety tests — normal packages + malicious archives."""
from __future__ import annotations

import io
import tempfile
import unittest
import zipfile
from pathlib import Path

import zip_safe


def _make_zip(entries: dict[str, bytes], *, symlink_name: str | None = None) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name, data in entries.items():
            zf.writestr(name, data)
        if symlink_name is not None:
            info = zipfile.ZipInfo(symlink_name)
            # Unix symlink mode S_IFLNK | 0777
            info.create_system = 3
            info.external_attr = (0o120777 & 0xFFFF) << 16
            zf.writestr(info, b"target.bin")
    return buf.getvalue()


class ZipSafeTests(unittest.TestCase):
    def test_normal_firmware_package(self) -> None:
        # High-entropy payload (typical for .enc) — must not trip ratio guards.
        enc = bytes((i * 37 + 11) % 256 for i in range(4096))
        raw = _make_zip(
            {
                "FIRM.bin.enc": enc,
                "info.json": b'{"displayName":"ZT3","type":"VCU"}',
            }
        )
        summary = zip_safe.inspect_zip(raw)
        self.assertEqual(summary["fileCount"], 2)
        self.assertGreater(summary["uncompressedBytes"], 0)

        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "FIRM.bin.enc"
            with zipfile.ZipFile(io.BytesIO(raw), "r") as zf:
                n = zip_safe.safe_extract_member(zf, "FIRM.bin.enc", dest)
            self.assertEqual(n, 4096)
            self.assertEqual(dest.read_bytes(), enc)

    def test_path_traversal_rejected(self) -> None:
        raw = _make_zip({"../../etc/passwd": b"root:x:0:0:"})
        with self.assertRaises(zip_safe.ZipSafetyError) as ctx:
            zip_safe.inspect_zip(raw)
        self.assertIn("Traversal", str(ctx.exception))

    def test_absolute_path_rejected(self) -> None:
        raw = _make_zip({"/tmp/evil.bin": b"x" * 16})
        with self.assertRaises(zip_safe.ZipSafetyError):
            zip_safe.inspect_zip(raw)

    def test_symlink_rejected(self) -> None:
        raw = _make_zip({"FIRM.bin.enc": b"ok"}, symlink_name="link.enc")
        with self.assertRaises(zip_safe.ZipSafetyError) as ctx:
            zip_safe.inspect_zip(raw)
        self.assertIn("Symbolische Links", str(ctx.exception))

    def test_too_many_entries(self) -> None:
        entries = {f"f{i}.bin": b"x" for i in range(zip_safe.MAX_ZIP_ENTRIES + 5)}
        raw = _make_zip(entries)
        with self.assertRaises(zip_safe.ZipSafetyError) as ctx:
            zip_safe.inspect_zip(raw)
        self.assertIn("Zu viele", str(ctx.exception))

    def test_upload_size_limit(self) -> None:
        with self.assertRaises(zip_safe.ZipSafetyError):
            zip_safe.validate_upload_size(b"x" * 100, max_bytes=50)

    def test_compression_ratio_bomb(self) -> None:
        # Highly compressible payload with tiny compress size vs large claimed size
        # Build manually so ratio check triggers even if zlib is efficient.
        zeros = b"\x00" * (512 * 1024)
        raw = _make_zip({"bomb.bin": zeros})
        # Force a lower ratio threshold temporarily via monkeypatch
        old = zip_safe.MAX_COMPRESSION_RATIO
        try:
            zip_safe.MAX_COMPRESSION_RATIO = 2.0
            with self.assertRaises(zip_safe.ZipSafetyError) as ctx:
                zip_safe.inspect_zip(raw)
            self.assertIn("Kompressionsverhältnis", str(ctx.exception))
        finally:
            zip_safe.MAX_COMPRESSION_RATIO = old

    def test_empty_upload(self) -> None:
        with self.assertRaises(zip_safe.ZipSafetyError):
            zip_safe.validate_upload_size(b"")


class StockDiffTrustTests(unittest.TestCase):
    def test_oem_source_without_provenance_is_community(self) -> None:
        import stock_diff

        trust = stock_diff._trust_fields_for_ref(
            {"source": "oem", "label": "G3 VCU 1.5.15", "notes": "rexzy archive"}
        )
        self.assertEqual(trust["referenceTrust"], "communityLibrary")
        self.assertFalse(trust["referenceProvenanceVerified"])

    def test_explicit_provenance_is_manufacturer(self) -> None:
        import stock_diff

        trust = stock_diff._trust_fields_for_ref(
            {
                "source": "oem",
                "label": "OEM",
                "notes": "",
                "provenanceVerified": True,
            }
        )
        self.assertEqual(trust["referenceTrust"], "manufacturerVerified")
        self.assertTrue(trust["referenceProvenanceVerified"])

    def test_compare_identical_emits_trust_fields(self) -> None:
        import stock_diff
        from unittest import mock

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            with mock.patch.object(stock_diff, "STOCK_FW_DIR", root):
                stock = b"STOCK-BYTES-123456"
                ref = stock_diff.register_stock_file(
                    stock,
                    label="Community OEM",
                    model="zt3",
                    controller_type="VCU",
                    version="1.0",
                    source="oem",
                    notes="community library",
                )
                out = stock_diff.compare_to_stock(stock, models=["zt3"], controller_type="VCU")
                self.assertEqual(out["outcome"], "identical")
                self.assertEqual(out["referenceTrust"], "communityLibrary")
                self.assertFalse(out["referenceProvenanceVerified"])
                self.assertEqual(ref["referenceTrust"], "communityLibrary")


if __name__ == "__main__":
    unittest.main()
