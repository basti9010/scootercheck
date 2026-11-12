import XCTest
import CryptoKit
import zlib
@testable import ScooterCheck

final class FirmwareZipAnalyzerTests: XCTestCase {

    func testZT3EncryptedPanicPackage() throws {
        let firm = Data((0..<4096).map { UInt8(($0 * 47 + 13) & 0xFF) }) // high-ish entropy
        let md5 = InsecureMD5.hex(firm)
        let info = """
        {
          "schemaVersion": 2,
          "firmware": {
            "displayName": "ZT3 VCU panicsystem",
            "models": ["zt3"],
            "type": "VCU",
            "compatible": ["zt3_VCU_AT32"],
            "md5": "\(md5)",
            "encrypted": true
          }
        }
        """
        let zip = try ZipTestBuilder.build([
            ("info.json", Data(info.utf8)),
            ("FIRM.bin.enc", firm)
        ])
        let forensic = FirmwareForensicOrchestrator.analyze(
            fileName: "ZT3⚡VCU_ panicsystem.zip",
            data: zip
        )
        XCTAssertEqual(forensic.meta.models, ["zt3"])
        XCTAssertEqual(forensic.meta.type, "VCU")
        XCTAssertEqual(forensic.meta.compatible, ["zt3_VCU_AT32"])
        XCTAssertEqual(forensic.primaryFirmwarePath, "FIRM.bin.enc")
        XCTAssertEqual(forensic.crypto.status, .confirmedByMetadata)
        XCTAssertFalse(forensic.crypto.decryptionAvailable)
        XCTAssertFalse(forensic.binary.performed)
        XCTAssertNotNil(forensic.binary.unavailableReason)
        XCTAssertTrue(forensic.evidence.contains { $0.category == .filenameHint && $0.verifiability == .unverified })
        XCTAssertFalse(forensic.evidence.contains { $0.title.lowercased().contains("custom-fw-signatur") && $0.evidence.contains("compatible") })
        // JSON keys must not become CFW hits
        XCTAssertFalse(forensic.evidence.contains {
            $0.title.localizedCaseInsensitiveContains("Custom-FW-String") && $0.detail == "compatible"
        })
        XCTAssertTrue([FirmwareForensicVerdict.gray, .yellow].contains(forensic.verdict))
    }

    func testJsonKeysNotFlaggedAsCustomFirmware() throws {
        let info = """
        {"schemaVersion":2,"firmware":{"displayName":"Stock","models":["max"],"type":"DRV","compatible":["max_DRV_STM32F103CxT6"],"md5":"\(InsecureMD5.hex(Data([1,2,3,4])))"}}
        """
        // Tiny "firmware" that is mostly zeros (low entropy plaintext-ish) without CFW strings
        var firm = Data(repeating: 0, count: 256)
        firm[0] = 0x00; firm[1] = 0x00; firm[2] = 0x00; firm[3] = 0x20
        firm[4] = 0x01; firm[5] = 0x00; firm[6] = 0x00; firm[7] = 0x08
        let zip = try ZipTestBuilder.build([
            ("info.json", Data(info.utf8)),
            ("FIRM.bin", firm)
        ])
        let report = FirmwareZipAnalyzer.analyze(fileName: "stock.zip", data: zip)
        XCTAssertFalse(report.findings.contains {
            $0.kind == .customFirmware && ($0.detail == "compatible" || $0.detail == "firmware" || $0.detail == "type")
        })
        let forensic = report.forensic!
        XCTAssertFalse(forensic.evidence.contains {
            $0.detail == "compatible" || $0.detail == "model" || $0.detail == "firmware"
        })
    }

