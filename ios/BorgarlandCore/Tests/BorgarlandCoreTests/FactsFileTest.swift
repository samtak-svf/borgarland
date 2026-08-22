import XCTest
import BorgarlandCore

/// Proves the app's category list really comes from the facts file: the
/// package reads the verbatim data/reykjavik-form.json and it must parse into
/// all twelve categories with the documented kind split (almenn-abending
/// general, the other eleven specific) and the documented description limit.
final class FactsFileTest: XCTestCase {

    func testAssetParsesWithAllTwelveCategories() throws {
        let facts = try Facts.parse(ContractSource.dataFile("reykjavik-form.json"))

        XCTAssertEqual(facts.categories.count, 12)
        XCTAssertEqual(facts.fields.description.maxLength, 2500)

        let general = facts.categories.first { $0.slug == "almenn-abending" }
        XCTAssertEqual(general?.type, "general")

        let specific = facts.categories.filter { $0.slug != "almenn-abending" }
        XCTAssertEqual(specific.count, 11)
        XCTAssertTrue(specific.allSatisfy { $0.type == "specific" })

        XCTAssertTrue(facts.categories.allSatisfy { !$0.slug.isEmpty && !$0.category.isEmpty })
    }
}
