import XCTest
@testable import ScooterCheck

final class PrivacyContentTests: XCTestCase {

    func testHubTopicsExcludeUnusedOptionalAreas() {
        let titles = PrivacyContent.Topic.allCases.map(\.title)
        XCTAssertFalse(titles.contains(where: { $0.localizedCaseInsensitiveContains("KI") }))
        XCTAssertFalse(titles.contains(where: { $0.localizedCaseInsensitiveContains("Analytics") }))
        XCTAssertFalse(titles.contains(where: { $0.localizedCaseInsensitiveContains("Einstellungen") && $0.contains("Datenschutz") }))
        XCTAssertTrue(titles.contains("Standort"))
        XCTAssertTrue(titles.contains("Bluetooth"))
        XCTAssertTrue(titles.contains("Kamera & Fotos"))
    }

    func testAtAGlanceStatesLocalStorage() {
        XCTAssertTrue(
            PrivacyContent.atAGlanceBody.localizedCaseInsensitiveContains("lokal")
        )
        XCTAssertTrue(
            PrivacyContent.atAGlanceBody.localizedCaseInsensitiveContains("kein Benutzerkonto")
                || PrivacyContent.atAGlanceBody.localizedCaseInsensitiveContains("kein App-eigenen Server")
        )
    }

    func testPolicyDoesNotInventControllerAddress() {
        let text = PrivacyContent.sections(for: .policy)
            .flatMap(\.paragraphs)
            .joined(separator: " ")
        XCTAssertTrue(text.contains("nicht hinterlegt") || text.contains("nicht angegeben"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("musterstraße"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("@example"))
    }

    func testExternalServicesMentionsGitHubOnlyAsCatalogHost() {
        let text = PrivacyContent.sections(for: .externalServices)
            .flatMap(\.paragraphs)
            .joined(separator: " ")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("github"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("stock-firmware") || text.localizedCaseInsensitiveContains("Katalog"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("Firebase"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("Sentry"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("OpenAI"))
    }

    func testEveryTopicHasSections() {
        for topic in PrivacyContent.Topic.allCases {
            XCTAssertFalse(
                PrivacyContent.sections(for: topic).isEmpty,
                "Topic \(topic.title) missing sections"
            )
        }
    }
}
