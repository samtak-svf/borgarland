import Foundation

/// A report someone filed that has not reached the relay yet, and where its
/// bytes are.
///
/// The fields are the report's own, not the queue's bookkeeping in disguise:
/// this is a Payload plus the two things a retry needs, when it was taken and
/// how many attempts it has cost. `photos` names files rather than carrying
/// them, so listing the queue does not pull four megabytes per entry into
/// memory to answer "is anything waiting".
public struct QueuedReport: Equatable, Codable {

    /// One photograph, as a file inside this report's directory plus the three
    /// facts the multipart body needs about it.
    public struct PhotoRef: Equatable, Codable {
        public let file: String
        public let name: String
        public let mime: String
        public let rotationDegrees: Int
        /// How large the file is. Recorded so the queue can answer how much of
        /// somebody's phone it is holding without opening every photograph to
        /// find out (#82).
        ///
        /// Decoded with a default rather than required, because this is a
        /// PERSISTED format and a required key is a silent eviction: a record
        /// written before the key existed fails to decode, `pending()` skips
        /// unreadable entries by design, and the report disappears with nobody
        /// told. The queue ships first in build 5, and build 5 was installed
        /// nowhere until 2026-08-24, when it was run — so a phone CAN now be
        /// holding such a record and the default is load-bearing rather than
        /// theoretical. This comment asserted the opposite for as long as it
        /// took somebody to update. The next field added here will have the
        /// same shape with a live queue underneath it.
        public let bytes: Int

        public init(file: String, name: String, mime: String, rotationDegrees: Int, bytes: Int) {
            self.file = file
            self.name = name
            self.mime = mime
            self.rotationDegrees = rotationDegrees
            self.bytes = bytes
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            file = try values.decode(String.self, forKey: .file)
            name = try values.decode(String.self, forKey: .name)
            mime = try values.decode(String.self, forKey: .mime)
            rotationDegrees = try values.decode(Int.self, forKey: .rotationDegrees)
            // 0 rather than a throw: a report readable and slightly
            // under-counted beats a report silently gone.
            bytes = try values.decodeIfPresent(Int.self, forKey: .bytes) ?? 0
        }
    }

    public let id: String
    public let categorySlug: String
    public let latitude: Double
    public let longitude: Double
    public let description: String

    /// Whole milliseconds since 1970. An integer on purpose: a date written by
    /// one Codable strategy and read by another is a class of bug this file
    /// cannot afford, since the thing it would corrupt is the ORDER reports go
    /// out in.
    public let queuedAtEpochMs: Int

    /// How many times we have handed this to the transport. Written down
    /// because a report that has been tried thirty times is telling us
    /// something a report that has been tried once is not.
    public internal(set) var attempts: Int

    public let photos: [PhotoRef]

    public var queuedAt: Date {
        Date(timeIntervalSince1970: Double(queuedAtEpochMs) / 1000)
    }

    /// What this report costs on the phone, near enough: the photographs are
    /// all of it that matters, and the record beside them is a few hundred
    /// bytes.
    public var bytes: Int {
        photos.reduce(0) { $0 + $1.bytes }
    }
}

/// Reports that could not be sent, kept on the phone until they can be.
///
/// #73: the first iOS field test put a phone in airplane mode and pressed
/// send. The send failed and the report was gone — one attempt, then a string
/// in the UI, and nothing anywhere that remembered what the person had filed.
/// This is a walking app; the person walking with a phone is exactly the person
/// who loses signal in a courtyard or a stairwell.
///
/// The layout is one directory per report, holding a JSON record and the photo
/// bytes as separate files:
///
///     <root>/<id>/report.json
///     <root>/<id>/photo-0
///
/// Separate files rather than one base64 blob because the photo is the large
/// part and nothing that reads the queue's SHAPE should have to load it.
///
/// **The queue is bounded, and it refuses rather than evicts (#82).**
///
/// A report leaves when it is sent, when the relay refuses it, when a person
/// discards it, and when its photo bytes have gone missing and it can no longer
/// be built. Nothing else removes one — and in particular nothing prunes it —
/// so without a bound a phone that never comes back online would keep every
/// report ever filed on it, at a photograph each.
///
/// Every policy that bounds it loses something somebody filed. Oldest-first
/// eviction throws away the report that has waited longest, which is the one
/// most likely to matter. An age limit discards a report from a walk somebody
/// still remembers taking. Both do it silently, and a queue that quietly drops
/// reports is worse than no queue, because it looks like one that works.
///
/// So this one REFUSES. `enqueue` throws `QueueError.full` and the report is
/// not written down, which the caller turns into a sentence in front of the
/// person standing right there, who can send what is waiting or throw
/// something away on purpose. Nothing leaves the queue without somebody
/// choosing it, which is the property worth keeping.
public final class ReportQueue {

