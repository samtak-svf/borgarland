import Foundation
import XCTest
import BorgarlandCore

/// Decision 0002 as a test rather than a promise. The package speaks our
/// vocabulary only: no city hostname, path or field name exists in the
/// library source, so there is nothing for a wrong turn to reach. The rule in
/// AGENTS.md says the adapter is the only place allowed to know those names,
/// and in this architecture the adapter lives in the relay.
///
/// The scan covers two scopes at two strictnesses. The library
/// (BorgarlandCore/Sources) renders nothing and reaches nothing, so it may not
/// hold a city hostname, path, field name or display name at all. The SwiftUI
/// shell (ios/Sources) is checked for the hostname and the paths only,
/// matching the Kotlin app-level guard exactly.
///
/// The shell is deliberately NOT scanned for field names or display names, and
/// the second exclusion was learned rather than assumed. A screen's job is to
/// render labels, and the label the picker shows for the city's `general` kind
/// is the string "Almenn ábending", which is also, separately, the display
/// name of one of the twelve categories. Scanning the shell for display names
/// fails that honest line and teaches nobody anything. The property the guard
/// actually protects, that a category's own label is read from the facts file
/// at runtime, is not something a substring scan can express.
///
/// The test target is the guard itself and deliberately holds the forbidden
/// strings, exactly as the Kotlin test lives beside the code it scans.
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

    /// The SwiftUI shell, at the Android app's scope: hostname and paths
    /// only, no word-level check. The shell is where a screen's internal state
    /// lives, and the Kotlin app it ports names a coordinate's parts the same
    /// way inside its own view model. Applying the package's stricter word
    /// list to it would fail honest code and teach nobody anything; what the
    /// shell must never hold is a route to the city, and that is what this
    /// checks.
    ///
    /// It is checked here, in a package test, rather than in a test target of
    /// the app: this suite runs on a macOS host with no simulator and no Xcode
    /// project, so the guard costs seconds and holds even when the app target
    /// cannot be built.
    func testNoCityEndpointAppearsInTheShellSource() throws {
        let offenders = try appSourceFiles().flatMap { file -> [String] in
            let code = try String(contentsOf: file, encoding: .utf8)
            let stripped = try stripComments(code)
            return forbiddenPaths
                .filter { stripped.contains($0) }
                .map { "\(file.lastPathComponent): \($0)" }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "the app must not know any city endpoint; found: \(offenders)"
        )
    }

    private func sourceFiles() throws -> [URL] {
        try swiftFiles(under: ContractSource.sourcesDirectory)
    }

    /// Recursive, unlike the package scan: the shell is free to grow
    /// subdirectories, and a guard that stops at the top level is a guard that
    /// silently stops guarding the moment someone makes a folder.
    private func appSourceFiles() throws -> [URL] {
        try swiftFiles(under: ContractSource.appSourcesDirectory)
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.path),
            "expected \(directory.path) to exist"
        )
        guard let walker = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return walker
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }
}
