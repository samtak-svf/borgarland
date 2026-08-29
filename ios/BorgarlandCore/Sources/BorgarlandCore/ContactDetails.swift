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
        let email = stored.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? nil : email
    }

    /// Returns whether the write landed. A failure costs the person one
    /// retyping and nothing else, so no caller has to treat it as fatal.
    @discardableResult
    public func write(_ email: String?) -> Bool {
        let value = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
    public static func isValid(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value.contains(where: { $0.isWhitespace }) { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard domain.contains(".") else { return false }
        // No empty label: `a@.is`, `a@b..is` and `a@b.` are all typos.
        return !domain.split(separator: ".", omittingEmptySubsequences: false).contains(where: { $0.isEmpty })
    }

    /// Stored and sent with the surrounding whitespace gone, never otherwise
    /// altered.
    public static func normalise(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
