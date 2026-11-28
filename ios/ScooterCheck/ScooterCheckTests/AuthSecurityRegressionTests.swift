import XCTest
@testable import ScooterCheck

/// Guards against re-introducing the PR #114 demo bypass on the recovery line.
final class AuthSecurityRegressionTests: XCTestCase {
    private var authDirectoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ScooterCheckTests
            .deletingLastPathComponent() // ScooterCheck (project)
            .appendingPathComponent("ScooterCheck", isDirectory: true)
            .appendingPathComponent("Auth", isDirectory: true)
    }

    private var appRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ScooterCheck", isDirectory: true)
    }

    func testDemoAuthBootstrapSwiftFileAbsent() {
        let demo = authDirectoryURL.appendingPathComponent("DemoAuthBootstrap.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: demo.path),
            "DemoAuthBootstrap.swift must not exist on the P0 recovery branch (PR #114 demo bypass)."
        )
    }

    func testAuthGateEnabledNeverFalseInFeatureFlagsSource() throws {
        let flags = appRootURL.appendingPathComponent("AppFeatureFlags.swift")
        let src = try String(contentsOf: flags, encoding: .utf8)
        // Flag may be absent (gate always on) or true — never shipped as false.
        XCTAssertFalse(
            src.contains("authGateEnabled = false"),
            "AppFeatureFlags.authGateEnabled must not be false on a productive recovery build."
        )
        if src.contains("authGateEnabled") {
            XCTAssertTrue(
                src.contains("authGateEnabled = true"),
                "If authGateEnabled exists it must be true."
            )
        }
    }

    func testScooterCheckAppAlwaysUsesAuthGateView() throws {
        let app = appRootURL.appendingPathComponent("ScooterCheckApp.swift")
        let src = try String(contentsOf: app, encoding: .utf8)
        XCTAssertTrue(src.contains("AuthGateView(auth:"), "App root must be AuthGateView.")
        XCTAssertFalse(src.contains("DemoAuthBootstrap"), "App must not call DemoAuthBootstrap.")
        // Must not conditionally skip the gate the way PR #114 did.
        XCTAssertFalse(
            src.contains("authGateEnabled"),
            "ScooterCheckApp must not branch on authGateEnabled."
        )
    }

    func testNoHardcodedDemoBootstrapSymbolInAuthSources() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: authDirectoryURL,
            includingPropertiesForKeys: nil
        )
        for file in files where file.pathExtension == "swift" {
            let src = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                src.contains("enum DemoAuthBootstrap") || src.contains("struct DemoAuthBootstrap"),
                "Unexpected DemoAuthBootstrap type in \(file.lastPathComponent)"
            )
        }
    }

    /// Legacy UserDefaults key must stay stable for Keychain migration (Agent A).
    func testLegacyTokenKeyStableForMigration() throws {
        let keychainStore = authDirectoryURL.appendingPathComponent("AuthTokenKeychainStore.swift")
        let src = try String(contentsOf: keychainStore, encoding: .utf8)
        XCTAssertTrue(
            src.contains("scootercheck.auth.token"),
            "AuthTokenKeychainStore must keep the legacy token key string for migration compatibility."
        )
        XCTAssertEqual(
            AuthTokenKeychainStore.legacyUserDefaultsKey,
            "scootercheck.auth.token"
        )
    }

    func testNoDemoAuthBootstrapPasswordsInTree() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: authDirectoryURL,
            includingPropertiesForKeys: nil
        )
        for file in files where file.pathExtension == "swift" {
            let src = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                src.contains("DemoAuthBootstrap"),
                "\(file.lastPathComponent) must not reference DemoAuthBootstrap"
            )
        }
    }
}
