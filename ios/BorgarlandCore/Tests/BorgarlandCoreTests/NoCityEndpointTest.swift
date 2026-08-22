import Foundation
import XCTest
import BorgarlandCore

/// Decision 0002 as a test rather than a promise. The package speaks our
/// vocabulary only: no city hostname, path or field name exists in the
/// library source, so there is nothing for a wrong turn to reach. The rule in
/// AGENTS.md says the adapter is the only place allowed to know those names,
/// and in this architecture the adapter lives in the relay.
///
/// The scan covers the library (Sources/) only. The test target is the guard
/// itself and deliberately holds the forbidden strings, exactly as the Kotlin
/// test lives beside the code it scans.
final class NoCityEndpointTest: XCTestCase {

    private let forbiddenPaths = [
        "reykjavik.is",
        "senda-abendingu",
        "abendingar/addressInfo",
        "location/addresses",
    ]

    /// The short city field names, as standalone words. Our wire names are
    /// the full words (latitude, longitude, description, photo), so a
    /// standalone short form in the library is the bug. The city's "type"
    /// key is deliberately absent from this list: the facts model mirrors it
    /// as a property name, exactly as the Kotlin reference does, and the
    /// wire-level prohibition on it is enforced by the body test.
    private let forbiddenWords = ["lat", "lng", "summary", "files"]

    /// Comments are stripped before scanning, deliberately. A guard that
    /// matches a substring rather than a structure fails the very comment
    /// that explains it, and then the rule cannot be documented in the file
    /// it governs. This test is about what the code can reach, not about
    /// which words appear near it.
    private func stripComments(_ text: String) throws -> String {
        let block = try NSRegularExpression(pattern: "/\\*.*?\\*/", options: [.dotMatchesLineSeparators])
        let withoutBlocks = block.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: ""
        )
        return withoutBlocks
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    func testNoCityEndpointAppearsInTheLibrarySource() throws {
        let offenders = try sourceFiles().flatMap { file -> [String] in
            let code = try String(contentsOf: file, encoding: .utf8)
            let stripped = try stripComments(code)
            var found: [String] = []
            for path in forbiddenPaths where stripped.contains(path) {
                found.append("\(file.lastPathComponent): \(path)")
            }
            for word in forbiddenWords {
                let words = stripped.split { !$0.isLetter && !$0.isNumber }
                if words.contains(Substring(word)) {
                    found.append("\(file.lastPathComponent): \(word)")
                }
            }
            return found
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "the library must not know any city endpoint or field name; found: \(offenders)"
        )
    }

    func testNoCategoryDisplayNameAppearsInTheLibrarySource() throws {
        // Display names come from the facts file at runtime; hardcoding one
        // in the library is the drift this scan exists to catch. The list is
        // read from the facts file so the guard stays current as the city
        // edits its categories.
        let facts = try Facts.parse(ContractSource.dataFile("reykjavik-form.json"))
        let displayNames = facts.categories.map(\.category)

        let offenders = try sourceFiles().flatMap { file -> [String] in
            let code = try String(contentsOf: file, encoding: .utf8)
            let stripped = try stripComments(code)
            return displayNames
                .filter { stripped.contains($0) }
                .map { "\(file.lastPathComponent): \($0)" }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "category display names belong to the facts file; found: \(offenders)"
        )
    }

    private func sourceFiles() throws -> [URL] {
        let directory = ContractSource.sourcesDirectory
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.path),
            "expected \(directory.path) to exist"
        )
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
    }
}
