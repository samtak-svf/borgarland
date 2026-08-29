import XCTest
import BorgarlandCore

/// The address the city answers to, and the rule for what counts as one (#163).
///
/// The table below is duplicated verbatim in the Android suite
/// (`ContactDetailsTest.kt`). That is deliberate: the rule is written twice
/// because the platforms share no code, and two spellings of one rule drift
/// the moment nothing compares them. Change one, change both.
final class ContactDetailsTest: XCTestCase {

    private func temporaryStore() throws -> (ContactDetails, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("contact-details.json")
        return (ContactDetails(url: url), url)
    }

    func testTheSharedTableOfWhatCountsAsAnAddress() {
        let accepted = [
            "nafn@example.is",
            "nafn.eftirnafn@example.co.uk",
            "nafn+merki@example.is",
            "gudrodur@gmail.com",
            // Trimmed, not rejected: a keyboard's trailing space is the most
            // common way a good address arrives looking wrong.
            "  nafn@example.is  ",
        ]
        for value in accepted {
            XCTAssertTrue(ContactDetails.isValid(value), "should accept '\(value)'")
        }

        let rejected = [
            "",
            "   ",
            "nafn",
            "nafn@",
            "@example.is",
            // No dot in the domain: deliverable on some intranet, a typo from
            // somebody filing an ábending.
            "nafn@example",
            "nafn@.is",
            "nafn@example..is",
            "nafn@example.",
            "nafn@@example.is",
            "nafn@example.is nafn2@example.is",
            "nafn @example.is",
        ]
        for value in rejected {
            XCTAssertFalse(ContactDetails.isValid(value), "should reject '\(value)'")
        }
    }

    func testNormaliseTrimsAndOtherwiseLeavesTheAddressAlone() {
        XCTAssertEqual(ContactDetails.normalise("  Nafn@Example.is \n"), "Nafn@Example.is")
    }

    func testAnAddressSurvivesTheRoundTrip() throws {
        let (store, _) = try temporaryStore()
        XCTAssertNil(store.read())
        XCTAssertTrue(store.write("nafn@example.is"))
        XCTAssertEqual(store.read(), "nafn@example.is")
    }

    func testTheLastAddressWrittenIsTheOneRead() throws {
        let (store, _) = try temporaryStore()
        store.write("gamalt@example.is")
        store.write("nytt@example.is")
        XCTAssertEqual(store.read(), "nytt@example.is")
    }

    func testAnEmptyOrUnreadableFileReadsAsNoAddressRatherThanAnEmptyOne() throws {
        let (store, url) = try temporaryStore()
        // Cleared on purpose.
        store.write("")
        XCTAssertNil(store.read())

        // Truncated by a process death mid-write, before the atomic write made
        // that unreachable. Still has to read as "ask for one" rather than
        // crash.
        try Data("{\"email\": \"nafn@exa".utf8).write(to: url)
        XCTAssertNil(store.read())
    }
}
