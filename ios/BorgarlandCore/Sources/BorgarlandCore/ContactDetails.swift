import Foundation

/// The address the city will answer to, kept on the phone so it is typed once
/// rather than on every walk (#163).
///
/// It belongs to the DEVICE, not to a report. That is why it lives here rather
/// than inside `QueuedReport`, and the choice is load-bearing twice over.
///
/// A queued report picks up whatever address the phone holds when it finally
/// goes out, so somebody who corrects a typo gets the confirmation at the
/// corrected address even for a report filed before the correction. And
/// `QueuedReport` is a PERSISTED format: adding a field to it means every
/// record written by an earlier build has to keep decoding, which is the
/// silent-eviction trap that file's own comments are about. Nothing is added
/// to it here.
///
/// This file never leaves the device. What leaves is the address itself, as
/// the `email` part of the report, and only there: the event stream's
/// allowlist (data/relay-events.json) names no free-text field at all, so it
/// cannot ride that channel even by mistake, and the relay does not log it
/// (worker/src/app.ts).
public struct ContactDetails {

    private let url: URL
    private let fileManager: FileManager

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    /// Beside the queue, in Application Support: this is something the person
    /// entered, not a cache, and the system deletes Caches under disk
    /// pressure. Falls back to the temporary directory for the same reason
    /// `ReportQueue.applicationDefault` does — a phone that cannot give us
    /// Application Support should still be able to file a report, and an
    /// address that has to be retyped after a reboot beats one that cannot be
    /// entered at all.
    public static func applicationDefault(fileManager: FileManager = .default) -> ContactDetails {
        let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = support ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return ContactDetails(
            url: base.appendingPathComponent("contact-details.json"),
            fileManager: fileManager
        )
    }

    private struct Stored: Codable {
        let email: String
    }

    /// The stored address, or nil when there is none or the file cannot be
    /// read. Nil is a prompt to type one, never a reason to send without one:
    /// the send path refuses that separately.
    public func read() -> String? {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        let email = Self.normalise(stored.email)
        return email.isEmpty ? nil : email
    }

    /// Returns whether the write landed. A failure costs the person one
    /// retyping and nothing else, so no caller has to treat it as fatal.
    @discardableResult
    public func write(_ email: String?) -> Bool {
        let value = Self.normalise(email ?? "")
        guard let data = try? JSONEncoder().encode(Stored(email: value)) else { return false }
        // Atomic, so a process death mid-write cannot leave truncated JSON
        // that reads back as "no address" and quietly loses it.
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// What an address has to look like before the app will send with it, and
    /// the only place the rule lives on this platform. Android carries the
    /// same rule in `data/ContactDetails.kt`, and both test suites pin the
    /// identical table of cases, because two spellings of one rule is two
    /// rules.
    ///
    /// Deliberately loose. A strict RFC 5322 pattern rejects addresses that
    /// work, and the cost of that is a person who cannot file at all; the cost
    /// of letting an odd-looking address through is a bounce we never see.
    /// What it does catch is the typo that loses the confirmation silently —
    /// `nafn@`, `nafn`, a stray space, a domain with no dot.
    /// Scalars an address may not contain, enumerated BY CODE POINT rather
    /// than by asking the platform what whitespace is (#163, found by review).
    ///
    /// The two platforms disagree about that question and the disagreement is
    /// silent. Java's `Character.isWhitespace` returns FALSE for the
    /// non-breaking spaces U+00A0, U+2007 and U+202F — its own javadoc says so
    /// — while Swift's `Character.isWhitespace` implements the Unicode
    /// White_Space property, which includes all three. It also runs the other
    /// way: Java returns true for the C0 separators U+001C-U+001F, which are
    /// not White_Space and which Swift would let through.
    ///
    /// So `nafn@example\u{00A0}.is`, the shape a copy-pasted address arrives
    /// in, was VALID on Android and INVALID here. Nothing caught it: the relay
    /// does no format check, the city does none either, and the confirmation
    /// simply bounces — the silent silence this whole feature exists to end.
    ///
    /// An explicit table is the fix. Two platform predicates that look alike
    /// are two rules, and the test tables that claimed to be identical carried
    /// no case that could tell them apart. This table is the same one
    /// `data/ContactDetails.kt` carries; change one, change both.
    private static let blocked: Set<UInt32> = {
        var set = Set<UInt32>(0x00...0x20)          // C0 controls and the space
        set.insert(0x7F)                             // DEL
        set.formUnion([0x85, 0xA0, 0x1680])          // NEL, NBSP, Ogham space
        set.formUnion(0x2000...0x200D)               // en/em spaces, and the zero-width family
        set.formUnion([0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF])
        return set
    }()

    /// Everything below works on Unicode SCALARS, and that is the second half
    /// of the fix rather than a detail (#163, found by the review of the first
    /// half).
    ///
    /// Replacing the platform whitespace predicates with one table closed the
    /// disagreement in the middle of a string and opened a new one at its
    /// EDGES, because the two languages iterate different units. Kotlin's
    /// `Char` is a UTF-16 code unit; Swift's `Character` is a grapheme
    /// cluster, and a cluster swallows what follows it. `U+200D` is in the
    /// table and `U+0301` is not, but `s` + ZWJ + combining acute is ONE
    /// Character — so a `Character`-based trim of
    /// `nafn@a.is\u{200D}\u{0301}` removed the whole cluster and returned
    /// `nafn@a.i`, eating the last letter of the domain and calling the result
    /// valid. Android refused the same input. An address that bounces, sent
    /// from one platform and refused by the other, is precisely the failure
    /// this feature exists to end — reintroduced by the fix for it.
    ///
    /// Every entry in the table is BMP, so a scalar and a UTF-16 code unit are
    /// the same thing for anything the table names, and scalar-wise Swift and
    /// Char-wise Kotlin now agree by construction. The `@` scan is scalar-wise
    /// for the same reason: `@` followed by a combining mark is one Character,
    /// so a Character-wise `split(separator: "@")` would not find it while
    /// Kotlin's `indexOf('@')` would.
    private static func isValidScalars(_ scalars: [Unicode.Scalar]) -> Bool {
        if scalars.isEmpty { return false }
        if scalars.contains(where: { blocked.contains($0.value) }) { return false }
        guard let at = scalars.firstIndex(of: "@"),
              at > 0,
              scalars.lastIndex(of: "@") == at else { return false }
        let domain = scalars[scalars.index(after: at)...]
        guard domain.contains(".") else { return false }
        // No empty label: `a@.is`, `a@b..is` and `a@b.` are all typos. Counted
        // rather than split, so the two platforms cannot disagree about what an
        // empty subsequence is.
        var label = 0
        for scalar in domain {
            if scalar == "." {
                if label == 0 { return false }
                label = 0
            } else {
                label += 1
            }
        }
        return label > 0
    }

    public static func isValid(_ raw: String) -> Bool {
        isValidScalars(Array(normalise(raw).unicodeScalars))
    }

    /// Stored and sent with the surrounding whitespace gone, never otherwise
    /// altered — trimming the same table, one SCALAR at a time. A grapheme
    /// cluster is the wrong unit here: it takes its base character with it.
    public static func normalise(_ raw: String) -> String {
        var scalars = Array(raw.unicodeScalars)
        while let first = scalars.first, blocked.contains(first.value) { scalars.removeFirst() }
        while let last = scalars.last, blocked.contains(last.value) { scalars.removeLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}
