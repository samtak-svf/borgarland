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

    /// The sentence is the RENDERED outcome, not the file's entry verbatim.
    /// They differ exactly where the entry carries a `{name}` placeholder: this
    /// body names no place, so the detail line is dropped and everything else
    /// is the file's own words (#148).
    func testARefusalGetsItsOwnSentence() throws {
        let file = try file()
        let outcome = RelayOutcomes.sentence(
            status: 400,
            body: #"{"error":"outside-reykjavik","svfnr":4200}"#,
            in: file
        )
        let entry = try XCTUnwrap(file.outcomes["outside-reykjavik"])
        XCTAssertEqual(outcome?.says, entry.says)
        XCTAssertEqual(outcome?.advice, entry.advice)
        XCTAssertNil(outcome?.detail)
    }

    /// #148: a refusal a person retries is a refusal that does not read as
    /// final. A tester pressed send three times against the same jurisdiction
    /// 400 because the button was the only live control on the screen.
    func testAJurisdictionRefusalIsNotRetryable() throws {
        let file = try file()
        XCTAssertEqual(file.outcomes["outside-reykjavik"]?.isRetryable, false)
        XCTAssertEqual(file.outcomes["jurisdiction-unknown"]?.isRetryable, false)
        XCTAssertEqual(file.outcomes["live-send-already-used"]?.isRetryable, false)
        XCTAssertEqual(file.outcomes["invalid-report-id"]?.isRetryable, false)
    }

    /// Absent means retryable. Wrongly retryable costs a wasted request;
    /// wrongly terminal takes the only control on the screen away from
    /// somebody who could have succeeded.
    func testAnOutcomeThatSaysNothingAboutRetryingIsRetryable() throws {
        let file = try file()
        XCTAssertEqual(file.outcomes["city-unreachable"]?.isRetryable, true)
        XCTAssertEqual(file.sent.isRetryable, true)
    }

    /// The placeholder is filled from the relay's own answer, never invented.
    func testTheDetailSentenceNamesThePlaceTheRelayReported() throws {
        let file = try file()
        let outcome = RelayOutcomes.sentence(
            status: 400,
            body: #"{"error":"outside-reykjavik","svfnr":8716,"placeDative":"Hveragerði"}"#,
            in: file
        )
        XCTAssertEqual(outcome?.detail, "Næsta skráða heimilisfang er í Hveragerði.")
    }

    /// Half a sentence in front of somebody is worse than the silence the
    /// screen had before it, so a placeholder with nothing behind it drops the
    /// whole line. A number is not a string and must not become the word it
    /// prints as.
    func testADetailWithNoFieldBehindItIsDropped() throws {
        let file = try file()
        XCTAssertNil(
            RelayOutcomes.sentence(status: 400, body: #"{"error":"outside-reykjavik"}"#, in: file)?.detail
        )
        XCTAssertNil(
            RelayOutcomes.sentence(
                status: 400,
                body: #"{"error":"outside-reykjavik","placeDative":8716}"#,
                in: file
            )?.detail
        )
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
