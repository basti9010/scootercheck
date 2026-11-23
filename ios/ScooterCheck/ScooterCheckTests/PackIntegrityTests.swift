import XCTest
@testable import ScooterCheck

final class PackIntegrityTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackIntegrityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try super.tearDownWithError()
    }

    func testSha256HexIsStable() {
        let data = Data("scootercheck-integrity".utf8)
        let a = PackIntegrity.sha256Hex(of: data)
        let b = PackIntegrity.sha256Hex(of: Data("scootercheck-integrity".utf8))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
        XCTAssertEqual(a, a.lowercased())
        XCTAssertNotEqual(a, PackIntegrity.sha256Hex(of: Data("other".utf8)))
    }

    func testSha256HexMatchesKnownVector() {
        // SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
        let digest = PackIntegrity.sha256Hex(of: Data("abc".utf8))
        XCTAssertEqual(digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testBuildAndVerifyRoundTrip() throws {
        let protocolNumber = "SC-TEST-001"
        try writeArtifact("session.json", contents: Data(#"{"ok":true}"#.utf8))
        try writeArtifact("\(protocolNumber).pdf", contents: Data("%PDF-bericht".utf8))
        try writeArtifact(
            "ScooterCheck_\(protocolNumber)_Bericht.pdf",
            contents: Data("%PDF-bericht".utf8)
        )
        try writeArtifact("\(protocolNumber).json", contents: Data(#"{"data":1}"#.utf8))
        try writeArtifact(
            "ScooterCheck_\(protocolNumber)_Daten.json",
            contents: Data(#"{"data":1}"#.utf8)
        )
        try writeArtifact("\(protocolNumber)_raw.pdf", contents: Data("%PDF-raw".utf8))
        try writeArtifact(
            "ScooterCheck_\(protocolNumber)_Rohdaten.pdf",
            contents: Data("%PDF-raw".utf8)
        )

        let photos = tempDir.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data("jpeg-bytes".utf8).write(to: photos.appendingPathComponent("photo.jpg"))

        // Manifest itself must never enter the hash set.
        try Data("{}".utf8).write(
            to: tempDir.appendingPathComponent(PackIntegrityManifest.fileName)
        )

        let manifest = try PackIntegrity.buildManifest(
            directory: tempDir,
            protocolNumber: protocolNumber,
            sealed: true,
            appVersion: "test-1.0"
        )
        XCTAssertTrue(manifest.sealed)
        XCTAssertEqual(manifest.manifestAlgorithm, "SHA-256")
        XCTAssertEqual(manifest.protocolNumber, protocolNumber)
        XCTAssertFalse(manifest.files.contains { $0.relativePath == PackIntegrityManifest.fileName })
        XCTAssertTrue(manifest.files.contains { $0.relativePath == "session.json" })
        XCTAssertTrue(manifest.files.contains { $0.relativePath == "photos/photo.jpg" })
        XCTAssertEqual(manifest.files.map(\.relativePath), manifest.files.map(\.relativePath).sorted())

        try PackIntegrity.writeManifest(manifest, to: tempDir)

        let result = try PackIntegrity.verify(directory: tempDir)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.mismatches.isEmpty)
        XCTAssertTrue(result.missing.isEmpty)
    }

    func testVerifyDetectsMismatch() throws {
        let protocolNumber = "SC-MISMATCH"
        try writeArtifact("session.json", contents: Data("original".utf8))
        try writeArtifact("\(protocolNumber).pdf", contents: Data("%PDF".utf8))

        let manifest = try PackIntegrity.buildManifest(
            directory: tempDir,
            protocolNumber: protocolNumber,
            sealed: true,
            appVersion: nil
        )
        try PackIntegrity.writeManifest(manifest, to: tempDir)

        // Tamper with session after seal.
        try writeArtifact("session.json", contents: Data("tampered".utf8))

        let result = try PackIntegrity.verify(directory: tempDir)
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.mismatches, ["session.json"])
        XCTAssertTrue(result.missing.isEmpty)
    }

    func testVerifyDetectsMissingFile() throws {
        let protocolNumber = "SC-MISSING"
        try writeArtifact("session.json", contents: Data("keep".utf8))
        try writeArtifact("\(protocolNumber).json", contents: Data("{}".utf8))

        let manifest = try PackIntegrity.buildManifest(
            directory: tempDir,
            protocolNumber: protocolNumber,
            sealed: true
        )
        try PackIntegrity.writeManifest(manifest, to: tempDir)

        try FileManager.default.removeItem(
            at: tempDir.appendingPathComponent("\(protocolNumber).json")
        )

        let result = try PackIntegrity.verify(directory: tempDir)
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.missing, ["\(protocolNumber).json"])
        XCTAssertTrue(result.mismatches.isEmpty)
    }

    func testManifestWriteIsAtomicSortedKeys() throws {
        try writeArtifact("session.json", contents: Data("x".utf8))
        let manifest = try PackIntegrity.buildManifest(
            directory: tempDir,
            protocolNumber: "SC-JSON",
            sealed: true,
            appVersion: "1.0.0"
        )
        try PackIntegrity.writeManifest(manifest, to: tempDir)

        let raw = try Data(
            contentsOf: tempDir.appendingPathComponent(PackIntegrityManifest.fileName)
        )
        let text = String(data: raw, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"manifestAlgorithm\""))
        XCTAssertTrue(text.contains("SHA-256"))
        // sortedKeys: appVersion before createdAt / files / manifestAlgorithm / …
        let appIdx = text.range(of: "\"appVersion\"")?.lowerBound
        let filesIdx = text.range(of: "\"files\"")?.lowerBound
        XCTAssertNotNil(appIdx)
        XCTAssertNotNil(filesIdx)
        if let appIdx, let filesIdx {
            XCTAssertLessThan(appIdx, filesIdx)
        }
    }

    // MARK: - Helpers

    private func writeArtifact(_ relativePath: String, contents: Data) throws {
        let url = tempDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, options: .atomic)
    }
}
