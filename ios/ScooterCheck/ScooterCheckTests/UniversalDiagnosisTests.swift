import XCTest
import CryptoKit
@testable import ScooterCheck

@MainActor
final class UniversalDiagnosisTests: XCTestCase {

    func testBundledProfilesDecode() {
        let profiles = loadProfiles()
        XCTAssertGreaterThanOrEqual(profiles.count, 5)
        let ninebot = profiles.first { $0.id == "ninebot-enc2-native" }
        XCTAssertEqual(ninebot?.verified, true)
        XCTAssertEqual(ninebot?.nativeStack, "ninebotEnc2")
        let xiaomi = profiles.first { $0.id == "xiaomi-plaintext-native" }
        XCTAssertEqual(xiaomi?.verified, true)
        let kukirin = profiles.first { $0.id == "kukirin-research" }
        XCTAssertEqual(kukirin?.verified, false)
        XCTAssertTrue(kukirin?.supportedReads.isEmpty == true)
    }

    func testCompatibilityNinebotFullNative() {
        let input = ProtocolMatchInput(
            name: "Ninebot",
            cryptoName: "Ninebot Max G2",
            modelLabel: "Max G2",
            serviceUUIDs: ["6E400001-0000-0000-006E-696E65626F74"],
            looksLikeScooter: true,
            suggestedProfileRaw: "maxG2D",
            isConnectable: true
        )
        let result = ProtocolCompatibilityEngine.evaluate(input: input, identity: nil, profiles: loadProfiles())
        XCTAssertEqual(result.supportLevel, .fullNative)
        XCTAssertEqual(result.profile?.nativeStack, "ninebotEnc2")
    }

    func testCompatibilityUnknownFirmwareStillNativeWhenUARTPresent() {
        let input = ProtocolMatchInput(
            name: "Ninebot",
            cryptoName: "Ninebot CustomFW",
            modelLabel: nil,
            serviceUUIDs: ["6E400001-0000-0000-006E-696E65626F74"],
            looksLikeScooter: true,
            suggestedProfileRaw: nil,
            isConnectable: true
        )
        let result = ProtocolCompatibilityEngine.evaluate(input: input, identity: nil, profiles: loadProfiles())
        XCTAssertEqual(result.supportLevel, .fullNative)
    }

    func testCompatibilityUnknownProprietaryResearchOnly() {
        let input = ProtocolMatchInput(
            name: "KuKirin G4",
            cryptoName: "KuKirin G4",
            modelLabel: nil,
            serviceUUIDs: ["FFF0"],
            looksLikeScooter: true,
            suggestedProfileRaw: nil,
            isConnectable: true
        )
        let result = ProtocolCompatibilityEngine.evaluate(input: input, identity: nil, profiles: loadProfiles())
        XCTAssertEqual(result.supportLevel, .researchHintOnly)
        XCTAssertEqual(result.profile?.verified, false)
        XCTAssertFalse(result.blockers.isEmpty)
    }

    func testCompatibilityManufacturerKnownModelUnknown() {
        let input = ProtocolMatchInput(
            name: "Navee",
            cryptoName: "Navee V40",
            modelLabel: nil,
            serviceUUIDs: [],
            looksLikeScooter: true,
            suggestedProfileRaw: nil,
            isConnectable: true
        )
        let result = ProtocolCompatibilityEngine.evaluate(input: input, identity: nil, profiles: loadProfiles())
        XCTAssertEqual(result.supportLevel, .researchHintOnly)
        XCTAssertEqual(result.profile?.manufacturer, "Navee")
    }

    func testCompatibilityGattDisReadonly() {
        let input = ProtocolMatchInput(
            name: "Unknown Scooter",
            cryptoName: "Mystery",
            modelLabel: nil,
            serviceUUIDs: ["180A"],
            looksLikeScooter: true,
            suggestedProfileRaw: nil,
            isConnectable: true
        )
        let result = ProtocolCompatibilityEngine.evaluate(input: input, identity: nil, profiles: loadProfiles())
        XCTAssertEqual(result.supportLevel, .gattReadonly)
        XCTAssertEqual(result.profile?.nativeStack, "gattDis")
    }

