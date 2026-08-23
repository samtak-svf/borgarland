import XCTest
@testable import BorgarlandCore

/// #77: a tester read `{"error":"outside-reykjavik",...}` on his phone and asked
/// what it meant; the other read the whole stored row and asked whether the app
/// was connected to anything. These tests are about the mapping from a relay
/// answer to a sentence, and about the file being the only place those
/// sentences live.
final class RelayOutcomesTest: XCTestCase {

    private func file() throws -> RelayOutcomesFile {
        try RelayOutcomes.parse(try ContractSource.dataFile("relay-outcomes.json"))
    }

    // MARK: - The file itself

    func testEveryEntryInTheFileSaysSomething() throws {
        let file = try file()
        for (code, outcome) in file.outcomes {
            XCTAssertFalse(outcome.says.isEmpty, "\(code) says nothing")
        }
        XCTAssertFalse(file.sent.says.isEmpty)
        XCTAssertFalse(file.dryRun.says.isEmpty)
        XCTAssertFalse(file.noAnswer.says.isEmpty)
        XCTAssertFalse(file.unknown.says.isEmpty)
    }

    /// The two the issue names. `live-send-already-used` is the one to forget:
    /// dry run never produces it, so it cannot be met until the day the relay is
    /// armed, which is the day it matters.
    func testTheCodesTheFieldTestAndTheArmedRelayProduce() throws {
        let file = try file()
        XCTAssertNotNil(file.outcomes["outside-reykjavik"])
        XCTAssertNotNil(file.outcomes["live-send-already-used"])
    }

    // MARK: - Reading an answer

    func testReadsTheErrorCodeOutOfARefusal() {
        let body = """
        {"error":"outside-reykjavik","reason":"…","nearestAddress":"…","svfnr":4200}
        """
        XCTAssertEqual(RelayOutcomes.read(body).errorCode, "outside-reykjavik")
        XCTAssertNil(RelayOutcomes.read(body).dryRun)
    }

    func testReadsTheDryRunFlagOutOfAStoredRow() {
        let body = """
        {"report":{"id":"abc","dryRun":true,"sentAt":null},"cityPayload":{}}
        """
        XCTAssertEqual(RelayOutcomes.read(body).dryRun, true)
        XCTAssertNil(RelayOutcomes.read(body).errorCode)
    }

    /// The failure path is the last place to fail again: anything unparseable
    /// answers nil rather than throwing.
    func testABodyThatIsNotJsonAnswersNothingRatherThanThrowing() {
        let answer = RelayOutcomes.read("<html>502 Bad Gateway</html>")
        XCTAssertNil(answer.errorCode)
        XCTAssertNil(answer.dryRun)
    }

    func testAnEmptyBodyAnswersNothing() {
        XCTAssertEqual(RelayOutcomes.read(""), RelayOutcomes.Answer(errorCode: nil, dryRun: nil))
    }

    // MARK: - Choosing the sentence

    func testARefusalGetsItsOwnSentence() throws {
        let file = try file()
        let outcome = RelayOutcomes.sentence(
            status: 400,
            body: #"{"error":"outside-reykjavik","svfnr":4200}"#,
            in: file
        )
        XCTAssertEqual(outcome, file.outcomes["outside-reykjavik"])
    }

    func testADryRunSuccessDoesNotClaimTheReportReachedTheCity() throws {
        let file = try file()
        let outcome = RelayOutcomes.sentence(
            status: 201,
            body: #"{"report":{"dryRun":true},"cityPayload":{}}"#,
            in: file
        )
        XCTAssertEqual(outcome, file.dryRun)
        XCTAssertNotEqual(outcome, file.sent, "the relay forwarded nothing, and the sentence must not say otherwise")
    }

    func testARealSuccessSaysItArrived() throws {
        let file = try file()
        XCTAssertEqual(
            RelayOutcomes.sentence(status: 201, body: #"{"report":{"dryRun":false}}"#, in: file),
            file.sent
        )
    }

    func testNoAnswerAtAllHasItsOwnSentence() throws {
        let file = try file()
        XCTAssertEqual(RelayOutcomes.sentence(status: 0, body: "timed out", in: file), file.noAnswer)
    }

    /// Should be unreachable: worker/tests/outcomes.test.ts fails the build when
    /// the relay can answer with a code this file does not name. "Should be
    /// unreachable" is not a reason to show somebody raw JSON.
    func testACodeTheFileDoesNotNameStillGetsASentence() throws {
        let file = try file()
        XCTAssertEqual(
            RelayOutcomes.sentence(status: 400, body: #"{"error":"something-new"}"#, in: file),
            file.unknown
        )
    }

    func testARefusalWithNoCodeAtAllStillGetsASentence() throws {
        let file = try file()
        XCTAssertEqual(RelayOutcomes.sentence(status: 500, body: "", in: file), file.unknown)
    }

    /// Nil rather than a sentence written in Swift. A second place for our
    /// words is a second place for them to drift, and a screen with no sentence
    /// still has the relay's own answer on it.
    func testAMissingFileProducesNoSentenceRatherThanAnInventedOne() {
        XCTAssertNil(RelayOutcomes.sentence(status: 400, body: #"{"error":"internal"}"#, in: nil))
    }
}
