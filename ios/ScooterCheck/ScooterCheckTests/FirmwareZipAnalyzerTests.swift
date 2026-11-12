import XCTest
import CryptoKit
import zlib
@testable import ScooterCheck

final class FirmwareZipAnalyzerTests: XCTestCase {

    func testAnalyzesZipV3WithParamsAndUnlockHints() throws {
        let info = """
        {
          "schemaVersion": 2,
          "firmware": {
            "displayName": "G30 Test CFW",
            "models": ["max"],
            "type": "DRV",
            "compatible": ["max_DRV_STM32F103CxT6"],
            "md5": "REPLACE"
          }
        }
        """
        let firm = Data("SHFW COMPAT patch Max speed German Maneuver throttle and brake hold".utf8)
        let md5 = InsecureMD5.hex(firm)
        let infoFixed = info.replacingOccurrences(of: "REPLACE", with: md5)
        let params = """
        Parameters:
        - Max speed: 33 km/h
        - DE Max speed: 22 km/h
        - Firmware region: auto
        - Applied profile at boot, throttle and brake pressed
        - Compat patches
        """
        let zip = try ZipTestBuilder.build([
            ("info.json", Data(infoFixed.utf8)),
            ("FIRM.bin", firm),
            ("params.txt", Data(params.utf8))
        ])
        let report = FirmwareZipAnalyzer.analyze(fileName: "test.zip", data: zip)
        XCTAssertEqual(report.displayName, "G30 Test CFW")
        XCTAssertEqual(report.firmwareType, "DRV")
        XCTAssertEqual(report.models, ["max"])
        XCTAssertEqual(report.md5Matches, true)
        XCTAssertTrue(report.findings.contains(where: { $0.kind == .speedLimit }))
        XCTAssertTrue(report.findings.contains(where: { $0.kind == .unlockGesture }))
        XCTAssertTrue(report.findings.contains(where: { $0.kind == .customFirmware }))
        XCTAssertTrue(report.summary.lowercased().contains("g30") || report.summary.contains("DRV"))
    }

    func testRejectsNonZip() {
        let report = FirmwareZipAnalyzer.analyze(fileName: "x.bin", data: Data("not a zip".utf8))
        XCTAssertFalse(report.warnings.isEmpty)
        XCTAssertTrue(report.findings.isEmpty)
    }

    func testRepetitionGestureInBinary() throws {
        let firm = Data("config brake 6x unlock sequence enabled".utf8)
        let zip = try ZipTestBuilder.build([("FIRM.bin", firm)])
        let report = FirmwareZipAnalyzer.analyze(fileName: "plain.zip", data: zip)
        XCTAssertTrue(report.findings.contains(where: {
            $0.kind == .unlockGesture && $0.detail.lowercased().contains("brake")
        }))
    }
}

// MARK: - Helpers

private enum InsecureMD5 {
    static func hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum ZipTestBuilder {
    /// Baut eine STORE-only ZIP (Kompression 0) — ausreichend für Parser-Tests.
    static func build(_ files: [(String, Data)]) throws -> Data {
        var out = Data()
        var central = Data()
        var offsets: [UInt32] = []
        for (name, payload) in files {
            offsets.append(UInt32(out.count))
            let nameData = Data(name.utf8)
            var local = Data()
            local.append(contentsOf: u32(0x04034b50))
            local.append(contentsOf: u16(20)) // version
            local.append(contentsOf: u16(0)) // flags
            local.append(contentsOf: u16(0)) // store
            local.append(contentsOf: u16(0)) // time
            local.append(contentsOf: u16(0)) // date
            local.append(contentsOf: u32(crc32(payload)))
            local.append(contentsOf: u32(UInt32(payload.count)))
            local.append(contentsOf: u32(UInt32(payload.count)))
            local.append(contentsOf: u16(UInt16(nameData.count)))
            local.append(contentsOf: u16(0)) // extra
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
