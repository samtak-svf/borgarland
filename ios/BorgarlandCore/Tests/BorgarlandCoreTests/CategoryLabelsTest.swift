import Foundation
import XCTest
@testable import BorgarlandCore

/// #40, and the requirement underneath it.
///
/// The reported defect was cosmetic: the picker showed "Almenn ábending" as a
/// category and "Almenn ábending" as its kind. The real defect was that
/// AGENTS.md has required this category to be reworded since the project
/// started — "never as a suggestion box" — and both apps rendered the city's
/// own string verbatim. The doc described a rewording that was never built.
final class CategoryLabelsTest: XCTestCase {

    private func labelsFile() throws -> CategoryLabelsFile {
        try CategoryLabels.parse(try ContractSource.dataFile("category-labels.json"))
    }

    private func facts() throws -> FactsFile {
        try Facts.parse(try ContractSource.dataFile("reykjavik-form.json"))
    }

    func testTheSuggestionBoxIsRenamed() throws {
        let file = try labelsFile()
        let general = try XCTUnwrap(
            try facts().categories.first { $0.slug == "almenn-abending" }
        )

        let shown = CategoryLabels.display(general, in: file)
        XCTAssertNotEqual(
            shown, general.category,
            "almenn-abending must not render the city's own name; AGENTS.md forbids the suggestion box"
        )
        XCTAssertFalse(
            shown.lowercased().contains("ábending"),
            "the point is not to rename it to another kind of ábending"
        )
    }

    func testEveryOtherCategoryKeepsTheCitysName() throws {
        // A picker that renames everything is a picker nobody can match against
        // the city's own form. The override is the exception.
        let file = try labelsFile()
        for category in try facts().categories where category.slug != "almenn-abending" {
            XCTAssertEqual(
                CategoryLabels.display(category, in: file), category.category,
                "\(category.slug) should render the city's own name"
            )
        }
    }

    func testAnOverrideNeverCollidesWithItsOwnHelpLine() throws {
        // The literal shape of #40: the label and the line under it were the
        // same string.
        let file = try labelsFile()
        for (slug, label) in file.labels {
            if let help = label.help {
                XCTAssertNotEqual(label.label, help, "\(slug) label and help are the same string")
            }
        }
    }

    func testEveryOverriddenSlugIsARealCategory() throws {
        // An override for a slug the city no longer has is dead vocabulary that
        // nothing would report.
        let slugs = Set(try facts().categories.map(\.slug))
        for slug in try labelsFile().labels.keys {
            XCTAssertTrue(slugs.contains(slug), "\(slug) is not a category in the facts file")
        }
    }

    func testAMissingLabelsFileFallsBackToTheCity() throws {
        // Degraded, not dead: the facts file is what stops the app, not this.
        let general = try XCTUnwrap(try facts().categories.first { $0.slug == "almenn-abending" })
        XCTAssertEqual(CategoryLabels.display(general, in: nil), general.category)
        XCTAssertNil(CategoryLabels.help(general, in: nil))
    }
}