    func testOnlineIngestRejectsUnsignedWhenRequired() {
        let data = encodeRemoteProfile(id: "remote-test")
        let outcome = ScooterProtocolRegistry.shared.ingestOnlineProfiles(
            fileData: data,
            signatureHex: nil,
            requireSignature: true
        )
        guard case .failure(let msg) = outcome else {
            return XCTFail("Unsigned profiles must be rejected")
        }
        XCTAssertTrue(msg.lowercased().contains("signatur"))
    }

    func testOnlineIngestRejectsInvalidSignature() {
        let data = encodeRemoteProfile(id: "remote-bad-sig")
        let outcome = ScooterProtocolRegistry.shared.ingestOnlineProfiles(
            fileData: data,
            signatureHex: "deadbeef",
            requireSignature: true
        )
        guard case .failure = outcome else {
            return XCTFail("Invalid signature must reject")
        }
    }

    func testSignatureRoundTripAcceptsValid() {
        let data = encodeRemoteProfile(id: "remote-ok")
        let key = DiagnosticProfileSignature.bundledKeyMaterial()
        let mac = HMACSHA256Hex(data: data, key: key)
        ScooterProtocolRegistry.shared.clearOnlineCache()
        let outcome = ScooterProtocolRegistry.shared.ingestOnlineProfiles(
            fileData: data,
            signatureHex: mac,
            requireSignature: true
        )
        guard case .success(let n) = outcome else {
            return XCTFail("Valid signature should accept")
        }
        XCTAssertEqual(n, 1)
        ScooterProtocolRegistry.shared.clearOnlineCache()
    }

    func testPlanBlocksResearchOnly() {
        let assessment = UniversalScooterDetectionService.PassiveAssessment(
            deviceId: UUID(),
            manufacturer: "KuKirin",
            model: nil,
            signalLabel: "Stark",
            possibleScooter: true,
            compatibility: ProtocolCompatibilityResult(
                profile: nil,
                supportLevel: .researchHintOnly,
                matchedOn: ["KuKirin"],
                blockers: ["Kein freigegebenes Lesprotokoll"]
            ),
            approval: nil,
            stageNotes: []
        )
        let plan = ReadOnlyDiagnosticEngine.shared.plan(for: assessment)
        XCTAssertFalse(plan.canStart)
    }

    func testSnapshotMarksMissingValues() {
        let reading = IntegrityReading()
        let snap = ReadOnlyDiagnosticEngine.shared.snapshotFromIntegrityReading(reading, profile: nil)
        XCTAssertTrue(snap.values.contains { $0.value == "Nicht verfügbar" })
    }

    func testWeakOnlineHintNeverVerified() {
        let hint = loadProfiles().first { $0.id == "vmax-research" }
        XCTAssertEqual(hint?.verified, false)
        XCTAssertTrue(hint?.supportedReads.isEmpty == true)
    }

    // MARK: - Helpers

    private func loadProfiles() -> [ScooterDiagnosticProfile] {
        let path = "/workspace/ios/ScooterCheck/ScooterCheck/scooter_diagnostic_profiles.json"
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        let file = try! JSONDecoder().decode(ScooterDiagnosticProfileFile.self, from: data)
        return file.profiles
    }

    private func encodeRemoteProfile(id: String) -> Data {
        let file = ScooterDiagnosticProfileFile(
            version: 1,
            source: "test",
            updatedAt: "2026-01-01",
            note: nil,
            profiles: [
                ScooterDiagnosticProfile(
                    id: id,
                    manufacturer: "Test",
                    modelPatterns: [],
                    serviceUUIDs: ["180A"],
                    protocolVersion: "1",
                    supportedReads: [],
                    referenceDataVersion: nil,
                    approvalDataVersion: nil,
                    source: "unit",
                    sourceUrl: nil,
                    verified: true,
                    minAppBuild: nil,
                    nativeStack: "gattDis",
                    updatedAt: "2026-01-01",
                    notes: nil
                )
            ]
        )
        return try! JSONEncoder().encode(file)
    }
}

private func HMACSHA256Hex(data: Data, key: Data) -> String {
    let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
    return Data(mac).map { String(format: "%02x", $0) }.joined()
}
