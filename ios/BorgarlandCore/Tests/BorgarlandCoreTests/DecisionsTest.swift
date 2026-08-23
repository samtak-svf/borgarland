import XCTest
@testable import BorgarlandCore

/// #89. Both of these decide something a person meets, and neither had a test:
/// they lived in `ReportModel`, which has no test target, so a revert of #73 or
/// #76 left every test in the repository green.
final class DecisionsTest: XCTestCase {

    // MARK: - What the relay's answer means

    func testTheRelaysOwnJudgementIsTrusted() {
        XCTAssertEqual(RelayDisposition.of(status: 201, ok: true), .sent)
        XCTAssertEqual(RelayDisposition.of(status: 200, ok: true), .sent)
    }

    /// The half that costs a report if it is wrong in one direction and a work
    /// queue if it is wrong in the other.
    func testAnAnswerThatWouldBeTheSameNextTimeStopsTheReportWaiting() {
        XCTAssertEqual(RelayDisposition.of(status: 400, ok: false), .refused)
        XCTAssertEqual(RelayDisposition.of(status: 413, ok: false), .refused)
        XCTAssertEqual(RelayDisposition.of(status: 409, ok: false), .refused)
    }

    func testNoAnswerAndTryLaterBothKeepTheReport() {
        // 0 is the transports' convention for nothing answering at all.
        XCTAssertEqual(RelayDisposition.of(status: 0, ok: false), .waiting)
        XCTAssertEqual(RelayDisposition.of(status: 408, ok: false), .waiting)
        XCTAssertEqual(RelayDisposition.of(status: 429, ok: false), .waiting)
        XCTAssertEqual(RelayDisposition.of(status: 500, ok: false), .waiting)
        XCTAssertEqual(RelayDisposition.of(status: 503, ok: false), .waiting)
    }

    func testAnUnrecognisedStatusKeepsTheReportRatherThanDroppingIt() {
        // Failing towards keeping it: a report kept is a report somebody can
        // still send, and a report dropped is gone.
        XCTAssertEqual(RelayDisposition.of(status: 302, ok: false), .waiting)
        XCTAssertEqual(RelayDisposition.of(status: 999, ok: false), .waiting)
    }

    // MARK: - Where the permission stands

    func testGrantedIsGrantedWhateverElseIsTrue() {
        XCTAssertEqual(LocationPermission.of(granted: true, canAskAgain: false), .granted)
        XCTAssertEqual(LocationPermission.of(granted: true, canAskAgain: true), .granted)
    }

    /// The distinction #76 exists for. Both are "not granted"; only one can be
    /// fixed by asking again.
    func testARefusalTheSystemWillRevisitIsNotTheSameAsOneItWillNot() {
        XCTAssertEqual(LocationPermission.of(granted: false, canAskAgain: true), .unanswered)
        XCTAssertEqual(LocationPermission.of(granted: false, canAskAgain: false), .deniedForGood)
    }

    func testTheScreenIsNeverOfferedARetryThatCannotWork() {
        XCTAssertEqual(LocationPermission.granted.exit, .carryOn)
        XCTAssertEqual(LocationPermission.unanswered.exit, .askAgain)
        XCTAssertEqual(LocationPermission.deniedForGood.exit, .openSystemSettings)
    }

    func testTheWalkResumesOnlyWhenTheReasonItStoppedIsGone() {
        XCTAssertTrue(LocationPermission.shouldResume(after: .deniedForGood, nowGranted: true))
        XCTAssertFalse(LocationPermission.shouldResume(after: .deniedForGood, nowGranted: false))
        // Coming back from somewhere else must not restart the location step
        // under somebody who has moved on.
        XCTAssertFalse(LocationPermission.shouldResume(after: .unanswered, nowGranted: true))
        XCTAssertFalse(LocationPermission.shouldResume(after: .granted, nowGranted: true))
    }
}
