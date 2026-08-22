import Foundation

/// Resolves the repo-root data/ directory the tests read. The Android tests
/// read the same files from src/main/assets; the Swift tests read them
/// directly from the repo root, because a fixture copy inside the package is
/// the second copy decision 0001 exists to prevent.
enum ContractSource {
    /// The repo root, derived from this file's own location
    /// (…/ios/BorgarlandCore/Tests/BorgarlandCoreTests). CONTRACT_DIR
    /// overrides it for a checkout the derivation cannot reach; it must point
    /// at the directory containing data/.
    static var repoRoot: URL {
        if let override = ProcessInfo.processInfo.environment["CONTRACT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/BorgarlandCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // BorgarlandCore
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repo root
    }

    static func dataFile(_ name: String) throws -> Data {
        try Data(contentsOf: repoRoot.appendingPathComponent("data").appendingPathComponent(name))
    }

    /// The package's own library source — the scope of the word-level
    /// vocabulary guard.
    static var sourcesDirectory: URL {
        repoRoot
            .appendingPathComponent("ios")
            .appendingPathComponent("BorgarlandCore")
            .appendingPathComponent("Sources")
    }

    /// The SwiftUI shell's source. Scanned by the same guard, at the Android
    /// app's scope rather than the package's: hostnames and paths only. The
    /// shell holds a screen's worth of internal state and may name a
    /// coordinate's parts whatever reads best there, exactly as the Kotlin app
    /// does; what it may never hold is a way to reach the city.
    static var appSourcesDirectory: URL {
        repoRoot
            .appendingPathComponent("ios")
            .appendingPathComponent("Sources")
    }
}