    public enum QueueError: Error, Equatable {
        /// The photo file named by the record is not there. The entry cannot be
        /// sent and the caller should drop it rather than retry it forever.
        case missingPhoto(String)
        /// The queue is at its bound and this report was not written down. The
        /// caller must say so: the person is standing there and can send what
        /// is waiting or discard something, and neither happens by itself.
        case full(reports: Int, bytes: Int)
    }

    /// How many reports may wait at once.
    ///
    /// Twenty is a number about walks rather than about storage: a person fills
    /// this only by filing report after report with no network at all, and by
    /// the twentieth something is wrong that more disk will not fix. It is also
    /// far past any real walk — the first field tests filed one and two.
    public static let defaultMaxReports = 20

    /// And how much of the phone they may hold, whichever bound is reached
    /// first. A photograph off the capture path measured 0.24 to 2.29 MB across
    /// the field tests, so this is roughly a hundred of them and about the size
    /// of one large app.
    public static let defaultMaxBytes = 200 * 1024 * 1024

    private let root: URL
    private let fileManager: FileManager
    private let newID: () -> String
    private let lock = NSLock()

    /// How many reports may wait at once, and how much of the phone they may
    /// hold. Instance properties rather than the constants directly, so a test
    /// can reach the bound with two small photographs instead of two hundred
    /// megabytes of real ones.
    public let maxReports: Int
    public let maxBytes: Int

    /// `newID` is injected so a test can produce a known, ordered id; the app
    /// takes the default. So are the bounds, for the same reason.
    ///
    /// The id is 32 lowercase hex, not a UUID: since #88 it travels with the
    /// report and becomes the relay's own row id, and the relay's ids have that
    /// shape. One id for one report, in one form, everywhere it is written down.
    public init(
        root: URL,
        fileManager: FileManager = .default,
        newID: @escaping () -> String = { RandomHex.id() },
        maxReports: Int = ReportQueue.defaultMaxReports,
        maxBytes: Int = ReportQueue.defaultMaxBytes
    ) {
        self.root = root
        self.fileManager = fileManager
        self.newID = newID
        self.maxReports = maxReports
        self.maxBytes = maxBytes
    }

    /// Where the app keeps it.
    ///
    /// Application Support, not Documents: nothing here is a document a person
    /// browses, and Documents is visible in Files when the app opts into it.
    /// Not Caches either — the system deletes Caches under disk pressure, and a
    /// report someone filed is not a cache.
    ///
    /// Falls back to the temporary directory rather than throwing. A phone that
    /// cannot give us Application Support should still be able to send, and a
    /// queue that survives only until the next reboot is worth more than no
    /// queue at all.
    public static func applicationDefault(fileManager: FileManager = .default) -> ReportQueue {
        let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = support ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return ReportQueue(root: base.appendingPathComponent("queued-reports", isDirectory: true))
    }

    // MARK: - Writing

    /// Writes a report down and returns it. Call this BEFORE trying to send:
    /// the whole point is that the failure arrives after the decision to send,
    /// so a report that exists only in memory at that moment is one that can be
    /// lost by the very thing we are guarding against.
    @discardableResult
    public func enqueue(_ payload: Payload, at date: Date = Date()) throws -> QueuedReport {
        lock.lock()
        defer { lock.unlock() }

        // Read INSIDE the lock, through the unlocked reader. An earlier version
        // called `pending()` before taking the lock, because `pending()` takes
        // it and the lock is not recursive — which avoided the deadlock and
        // bought a check-then-act gap instead: two callers could both see room
        // and both write. Every call is main-actor serialised in the app today,
        // so it could not fire; the type is public and the lock exists for
        // callers that are not.
        let waiting = pendingLocked()
        let incoming = payload.photos.reduce(0) { $0 + $1.bytes.count }
        let held = waiting.reduce(0) { $0 + $1.bytes }
        if waiting.count >= maxReports || held + incoming > maxBytes {
            throw QueueError.full(reports: waiting.count, bytes: held)
        }

        let id = newID()
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // A write that fails halfway leaves photo bytes in a directory with no
        // readable record, which `pending()` cannot see, `maxBytes` cannot
        // count and nothing can remove: a leak of one photograph per failure,
        // on exactly the disk-pressure path this throws for.
        var wrote = false
        defer {
            if !wrote { try? fileManager.removeItem(at: directory) }
        }

        var refs: [QueuedReport.PhotoRef] = []
        for (index, photo) in payload.photos.enumerated() {
            let file = "photo-\(index)"
            try write(photo.bytes, to: directory.appendingPathComponent(file))
            refs.append(
                QueuedReport.PhotoRef(
                    file: file,
                    name: photo.name,
                    mime: photo.mime,
                    rotationDegrees: photo.rotationDegrees,
                    bytes: photo.bytes.count
                )
            )
        }

        let report = QueuedReport(
            id: id,
            categorySlug: payload.categorySlug,
            latitude: payload.latitude,
            longitude: payload.longitude,
            description: payload.description,
            queuedAtEpochMs: Int((date.timeIntervalSince1970 * 1000).rounded()),
            attempts: 0,
            photos: refs
        )
        try writeRecord(report)
        wrote = true
        return report
    }

