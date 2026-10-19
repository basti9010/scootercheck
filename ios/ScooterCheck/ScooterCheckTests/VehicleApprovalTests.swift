import XCTest
@testable import ScooterCheck

final class VehicleApprovalTests: XCTestCase {

    func testKuKirinG4ConcreteNoGermanApprovalDocumented() {
        let match = VehicleApprovalCatalog.shared.match(
            displayName: "KuKirin G4",
            bleName: "KuKirin G4",
            modelLabel: "KuKirin G4",
            manufacturerHint: "KuKirin"
        )
        XCTAssertNotNil(match)
        XCTAssertTrue(match?.concreteVariant == true)
        XCTAssertEqual(match?.entry.germanApproval, .noGermanApprovalDocumented)
        XCTAssertTrue(match?.entry.germanApproval.warrantsApprovalAlert == true)
    }

    func testNinebotMaxG2NotConfusedWithKuKirinG2() {
        let match = VehicleApprovalCatalog.shared.match(
            displayName: "Ninebot Max G2",
            bleName: "Max G2",
            modelLabel: "Ninebot Max G2",
            manufacturerHint: "Segway-Ninebot"
        )
        // Darf nicht als KuKirin G2 ohne Brand-Marker landen
        XCTAssertNotEqual(match?.entry.manufacturer, "KuKirin")
    }

    func testKuKirinBrandOnlyIsModelUnidentified() {
        let match = VehicleApprovalCatalog.shared.match(
            displayName: "KuKirin",
            bleName: "KUKIRIN",
            modelLabel: nil,
            manufacturerHint: "KuKirin"
        )
        XCTAssertEqual(match?.entry.germanApproval, .modelUnidentified)
        XCTAssertFalse(match?.concreteVariant == true)
    }

    func testExtendedHintRecognizesKuKirinG2Master() {
        let r = ExtendedScooterModelHint.recognize(bleName: "KuKirin G2 Master")
        XCTAssertEqual(r?.title, "KuKirin G2 Master")
        XCTAssertTrue(r?.isConcrete == true)
    }

    func testExtendedHintIgnoresNinebotG2() {
        let r = ExtendedScooterModelHint.recognize(bleName: "Ninebot Max G2")
        XCTAssertNil(r)
    }

    func testNoInventedAbeNumbersInCatalog() {
        for entry in VehicleApprovalCatalog.shared.entries {
            if let abe = entry.abeNumber {
                XCTAssertFalse(abe.isEmpty)
                // Placeholder/fake patterns
                XCTAssertFalse(abe.uppercased().contains("TODO"))
                XCTAssertFalse(abe.uppercased().contains("FAKE"))
            }
        }
    }
}
