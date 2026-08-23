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

        public init(file: String, name: String, mime: String, rotationDegrees: Int) {
            self.file = file
            self.name = name
            self.mime = mime
            self.rotationDegrees = rotationDegrees
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
/// Deliberately not addressed here, and worth knowing before this grows:
/// **nothing prunes the queue.** A report leaves when it is sent, when the relay
/// refuses it, when a person discards it, and when its photo bytes have gone
/// missing and it can no longer be built. Nothing else removes one, so a phone
/// that never comes back online keeps every report ever filed on it. At one photograph each and
/// a handful of reports per walk that is the right trade; at a hundred it is
/// not, and the fix then is a policy decision (oldest-first eviction loses
/// someone's report, refusing new ones loses a different one) rather than a
/// line of code.
public final class ReportQueue {

    public enum QueueError: Error, Equatable {
        /// The photo file named by the record is not there. The entry cannot be
        /// sent and the caller should drop it rather than retry it forever.
        case missingPhoto(String)
    }

    private let root: URL
    private let fileManager: FileManager
    private let newID: () -> String
    private let lock = NSLock()

    /// `newID` is injected so a test can produce a known, ordered id; the app
    /// takes the default.
    public init(
        root: URL,
        fileManager: FileManager = .default,
        newID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.root = root
        self.fileManager = fileManager
        self.newID = newID
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

        let id = newID()
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var refs: [QueuedReport.PhotoRef] = []
        for (index, photo) in payload.photos.enumerated() {
            let file = "photo-\(index)"
            try write(photo.bytes, to: directory.appendingPathComponent(file))
            refs.append(
                QueuedReport.PhotoRef(
                    file: file,
                    name: photo.name,
                    mime: photo.mime,
                    rotationDegrees: photo.rotationDegrees
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
        // A traversal in an id would reach outside the queue. Ids come from
        // UUID today, so this cannot happen; it costs one line and the file it
        // would delete is somebody's.
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
            photos: photos
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
