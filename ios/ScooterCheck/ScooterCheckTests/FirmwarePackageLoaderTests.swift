import XCTest
@testable import ScooterCheck

final class FirmwarePackageLoaderTests: XCTestCase {

    func testLoadEncryptedBareBinary() {
        let payload = Data((0..<64).map { UInt8($0) })
        let pkg = FirmwarePackageLoader.load(fileName: "FIRM.bin.enc", data: payload)
        XCTAssertEqual(pkg.containerKind, .bareEncryptedBinary)
        XCTAssertEqual(pkg.archiveByteCount, 64)
        XCTAssertEqual(pkg.files.count, 1)
        XCTAssertEqual(pkg.files[0].data, payload)
    }

    func testLoadZipWithInfoJsonAndEnc() throws {
        let info = Data(#"{"schemaVersion":1,"firmware":{"model":"zt3","encryption":"encrypted","compatible":["zt3_VCU_AT32"]}}"#.utf8)
        let enc = Data(repeating: 0xAB, count: 32)
        let zip = try makeZip(entries: [
            ("info.json", info),
            ("FIRM.bin.enc", enc)
        ])
        let pkg = FirmwarePackageLoader.load(fileName: "sample.zip", data: zip)
        XCTAssertEqual(pkg.containerKind, .zipV3)
        XCTAssertTrue(pkg.files.contains { FirmwarePackageLoader.baseName($0.path).lowercased() == "info.json" })
        XCTAssertTrue(pkg.files.contains { FirmwarePackageLoader.baseName($0.path).lowercased().hasSuffix(".enc") })
        XCTAssertEqual(pkg.meta.declaredEncrypted, true)
        XCTAssertEqual(pkg.meta.schemaVersion, 1)
    }

    func testBinaryStaticAnalyzerFilenamePanicIsUnverified() {
        let crypto = FirmwareCryptoAssessment(
            status: .confirmedByMetadata,
            detectedFormat: "enc",
            decryptionAvailable: false,
            decryptionNote: "offline",
            evidence: []
        )
        let meta = FirmwarePackageMeta(
            schemaVersion: 1,
            displayName: "VCU AT32",
            models: ["zt3"],
            type: "VCU",
            compatible: ["zt3_VCU_AT32"],
            declaredMd5: nil,
            declaredEncrypted: true,
            rawInfoJSON: nil
        )
        let (analysis, evidence) = FirmwareBinaryStaticAnalyzer.analyze(
            path: "FIRM.bin.enc",
            archiveFileName: "ZT3_________panicsystem_9646.zip",
            data: Data(repeating: 1, count: 16),
            crypto: crypto,
            meta: meta,
            paramsText: nil
        )
        XCTAssertFalse(analysis.performed)
        XCTAssertTrue(evidence.contains { $0.category == .filenameHint && $0.confirmed == false })
        XCTAssertTrue(evidence.contains { $0.category == .architecture && $0.confirmed == true })
    }

    func testServerClientNotConfiguredWithoutURL() {
        let client = FirmwareServerAnalysisClient(baseURL: nil, apiToken: nil, bearerToken: nil, clientId: "test")
        XCTAssertFalse(client.isConfigured)
    }

    // MARK: - Minimal ZIP (store)

    private func makeZip(entries: [(String, Data)]) throws -> Data {
        var out = Data()
        var central = Data()
        var offsets: [UInt32] = []
        for (name, payload) in entries {
            offsets.append(UInt32(out.count))
            let nameData = Data(name.utf8)
            out.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])
            out.append(contentsOf: [0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
            let crc = crc32(payload)
            appendU32(&out, crc)
            appendU32(&out, UInt32(payload.count))
            appendU32(&out, UInt32(payload.count))
            appendU16(&out, UInt16(nameData.count))
            appendU16(&out, 0)
            out.append(nameData)
            out.append(payload)

            central.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
            central.append(contentsOf: [0x14, 0x00, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
            appendU32(&central, crc)
            appendU32(&central, UInt32(payload.count))
            appendU32(&central, UInt32(payload.count))
            appendU16(&central, UInt16(nameData.count))
            central.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
            appendU32(&central, offsets.last!)
            central.append(nameData)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(contentsOf: [0x50, 0x4b, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00])
        appendU16(&out, UInt16(entries.count))
        appendU16(&out, UInt16(entries.count))
        appendU32(&out, UInt32(central.count))
        appendU32(&out, centralOffset)
        appendU16(&out, 0)
        return out
    }

    private func appendU16(_ data: inout Data, _ v: UInt16) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private func appendU32(_ data: inout Data, _ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xedb8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xffff_ffff
    }
}
