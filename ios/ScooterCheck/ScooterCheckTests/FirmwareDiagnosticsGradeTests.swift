import XCTest
@testable import ScooterCheck

final class FirmwareDiagnosticsGradeTests: XCTestCase {

    // MARK: - Parse

    func testParseConfiguredAvailableVerifiedFailedUnknown() {
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse("CONFIGURED"), .configured)
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse("available"), .available)
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse("VERIFIED"), .verified)
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse("FAILED"), .failed)
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse("UNKNOWN"), .unknown)
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse(nil), .unknown)
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse("nonsense"), .unknown)
    }

    func testParseEndToEndAndNotConfiguredAliases() {
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse("END_TO_END_VERIFIED"), .endToEndVerified)
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse("E2E_VERIFIED"), .endToEndVerified)
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse("NOT_CONFIGURED"), .notConfigured)
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse("ROUTE_MISSING"), .routeMissing)
        XCTAssertEqual(FirmwareDiagnosticsGrade.parse("404"), .routeMissing)
    }

    // MARK: - Tokens / labels

    func testGradeTokensAreUppercaseWireValues() {
        XCTAssertEqual(FirmwareDiagnosticsGrade.configured.token, "CONFIGURED")
        XCTAssertEqual(FirmwareDiagnosticsGrade.available.token, "AVAILABLE")
        XCTAssertEqual(FirmwareDiagnosticsGrade.verified.token, "VERIFIED")
        XCTAssertEqual(FirmwareDiagnosticsGrade.endToEndVerified.token, "END_TO_END_VERIFIED")
        XCTAssertEqual(FirmwareDiagnosticsGrade.failed.token, "FAILED")
        XCTAssertEqual(FirmwareDiagnosticsGrade.unknown.token, "UNKNOWN")
    }

    func testGradeLabelsAreNonEmptyGerman() {
        for grade in FirmwareDiagnosticsGrade.allCases {
            XCTAssertFalse(grade.labelDE.isEmpty, "\(grade) missing label")
        }
    }

    // MARK: - /health → grades (never VERIFIED from flags alone)

    func testWorkerHealthMapsConfiguredFlagsNotVerified() {
        let health = makeHealth(
            ok: true,
            service: "scootercheck-fw",
            decryptConfigured: true,
            ghidraConfigured: true,
            ghidraEnabled: true
        )
        let status = FirmwareDiagnosticsStatusMapper.fromWorkerHealth(health)
        let tea = status.grade(for: .tea)
        let ghidra = status.grade(for: .ghidra)
        XCTAssertEqual(tea, .configured, "decryptConfigured alone must not be VERIFIED")
        XCTAssertEqual(ghidra, .configured, "ghidraConfigured alone must not be VERIFIED")
        XCTAssertNotEqual(tea, .verified)
        XCTAssertNotEqual(tea, .endToEndVerified)
        XCTAssertNotEqual(ghidra, .verified)
        XCTAssertNotEqual(ghidra, .endToEndVerified)
        XCTAssertEqual(status.grade(for: .server), .available)
        XCTAssertEqual(status.grade(for: .worker), .available)
    }

    func testWorkerHealthFailedWhenOkFalse() {
        let health = makeHealth(ok: false, service: "down")
        let status = FirmwareDiagnosticsStatusMapper.fromWorkerHealth(health)
        XCTAssertEqual(status.grade(for: .server), .failed)
        XCTAssertEqual(status.grade(for: .worker), .failed)
        XCTAssertEqual(status.overallGrade, .failed)
    }

    func testWorkerHealthTeaNotConfigured() {
        let health = makeHealth(
            ok: true,
            decryptConfigured: false,
            ghidraConfigured: false,
            ghidraEnabled: false
        )
        let status = FirmwareDiagnosticsStatusMapper.fromWorkerHealth(health)
        XCTAssertEqual(status.grade(for: .tea), .notConfigured)
        XCTAssertEqual(status.grade(for: .ghidra), .notConfigured)
    }

    func testNormalizedComponentsAlwaysFourRows() {
        let partial = FirmwareDiagnosticsStatus(
            components: [
                .init(component: .tea, grade: .configured)
            ]
        )
        let rows = FirmwareDiagnosticsStatusMapper.normalizedComponents(from: partial)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.component), FirmwareDiagnosticsComponent.allCases)
        XCTAssertEqual(rows.first(where: { $0.component == .tea })?.grade, .configured)
        XCTAssertEqual(rows.first(where: { $0.component == .server })?.grade, .unknown)
    }

    // MARK: - Admin gate on client

    func testDiagnosticsAdminRequiresDedicatedAdminToken() {
        let sharedOnly = FirmwareServerAnalysisClient(
            baseURL: URL(string: "https://example.test"),
            apiToken: "shared",
            adminAPIToken: nil,
            bearerToken: nil,
            clientId: "test"
        )
        XCTAssertFalse(sharedOnly.isDiagnosticsAdmin)
        XCTAssertTrue(sharedOnly.hasAPIToken)

        let admin = FirmwareServerAnalysisClient(
            baseURL: URL(string: "https://example.test"),
            apiToken: "shared",
            adminAPIToken: "admin-secret",
            bearerToken: nil,
            clientId: "test"
        )
        XCTAssertTrue(admin.isDiagnosticsAdmin)
    }

    func testGradeColorMappingCoversAllCases() {
        // Ensures UI badge colors resolve for every grade (no accidental missing switch).
        for grade in FirmwareDiagnosticsGrade.allCases {
            _ = grade.color
            XCTAssertFalse(grade.token.isEmpty)
        }
        XCTAssertEqual(FirmwareDiagnosticsGrade.failed.token, "FAILED")
        XCTAssertEqual(FirmwareDiagnosticsGrade.verified.token, "VERIFIED")
    }

    // MARK: - Helpers

    private func makeHealth(
        ok: Bool,
        service: String? = nil,
        decryptConfigured: Bool? = nil,
        ghidraConfigured: Bool? = nil,
        ghidraEnabled: Bool? = nil
    ) -> FirmwareWorkerHealth {
        FirmwareWorkerHealth(
            ok: ok,
            service: service,
            decryptConfigured: decryptConfigured,
            ghidraConfigured: ghidraConfigured,
            ghidraEnabled: ghidraEnabled,
            llmConfigured: nil,
            llmKeyStatus: nil,
            llmProvider: nil,
            llmModel: nil,
            jwtConfigured: nil,
            retentionDays: nil,
            maxStoredJobs: nil,
            stockFwDir: nil,
            stockRefCount: nil,
            r2Configured: nil,
            capstoneConfigured: nil,
            yaraConfigured: nil,
            unicornConfigured: nil,
            angrLiteConfigured: nil,
            angrEngineConfigured: nil,
            angrTimeoutSec: nil,
            angrMemMb: nil,
            angrCfgDepth: nil,
            angrSymbolic: nil
        )
    }
}
