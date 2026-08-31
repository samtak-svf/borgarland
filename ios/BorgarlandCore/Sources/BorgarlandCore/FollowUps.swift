import Foundation

/// The list of reports this phone filed, so it can ask later whether they got
/// fixed (#57, decision 0013), and so an answer is not lost when the post
/// fails (#129).
///
/// The design rests on one fact: the report id is generated HERE, before the
/// report is sent (decision 0010). Asking about a report later needs nothing
/// the app does not already have, and in particular needs no way to contact
/// anybody. The Android half lives in `data/FollowUps.kt`; two spellings of
/// one rule drift the moment nothing compares them, so the boundary constants
/// are pinned by both test suites.
///
/// This file never leaves the device.
public struct FollowUps {

    /// Picked rather than measured, and decision 0013 says so. The city
    /// publishes no response-time data, which is the reason this measurement
    /// exists, so there is no figure to derive an interval from.
    public static let askAfterDays = 14
    private static let askAfterMs = TimeInterval(askAfterDays * 24 * 60 * 60)

    /// Rows are dropped once the answer is safely delivered AND they are older
    /// than this. Without it the file grows for the life of the install
    /// (#129). Generous, because the only cost of keeping a delivered row is
    /// bytes and the cost of dropping one too early is asking twice.
    private static let keepAfterPostedMs = TimeInterval(90 * 24 * 60 * 60)

    public struct Pending {
        public let id: String
        public let sentAtMs: Int64
        public let categorySlug: String
    }

    /// An answer given but not yet accepted by the relay.
    public struct Unposted {
        public let id: String
        public let fixed: Bool
    }

    /// `asked` is set whether or not the person answers: somebody who dismisses
    /// the question has answered it, and asking again is a nag.
    ///
    /// `answer` is nil for a dismissal and non-nil for a real answer. A
    /// non-nil answer with `posted` false is the retry queue: the person told
    /// us something and the relay has not heard it yet.
    private struct Row: Codable {
        var id: String
        var sentAtMs: Int64
        var categorySlug: String
        var asked: Bool
        var answer: Bool?
        var posted: Bool
    }

    private let url: URL
    private let fileManager: FileManager

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    /// Beside the queue and the address, in Application Support: the ids of
    /// reports the phone filed are not a cache. Falls back to the temporary
    /// directory for the same reason `ContactDetails.applicationDefault` does.
    public static func applicationDefault(fileManager: FileManager = .default) -> FollowUps {
        let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = support ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return FollowUps(
            url: base.appendingPathComponent("follow-ups.json"),
            fileManager: fileManager
        )
    }

    private func read() -> [Row] {
        guard let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        // A duplicate id would be asked about twice, because markAnswered
        // only ever touches the first match. Dropping it on read makes that
        // unreachable regardless of how the file came to hold one (#129).
        var seen = Set<String>()
        return rows.filter { seen.insert($0.id).inserted }
    }

    /// Write to a sibling file and rename over the target, so a process death
    /// mid-write cannot leave truncated JSON that reads back as an empty list
    /// (#129) — the same failure mode `ContactDetails` guards against, and the
    /// same fix.
    @discardableResult
    private func write(_ rows: [Row]) -> Bool {
        guard let data = try? JSONEncoder().encode(rows) else { return false }
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

    /// Called when the relay accepted a report. A repeat id is not added twice.
    @discardableResult
    public func record(id: String, categorySlug: String, atMs: Int64) -> Bool {
        var rows = read()
        if rows.contains(where: { $0.id == id }) { return true }
        rows.append(
            Row(
                id: id,
                sentAtMs: atMs,
                categorySlug: categorySlug,
                asked: false,
                answer: nil,
                posted: false
            )
        )
        return write(prune(rows, nowMs: atMs))
    }

    /// Whether a report sent at [sentAtMs] is old enough to ask about. Pure
    /// and separate from the file so the interval is testable.
    public func isDue(sentAtMs: Int64, nowMs: Int64) -> Bool {
        Double(nowMs - sentAtMs) / 1000 >= Self.askAfterMs
    }

    /// The oldest report that is due and has not been asked about, or nil.
    /// One question at a time: a queue of them is a nag.
    public func due(nowMs: Int64) -> Pending? {
        read()
            .filter { !$0.asked && isDue(sentAtMs: $0.sentAtMs, nowMs: nowMs) }
            .min(by: { $0.sentAtMs < $1.sentAtMs })
            .map { Pending(id: $0.id, sentAtMs: $0.sentAtMs, categorySlug: $0.categorySlug) }
    }

    /// The person answered. Recorded BEFORE the post is attempted and kept
    /// until the relay confirms, so a failed send is retried rather than lost
    /// (#129).
    @discardableResult
    public func markAnswered(id: String, fixed: Bool) -> Bool {
        update(id) { $0.asked = true; $0.answer = fixed; $0.posted = false }
    }

    /// Dismissed without answering. Asked, but there is nothing to deliver.
    @discardableResult
    public func markDismissed(id: String) -> Bool {
        update(id) { $0.asked = true; $0.answer = nil; $0.posted = true }
    }

    /// The relay accepted the answer; stop retrying it.
    @discardableResult
    public func markPosted(id: String) -> Bool {
        update(id) { $0.posted = true }
    }

    /// Answers the relay has not accepted yet, oldest first.
    public func unposted() -> [Unposted] {
        read()
            .filter { $0.answer != nil && !$0.posted }
            .sorted { $0.sentAtMs < $1.sentAtMs }
            .map { Unposted(id: $0.id, fixed: $0.answer == true) }
    }

    private func update(_ id: String, _ change: (inout Row) -> Void) -> Bool {
        var rows = read()
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return false }
        change(&rows[index])
        return write(rows)
    }

    /// Delivered rows older than the keep window are dropped.
    private func prune(_ rows: [Row], nowMs: Int64) -> [Row] {
        rows.filter { !$0.posted || Double(nowMs - $0.sentAtMs) / 1000 <= Self.keepAfterPostedMs }
    }

    /// Test seam: total rows, unasked rows, and answers awaiting delivery.
    public func counts() -> (rows: Int, unasked: Int, unposted: Int) {
        let rows = read()
        return (
            rows.count,
            rows.filter { !$0.asked }.count,
            rows.filter { $0.answer != nil && !$0.posted }.count
        )
    }
}
