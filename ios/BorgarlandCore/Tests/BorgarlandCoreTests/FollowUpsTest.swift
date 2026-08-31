import XCTest
import BorgarlandCore

/// The follow-up list, and the interval that drives it (#57, decision 0013).
///
/// The boundary constants are pinned here AND in the Android suite
/// (`FollowUpsTest.kt`): the interval is the one behavioural number two
/// platforms must not drift on, and two spellings of one rule drift the
/// moment nothing compares them.
final class FollowUpsTest: XCTestCase {

    private func temporaryStore() throws -> FollowUps {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return FollowUps(url: directory.appendingPathComponent("follow-ups.json"))
    }

    private let nowMs: Int64 = 1_700_000_000_000

    func testTheIntervalIsFourteenDays() {
        XCTAssertEqual(FollowUps.askAfterDays, 14)
        // The boundary itself: thirteen days and 23 hours is not due, fourteen
        // days is.
        let thirteenDays = nowMs - 13 * 24 * 60 * 60 * 1000
        let fourteenDays = nowMs - 14 * 24 * 60 * 60 * 1000
        let store = FollowUps(url: URL(fileURLWithPath: "/dev/null"))
        XCTAssertFalse(store.isDue(sentAtMs: thirteenDays, nowMs: nowMs))
        XCTAssertTrue(store.isDue(sentAtMs: fourteenDays, nowMs: nowMs))
    }

    func testRecordThenDueThenAnswerThenPostRoundTrip() throws {
        let store = try temporaryStore()
        let id = "a1b2c3d4e5f60718293a4b5c6d7e8f90"

        XCTAssertTrue(store.record(id: id, categorySlug: "ruslafotur", atMs: nowMs - 14 * 24 * 60 * 60 * 1000))
        XCTAssertEqual(store.counts().rows, 1)
        XCTAssertEqual(store.counts().unasked, 1)

        // Not due yet: fourteen days back is the boundary.
        XCTAssertNotNil(store.due(nowMs: nowMs))

        // A duplicate id is not recorded twice.
        XCTAssertTrue(store.record(id: id, categorySlug: "ruslafotur", atMs: nowMs))
        XCTAssertEqual(store.counts().rows, 1)

        XCTAssertTrue(store.markAnswered(id: id, fixed: false))
        XCTAssertEqual(store.counts().unasked, 0)
        XCTAssertEqual(store.counts().unposted, 1)

        // The answer survives as unposted until the relay confirms.
        let unposted = store.unposted()
        XCTAssertEqual(unposted.count, 1)
        XCTAssertEqual(unposted[0].id, id)
        XCTAssertFalse(unposted[0].fixed)

        XCTAssertTrue(store.markPosted(id: id))
        XCTAssertEqual(store.counts().unposted, 0)
    }

    func testAReportThatIsNotDueIsNotAsked() throws {
        let store = try temporaryStore()
        XCTAssertTrue(store.record(id: "a1b2c3d4e5f60718293a4b5c6d7e8f91", categorySlug: "ruslafotur", atMs: nowMs))
        XCTAssertNil(store.due(nowMs: nowMs))
    }

    func testADismissalIsAskedAndDeliversNothing() throws {
        let store = try temporaryStore()
        let id = "a1b2c3d4e5f60718293a4b5c6d7e8f92"
        XCTAssertTrue(store.record(id: id, categorySlug: "grasgroedur", atMs: nowMs - 14 * 24 * 60 * 60 * 1000))
        XCTAssertTrue(store.markDismissed(id: id))
        XCTAssertEqual(store.counts().unasked, 0)
        XCTAssertEqual(store.counts().unposted, 0)
        XCTAssertNil(store.due(nowMs: nowMs))
    }
}
