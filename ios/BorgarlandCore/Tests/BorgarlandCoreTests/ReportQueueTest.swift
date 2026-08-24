import XCTest
@testable import BorgarlandCore

/// #73: a send that loses the network lost the report. These tests are about
/// the one property that fixes it — a report survives the moment it fails to
/// send — and about the two ways a queue quietly stops working: an entry that
/// can never be built blocking the head of it, and an order that depends on
/// whatever the filesystem happens to list first.
final class ReportQueueTest: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("borgarland-queue-test-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeQueue(ids: [String] = []) -> ReportQueue {
        var remaining = ids
        return ReportQueue(
            root: root,
            newID: { remaining.isEmpty ? UUID().uuidString : remaining.removeFirst() }
        )
    }

    private func payload(
        slug: String = "ruslafotur",
        description: String = "Full ruslafata",
        photo: Data? = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02])
    ) -> Payload {
        Payload(
            categorySlug: slug,
            latitude: 64.1466,
            longitude: -21.9426,
            description: description,
            photos: photo.map { [Photo(bytes: $0, name: "mynd.jpg", mime: "image/jpeg", rotationDegrees: 90)] } ?? []
        )
    }

    // MARK: - Surviving the failure

    func testAQueuedReportComesBackWholeIncludingItsPhotograph() throws {
        let bytes = Data((0..<4096).map { UInt8($0 % 251) })
        let queue = makeQueue()

        let queued = try queue.enqueue(payload(photo: bytes), at: Date(timeIntervalSince1970: 1_700))

        // A different instance: the report has to survive the object, not just
        // the variable. This is the process-death case in miniature.
        let reread = ReportQueue(root: root).pending()
        XCTAssertEqual(reread.count, 1)
        XCTAssertEqual(reread.first?.id, queued.id)
        XCTAssertEqual(reread.first?.categorySlug, "ruslafotur")
        XCTAssertEqual(reread.first?.description, "Full ruslafata")
        XCTAssertEqual(reread.first?.latitude, 64.1466)
        XCTAssertEqual(reread.first?.longitude, -21.9426)
        XCTAssertEqual(reread.first?.queuedAt, Date(timeIntervalSince1970: 1_700))

        let first = try XCTUnwrap(reread.first)
        let restored = try ReportQueue(root: root).payload(for: first)
        XCTAssertEqual(restored.photos.count, 1)
        XCTAssertEqual(restored.photos.first?.bytes, bytes, "the photograph must come back byte for byte")
        XCTAssertEqual(restored.photos.first?.name, "mynd.jpg")
        XCTAssertEqual(restored.photos.first?.mime, "image/jpeg")
        XCTAssertEqual(restored.photos.first?.rotationDegrees, 90, "rotation survives, or the photo arrives sideways")
    }

    /// #88's integration, which nothing pinned: the builder test supplies its
    /// own id, and the round-trip test checked every field except the one that
    /// travels. Deleting `reportId: report.id` from `payload(for:)` left the
    /// whole suite green.
    func testTheQueuesOwnIdIsWhatTheReportCarriesToTheRelay() throws {
        let queue = makeQueue(ids: ["a1b2c3d4e5f60718293a4b5c6d7e8f90"])
        let queued = try queue.enqueue(payload())

        // Through a fresh instance, so this is the id as READ BACK rather than
        // the one still in hand: a retry after a relaunch is the case that
        // matters.
        let reread = try XCTUnwrap(ReportQueue(root: root).pending().first)
        let restored = try ReportQueue(root: root).payload(for: reread)
        XCTAssertEqual(restored.reportId, queued.id)
        XCTAssertEqual(restored.reportId, "a1b2c3d4e5f60718293a4b5c6d7e8f90")
    }

    /// The bytes field was added to a PERSISTED format. A required key is a
    /// silent eviction: the record fails to decode and `pending()` skips
    /// unreadable entries by design, so the report disappears with nobody told.
    func testARecordWrittenBeforeTheSizeFieldExistedIsStillReadable() throws {
        let queue = makeQueue(ids: ["older"])
        try queue.enqueue(payload())

        // The same record as a build that predates `bytes` would have left it.
        let record = root.appendingPathComponent("older", isDirectory: true)
            .appendingPathComponent("report.json")
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try Data(contentsOf: record)) as? [String: Any]
        )
        var photos = try XCTUnwrap(json["photos"] as? [[String: Any]])
        photos[0].removeValue(forKey: "bytes")
        json["photos"] = photos
        try JSONSerialization.data(withJSONObject: json).write(to: record)

        let reread = ReportQueue(root: root).pending()
        XCTAssertEqual(reread.count, 1, "the report must not vanish because the format grew")
        XCTAssertEqual(reread.first?.photos.first?.bytes, 0, "unknown size counts as none, not as gone")
    }

    /// A write that fails halfway used to leave photo bytes in a directory with
    /// no readable record: invisible to `pending()`, uncounted by the byte
    /// bound, and removable by nothing.
    func testAHalfWrittenReportLeavesNothingBehind() throws {
        let queue = ReportQueue(root: root, maxBytes: 1)
        XCTAssertThrowsError(try queue.enqueue(payload()))
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        XCTAssertEqual(entries, [], "a refused report leaves no directory at all")
    }

    func testAReportWithNoPhotographIsStillAReport() throws {
        let queue = makeQueue()
        let queued = try queue.enqueue(payload(photo: nil))
        XCTAssertEqual(try queue.payload(for: queued).photos.count, 0)
    }

    // MARK: - Order

    func testTheOldestGoesFirst() throws {
        let queue = makeQueue(ids: ["c", "a", "b"])
        try queue.enqueue(payload(description: "third"), at: Date(timeIntervalSince1970: 300))
        try queue.enqueue(payload(description: "first"), at: Date(timeIntervalSince1970: 100))
        try queue.enqueue(payload(description: "second"), at: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(queue.pending().map(\.description), ["first", "second", "third"])
    }

    /// Two reports queued in the same millisecond must still have an order, or
    /// the head of the queue depends on directory listing order and a report
    /// can be overtaken by one filed after it on every retry.
    func testTwoReportsInTheSameMillisecondStillHaveAnOrder() throws {
        let sameMoment = Date(timeIntervalSince1970: 500)
        let queue = makeQueue(ids: ["bbb", "aaa"])
        try queue.enqueue(payload(description: "queued as bbb"), at: sameMoment)
        try queue.enqueue(payload(description: "queued as aaa"), at: sameMoment)

        XCTAssertEqual(queue.pending().map(\.id), ["aaa", "bbb"])
    }

    // MARK: - Leaving the queue

    func testRemovingTakesThePhotographWithIt() throws {
        let queue = makeQueue(ids: ["only"])
        let queued = try queue.enqueue(payload())
        let directory = root.appendingPathComponent("only", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))

        queue.remove(queued.id)

        XCTAssertTrue(queue.pending().isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: directory.path),
            "the photograph must go with the report, not linger in the container"
        )
    }

    func testRemovingSomethingThatIsNotThereIsNotAnError() throws {
        let queue = makeQueue()
        queue.remove("never-existed")
        XCTAssertTrue(queue.pending().isEmpty)
    }

    /// An id is a path component. Ids come from UUID today, so this is a guard
    /// rather than a fix, and the file it would otherwise delete is somebody's.
    func testAnIdThatTriesToLeaveTheQueueRemovesNothing() throws {
        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("borgarland-not-ours-\(UUID().uuidString)")
        try Data("keep me".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        makeQueue().remove("../\(outside.lastPathComponent)")

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    // MARK: - The bound

    /// #82. Every policy that bounds a queue loses something somebody filed;
    /// this one loses nothing, because it refuses the new report instead of
    /// dropping an old one, in front of the person who can act on it.
    func testTheQueueRefusesRatherThanEvictsWhenItIsFull() throws {
        let queue = ReportQueue(root: root, maxReports: 3)
        for i in 0..<3 {
            try queue.enqueue(payload(description: "report \(i)"))
        }

        XCTAssertThrowsError(try queue.enqueue(payload(description: "one too many"))) { error in
            guard case .full(let reports, _)? = error as? ReportQueue.QueueError else {
                return XCTFail("expected .full, got \(error)")
            }
            XCTAssertEqual(reports, 3)
        }

        // The point of refusing: everything already waiting is still there.
        XCTAssertEqual(queue.pending().count, 3)
        XCTAssertFalse(
            queue.pending().contains { $0.description == "one too many" },
            "the refused report was not written down, which is what the caller has to say"
        )
    }

    func testTheByteBoundRefusesBeforeTheCountDoes() throws {
        // Room for twenty reports and for two photographs.
        let queue = ReportQueue(root: root, maxBytes: 9000)
        let photo = Data(repeating: 0xFF, count: 4096)
        try queue.enqueue(payload(photo: photo))
        try queue.enqueue(payload(photo: photo))
        XCTAssertThrowsError(try queue.enqueue(payload(photo: photo)))
        XCTAssertEqual(queue.pending().count, 2)
    }

    func testRoomIsMadeByThingsLeavingTheQueue() throws {
        let queue = ReportQueue(root: root, maxReports: 2)
        try queue.enqueue(payload())
        try queue.enqueue(payload())
        XCTAssertThrowsError(try queue.enqueue(payload()))

        // Sending one, or a person discarding one, is the only way back.
        queue.remove(try XCTUnwrap(queue.pending().first).id)
        XCTAssertNoThrow(try queue.enqueue(payload()))
    }

    func testTheAppsBoundsAreTheOnesWrittenDown() {
        let queue = ReportQueue(root: root)
        XCTAssertEqual(queue.maxReports, ReportQueue.defaultMaxReports)
        XCTAssertEqual(queue.maxBytes, ReportQueue.defaultMaxBytes)
    }

    func testAReportKnowsWhatItCostsOnThePhone() throws {
        let queue = makeQueue()
        let bytes = Data(repeating: 0xAB, count: 4096)
        try queue.enqueue(payload(photo: bytes))
        XCTAssertEqual(queue.pending().first?.bytes, 4096)
    }

    // MARK: - Attempts

    func testAttemptsAreCountedAndSurviveAReread() throws {
        let queue = makeQueue(ids: ["tried"])
        try queue.enqueue(payload())
        XCTAssertEqual(queue.pending().first?.attempts, 0)

        queue.recordAttempt("tried")
        queue.recordAttempt("tried")

        XCTAssertEqual(ReportQueue(root: root).pending().first?.attempts, 2)
    }

    func testRecordingAnAttemptAgainstAReportThatArrivedIsSilent() throws {
        let queue = makeQueue()
        queue.recordAttempt("gone")
        XCTAssertTrue(queue.pending().isEmpty)
    }

    // MARK: - Entries that cannot be sent

    /// The failure mode that turns a queue into a stuck queue: an entry whose
    /// bytes are gone can never be built, so the caller has to be told it is
    /// unsendable rather than handed a retry that will fail identically.
    func testAReportWhosePhotographIsGoneSaysSoRatherThanReturningHalfOfIt() throws {
        let queue = makeQueue(ids: ["broken"])
        let queued = try queue.enqueue(payload())
        try FileManager.default.removeItem(
            at: root.appendingPathComponent("broken", isDirectory: true).appendingPathComponent("photo-0")
        )

        XCTAssertThrowsError(try queue.payload(for: queued)) { error in
            XCTAssertEqual(error as? ReportQueue.QueueError, .missingPhoto("photo-0"))
        }
    }

    func testAnUnreadableEntryIsSkippedRatherThanBreakingTheListing() throws {
        let queue = makeQueue(ids: ["good"])
        try queue.enqueue(payload(description: "readable"))

        let junk = root.appendingPathComponent("junk", isDirectory: true)
        try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: junk.appendingPathComponent("report.json"))

        XCTAssertEqual(queue.pending().map(\.description), ["readable"])
    }

    func testAnEmptyQueueIsEmptyEvenBeforeAnythingHasEverBeenWritten() {
        XCTAssertTrue(ReportQueue(root: root).pending().isEmpty)
    }
}