    func testPlainParamsSpeedFinding() throws {
        let firm = Data("STOCK_FW_OK".utf8)
        let params = "Parameters:\n- Max speed: 20 km/h\n- Firmware region: DE\n"
        let info = """
        {"schemaVersion":2,"firmware":{"displayName":"G30","models":["max"],"type":"DRV","compatible":["max_DRV_STM32"],"md5":"\(InsecureMD5.hex(firm))"}}
        """
        let zip = try ZipTestBuilder.build([
            ("info.json", Data(info.utf8)),
            ("FIRM.bin", firm),
            ("params.txt", Data(params.utf8))
        ])
        let forensic = FirmwareForensicOrchestrator.analyze(fileName: "g30.zip", data: zip)
        XCTAssertTrue(forensic.evidence.contains { $0.category == .limitHint && $0.confirmed })
        XCTAssertEqual(forensic.crypto.decryptionAvailable, false)
    }

    func testRejectsNonZip() {
        let report = FirmwareZipAnalyzer.analyze(fileName: "x.bin", data: Data("not a zip".utf8))
        XCTAssertNotNil(report.forensic)
    }

    func testReferenceIdenticalComparison() throws {
        let firm = Data("REFERENCE_IMAGE_BYTES_1234567890".utf8)
        let ref = FirmwareReferenceRecord(
            id: "r1",
            manufacturer: "Ninebot",
            model: "max",
            controllerType: "DRV",
            hardwareVersion: "STM32",
            firmwareVersion: "1.0",
            sha256: FirmwareDigest.sha256Hex(firm),
            md5: FirmwareDigest.md5Hex(firm),
            byteCount: firm.count,
            origin: "test",
            verificationStatus: .userImported,
            createdAt: Date(),
            plaintextBytes: firm
        )
        let zip = try ZipTestBuilder.build([("FIRM.bin", firm)])
        let forensic = FirmwareForensicOrchestrator.analyze(
            fileName: "same.zip",
            data: zip,
            references: [ref]
        )
        XCTAssertEqual(forensic.comparison?.outcome, .identical)
        XCTAssertEqual(forensic.verdict, .green)
    }
}

private enum InsecureMD5 {
    static func hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum ZipTestBuilder {
    static func build(_ files: [(String, Data)]) throws -> Data {
        var out = Data()
        var central = Data()
        var offsets: [UInt32] = []
        for (name, payload) in files {
            offsets.append(UInt32(out.count))
            let nameData = Data(name.utf8)
            var local = Data()
            local.append(contentsOf: u32(0x04034b50))
            local.append(contentsOf: u16(20))
            local.append(contentsOf: u16(0))
            local.append(contentsOf: u16(0))
            local.append(contentsOf: u16(0))
            local.append(contentsOf: u16(0))
            local.append(contentsOf: u32(crc32(payload)))
            local.append(contentsOf: u32(UInt32(payload.count)))
            local.append(contentsOf: u32(UInt32(payload.count)))
            local.append(contentsOf: u16(UInt16(nameData.count)))
            local.append(contentsOf: u16(0))
            local.append(nameData)
            local.append(payload)
            out.append(local)

            var cen = Data()
            cen.append(contentsOf: u32(0x02014b50))
            cen.append(contentsOf: u16(20))
            cen.append(contentsOf: u16(20))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u32(crc32(payload)))
            cen.append(contentsOf: u32(UInt32(payload.count)))
            cen.append(contentsOf: u32(UInt32(payload.count)))
            cen.append(contentsOf: u16(UInt16(nameData.count)))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u16(0))
            cen.append(contentsOf: u32(0))
            cen.append(contentsOf: u32(offsets.last!))
            cen.append(nameData)
            central.append(cen)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        var eocd = Data()
        eocd.append(contentsOf: u32(0x06054b50))
        eocd.append(contentsOf: u16(0))
        eocd.append(contentsOf: u16(0))
        eocd.append(contentsOf: u16(UInt16(files.count)))
        eocd.append(contentsOf: u16(UInt16(files.count)))
        eocd.append(contentsOf: u32(UInt32(central.count)))
        eocd.append(contentsOf: u32(centralOffset))
        eocd.append(contentsOf: u16(0))
        out.append(eocd)
        return out
    }

    private static func u16(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
    }

    private static func u32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    private static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buf in
            let ptr = buf.bindMemory(to: UInt8.self).baseAddress
            return UInt32(zlib.crc32(0, ptr, uInt(data.count)))
        }
    }
}