    /// One more attempt against this report's name. Silent when the entry has
    /// gone: a report removed between the read and the write is not an error,
    /// it is a report that arrived.
    public func recordAttempt(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var report = readRecord(id: id) else { return }
        report.attempts += 1
        try? writeRecord(report)
    }

    /// Drops a report and its photographs. Used for all three endings — sent,
    /// refused by the relay, discarded by the person — because from here they
    /// are the same act: this report is not waiting any more.
    public func remove(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        // A traversal in an id would reach outside the queue. Ids are 32 hex
        // characters from a secure source, so this cannot happen; it costs one
        // line and the file it would delete is somebody's.
        guard !id.isEmpty, !id.contains("/"), id != ".", id != ".." else { return }
        try? fileManager.removeItem(at: root.appendingPathComponent(id, isDirectory: true))
    }

    // MARK: - Reading

    /// Everything waiting, oldest first.
    ///
    /// An entry that cannot be read is skipped rather than thrown, and the id
    /// breaks a tie on the millisecond, so the order is total: two reports
    /// queued in the same millisecond still go out in a fixed order rather than
    /// whatever the filesystem lists first.
    public func pending() -> [QueuedReport] {
        lock.lock()
        defer { lock.unlock() }
        return pendingLocked()
    }

    /// The same read, for a caller that already holds the lock. The lock is not
    /// recursive, so this exists rather than a second `lock()`.
    private func pendingLocked() -> [QueuedReport] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [] }
        return entries
            .compactMap { readRecord(id: $0) }
            .sorted { ($0.queuedAtEpochMs, $0.id) < ($1.queuedAtEpochMs, $1.id) }
    }

    /// The report as something that can be sent, photo bytes and all. Throws
    /// `missingPhoto` when the bytes are gone, which the caller must treat as
    /// unsendable rather than as a failure to retry: an entry that can never be
    /// built would otherwise sit at the head of the queue forever.
    public func payload(for report: QueuedReport) throws -> Payload {
        lock.lock()
        defer { lock.unlock() }
        let directory = root.appendingPathComponent(report.id, isDirectory: true)
        var photos: [Photo] = []
        for ref in report.photos {
            guard let bytes = try? Data(contentsOf: directory.appendingPathComponent(ref.file)) else {
                throw QueueError.missingPhoto(ref.file)
            }
            photos.append(
                Photo(bytes: bytes, name: ref.name, mime: ref.mime, rotationDegrees: ref.rotationDegrees)
            )
        }
        return Payload(
            categorySlug: report.categorySlug,
            latitude: report.latitude,
            longitude: report.longitude,
            description: report.description,
            photos: photos,
            // The queue's id IS the report's id on the wire (#88). Without this
            // line a retry of a report the relay already stored becomes a
            // second row, which is the whole thing the id exists to prevent.
            reportId: report.id
        )
    }

    // MARK: - The files themselves

    private func recordURL(id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("report.json")
    }

    private func writeRecord(_ report: QueuedReport) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try write(try encoder.encode(report), to: recordURL(id: report.id))
    }

    private func readRecord(id: String) -> QueuedReport? {
        guard let data = try? Data(contentsOf: recordURL(id: id)) else { return nil }
        return try? JSONDecoder().decode(QueuedReport.self, from: data)
    }

    /// Atomic so a process death mid-write leaves the previous file rather than
    /// half of the new one, and, on a phone, readable only while the device is
    /// unlocked. The strongest protection class is the right one here precisely
    /// because retries happen in the foreground: nothing needs these bytes
    /// while the phone is in a pocket, and they are a photograph of where
    /// somebody was standing.
    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }
}
