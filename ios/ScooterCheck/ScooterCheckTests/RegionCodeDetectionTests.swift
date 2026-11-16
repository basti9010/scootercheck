import XCTest
@testable import ScooterCheck

final class RegionCodeDetectionTests: XCTestCase {

    func testMaxG3Prefixes() {
        XCTAssertEqual(TrackClassifier.resolveRegionProfile(for: "1CGBF2531C0230")?.shuStyleLabel, "Max G3 DE (22 km/h)")
        XCTAssertEqual(TrackClassifier.resolveRegionProfile(for: "1CGEF2531C0230")?.region, .eu)
        XCTAssertEqual(TrackClassifier.resolveRegionProfile(for: "1CGCF2551C3388")?.marketName, "US")
        XCTAssertEqual(TrackClassifier.resolveRegionProfile(for: "1CGDF2551C3388")?.marketName, "RU")
    }

    func testZT3Prefixes() {
        XCTAssertEqual(TrackClassifier.resolveRegionProfile(for: "1K1DA2616P1917")?.shuStyleLabel, "ZT3 Pro DE (22 km/h)")
        XCTAssertEqual(TrackClassifier.resolveRegionProfile(for: "1K1EA2616P1917")?.shuStyleLabel, "ZT3 Pro EU (25 km/h)")
    }

    func testF3US32AndCN() {
        XCTAssertEqual(TrackClassifier.resolveRegionProfile(for: "1EFGE2515C0440")?.shuStyleLabel, "F3 Pro US (32 km/h)")
        XCTAssertEqual(TrackClassifier.resolveRegionProfile(for: "1EFFE2515C0440")?.region, .cn)
        XCTAssertEqual(TrackClassifier.resolveRegionProfile(for: "1EFBE2515C0440")?.shuStyleLabel, "F3 US (32 km/h)")
    }

    func testPreferredSerialPrefersVehicleOverVcu() {
        let reading = IntegrityReading(
            serialDisplay: "1EFJE2515C0440",
            serialVcu: "1EFCE2515C0440"
        )
        XCTAssertEqual(TrackClassifier.preferredRegionSerial(from: reading), "1EFJE2515C0440")
        XCTAssertEqual(TrackClassifier.serialRegion(for: reading), .de)
    }
}
