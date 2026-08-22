import XCTest
import BorgarlandCore

/// The one rule this project enforces that the city does not: a usable
/// coordinate is present, finite and inside WGS84 bounds. A non-finite value
/// can reach this guard via EXIF rationals with a zero denominator, so it is
/// rejected rather than assumed impossible.
final class CoordinatesTest: XCTestCase {

    func testRejectsNonFinite() {
        XCTAssertFalse(Coordinates.isUsable(latitude: .nan, longitude: 0.0))
        XCTAssertFalse(Coordinates.isUsable(latitude: 0.0, longitude: .infinity))
        XCTAssertFalse(Coordinates.isUsable(latitude: -.infinity, longitude: -22.0))
    }

    func testRejectsOutOfWgs84Range() {
        XCTAssertFalse(Coordinates.isUsable(latitude: 91.0, longitude: 0.0))
        XCTAssertFalse(Coordinates.isUsable(latitude: -91.0, longitude: 0.0))
        XCTAssertFalse(Coordinates.isUsable(latitude: 0.0, longitude: 181.0))
        XCTAssertFalse(Coordinates.isUsable(latitude: 0.0, longitude: -181.0))
    }

    func testAcceptsReykjavikCoordinate() {
        XCTAssertTrue(Coordinates.isUsable(latitude: 64.1467, longitude: -21.9429))
        // Finite and in range; the map-bounds warning handles the rest.
        XCTAssertTrue(Coordinates.isUsable(latitude: 0.0, longitude: 0.0))
    }

    func testDecimalTextGate() {
        // The wire format is a dot separator. Comma decimals and empty input
        // must read as nil rather than reach the wire mis-formatted.
        XCTAssertEqual(Coordinates.decimal(from: "64.14658919"), 64.14658919)
        XCTAssertNil(Coordinates.decimal(from: "64,14658919"))
        XCTAssertNil(Coordinates.decimal(from: ""))
        XCTAssertNil(Coordinates.decimal(from: "  "))
    }

    func testWireFormattingUsesDotSeparator() {
        // Shortest round-trip, dot separator, no exponent for these
        // magnitudes — the same string the Kotlin's toString() produces.
        XCTAssertEqual(String(64.14658919), "64.14658919")
        XCTAssertEqual(String(-21.93279823), "-21.93279823")
    }
}
