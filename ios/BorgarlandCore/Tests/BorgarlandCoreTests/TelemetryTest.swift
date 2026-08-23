import XCTest
@testable import BorgarlandCore

/// The client half of the telemetry channel, pinned to data/relay-events.json.
/// The contract is the privacy boundary, so these tests are about what can
/// and cannot reach the wire: the envelope shape, the session format, the
/// batch cap, and above all that a description string handed anywhere near
/// the channel never appears in an encoded body.
final class TelemetryTest: XCTestCase {

    // MARK: - Envelope

    func testEnvelopeCarriesTheContractShape() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var bodies: [Data] = []
        let telemetry = Telemetry(
            sessionID: String(repeating: "ab", count: 16),
            sessionStart: start,
            now: { start.addingTimeInterval(1.5) }
        )
        telemetry.appVersion = "0.1.0 (3)"
        telemetry.send = { body, done in bodies.append(body); done(.delivered) }

        telemetry.track(.appOpened)
        telemetry.track(.sendStarted)
        telemetry.flush()

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(bodies.first)) as? [String: Any])
        XCTAssertEqual(json["session"] as? String, String(repeating: "ab", count: 16))
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertEqual(json["appVersion"] as? String, "0.1.0 (3)")

        let events = try XCTUnwrap(json["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 2)
        // atMs is the offset from session start, recorded per event.
        XCTAssertEqual(events[0]["name"] as? String, "app-opened")
        XCTAssertEqual(events[0]["atMs"] as? Int, 1500)
        // app-opened carries no fields at all — exactly name + atMs.
        XCTAssertEqual(events[0].count, 2)
        XCTAssertEqual(events[1]["name"] as? String, "send-started")
    }

    func testFieldCarryingEventEncodesItsFields() throws {
        let start = Date()
        var bodies: [Data] = []
        let telemetry = Telemetry(sessionStart: start, now: { start })
        telemetry.send = { body, done in bodies.append(body); done(.delivered) }

        telemetry.track(.locationResolved(elapsedMs: 5, source: .device, accuracyM: 7))
        telemetry.flush()

        let events = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: try XCTUnwrap(bodies.first)) as? [String: Any])?["events"] as? [[String: Any]]
        )
        XCTAssertEqual(events[0]["name"] as? String, "location-resolved")
        XCTAssertEqual(events[0]["elapsedMs"] as? Int, 5)
        XCTAssertEqual(events[0]["source"] as? String, "device")
        XCTAssertEqual(events[0]["accuracyM"] as? Int, 7)
    }

    func testAtMsIsClampedToADay() throws {
        let start = Date(timeIntervalSince1970: 0)
        var bodies: [Data] = []
        let telemetry = Telemetry(sessionStart: start, now: { start.addingTimeInterval(2 * 86_400) })
        telemetry.send = { body, done in bodies.append(body); done(.delivered) }

        telemetry.track(.appOpened)
        telemetry.flush()

        let events = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: try XCTUnwrap(bodies.first)) as? [String: Any])?["events"] as? [[String: Any]]
        )
        XCTAssertEqual(events[0]["atMs"] as? Int, 86_400_000)
    }

    // MARK: - Session

    func testSessionIs32LowercaseHexCharacters() {
        let session = Telemetry.newSessionID()
        XCTAssertEqual(session.count, 32)
        XCTAssertNil(session.range(of: "[^0-9a-f]", options: .regularExpression))
    }

    func testSessionIsFreshPerInstance() {
        // One instance per app LAUNCH, so two instances must never share a
        // session: the id is what makes the stream a timeline rather than a
        // tracker.
        XCTAssertNotEqual(Telemetry().sessionID, Telemetry().sessionID)
    }

    // MARK: - Batching

    func testFlushesWhenTheBufferReachesTheThreshold() {
        let start = Date()
        var bodies: [Data] = []
        let telemetry = Telemetry(sessionStart: start, now: { start })
        telemetry.send = { body, done in bodies.append(body); done(.delivered) }

        for _ in 0..<19 {
            telemetry.track(.appOpened)
        }
        XCTAssertTrue(bodies.isEmpty, "the buffer must hold until the threshold")
        telemetry.track(.appOpened)
        XCTAssertEqual(bodies.count, 1, "the 20th event must trigger a flush")
    }

    func testBatchNeverExceeds100AndDropsTheOldest() throws {
        let start = Date()
        var bodies: [Data] = []
        let telemetry = Telemetry(sessionStart: start, now: { start.addingTimeInterval(0.001) })
        telemetry.send = { body, done in bodies.append(body); done(.delivered) }
        telemetry.flushThreshold = .max

        // Distinct byte counts identify the order of the buffered events.
        for i in 0..<150 {
            telemetry.track(.photoCaptured(elapsedMs: i, bytes: i, mime: "image/jpeg"))
        }
        telemetry.flush()

        let events = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: try XCTUnwrap(bodies.first)) as? [String: Any])?["events"] as? [[String: Any]]
        )
        XCTAssertEqual(events.count, 100, "the relay refuses a batch longer than 100")
        XCTAssertEqual(events.first?["bytes"] as? Int, 50, "the oldest 50 must have been dropped")
        XCTAssertEqual(events.last?["bytes"] as? Int, 149)
    }

    func testConsecutiveDescriptionLengthsCoalesce() throws {
        let start = Date()
        var bodies: [Data] = []
        let telemetry = Telemetry(sessionStart: start, now: { start })
        telemetry.send = { body, done in bodies.append(body); done(.delivered) }

        // One event per keystroke would spam the relay; the buffer keeps the
        // latest length only.
        telemetry.track(.descriptionLength(length: 1))
        telemetry.track(.descriptionLength(length: 5))
        telemetry.track(.descriptionLength(length: 9))
        telemetry.flush()

        let events = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: try XCTUnwrap(bodies.first)) as? [String: Any])?["events"] as? [[String: Any]]
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["length"] as? Int, 9)
    }

    // MARK: - A batch the relay did not take

    /// #74, and the reason this section exists: the airplane-mode walk of the
    /// first iOS field test is missing from D1 entirely. The buffer was emptied
    /// before the request, the request failed, and a two-minute hole in the
    /// timeline is indistinguishable from a tester standing still.
    func testAnUndeliveredBatchIsKeptAndSentAgain() throws {
        let start = Date()
        var bodies: [Data] = []
        var outcome = Telemetry.BatchOutcome.undelivered
        let telemetry = Telemetry(sessionStart: start, now: { start })
        telemetry.send = { body, done in bodies.append(body); done(outcome) }

        telemetry.track(.categoryChosen(elapsedMs: 1, slug: "ruslafotur"))
        telemetry.track(.sendStarted)
        telemetry.flush()
        XCTAssertEqual(bodies.count, 1, "the first attempt is made")

        // The network came back, and nothing else happened in between.
        outcome = .delivered
        telemetry.flush()

        XCTAssertEqual(bodies.count, 2, "the failed batch is tried again")
        XCTAssertEqual(
            try names(in: bodies[1]),
            ["category-chosen", "send-started"],
            "and it carries the events the failed attempt held"
        )
    }

    func testARequeuedBatchStaysAheadOfWhatCameAfterIt() throws {
        let start = Date()
        var bodies: [Data] = []
        var outcome = Telemetry.BatchOutcome.undelivered
        let telemetry = Telemetry(sessionStart: start, now: { start })
        telemetry.send = { body, done in bodies.append(body); done(outcome) }

        telemetry.track(.sendStarted)
        telemetry.flush()

        // Buffered while the failed request was still out, so newer.
        telemetry.track(.screenLeft(screen: .confirm, completed: false))
        outcome = .delivered
        telemetry.flush()

        XCTAssertEqual(
            try names(in: bodies[1]),
            ["send-started", "screen-left"],
            "a batch put back is older than what arrived while it was in flight"
        )
    }

    /// The other half of the fix. A relay that refuses this body will refuse it
    /// again — the `noExif` bug 400'd every batch that contained one — so a
    /// rejected batch must be dropped or it blocks the buffer for the session.
    func testARejectedBatchIsDroppedRatherThanTriedForever() throws {
        let start = Date()
        var bodies: [Data] = []
        let telemetry = Telemetry(sessionStart: start, now: { start })
        telemetry.send = { body, done in bodies.append(body); done(.rejected) }

        telemetry.track(.appOpened)
        telemetry.flush()
        telemetry.flush()

        XCTAssertEqual(bodies.count, 1, "nothing was left to send")
    }

    func testStatusIsReadAsKeepOrDrop() {
        // The relay took it.
        XCTAssertEqual(Telemetry.outcome(forStatus: 200), .delivered)
        XCTAssertEqual(Telemetry.outcome(forStatus: 204), .delivered)
        // The relay refused this body and would refuse it again.
        XCTAssertEqual(Telemetry.outcome(forStatus: 400), .rejected)
        XCTAssertEqual(Telemetry.outcome(forStatus: 413), .rejected)
        // Try later: a timeout, a rate limit, or the relay being down.
        XCTAssertEqual(Telemetry.outcome(forStatus: 408), .undelivered)
        XCTAssertEqual(Telemetry.outcome(forStatus: 429), .undelivered)
        XCTAssertEqual(Telemetry.outcome(forStatus: 500), .undelivered)
        XCTAssertEqual(Telemetry.outcome(forStatus: 0), .undelivered)
    }

    /// Without this, every event past the threshold starts another post while
    /// offline, and a batch requeued underneath a later one duplicates it.
    func testOnlyOneBatchIsInFlightAtATime() throws {
        let start = Date()
        var bodies: [Data] = []
        var pending: [(Telemetry.BatchOutcome) -> Void] = []
        let telemetry = Telemetry(sessionStart: start, now: { start })
        telemetry.send = { body, done in bodies.append(body); pending.append(done) }

        telemetry.track(.appOpened)
        telemetry.flush()
        XCTAssertEqual(bodies.count, 1)

        telemetry.track(.sendStarted)
        telemetry.flush()
        XCTAssertEqual(bodies.count, 1, "the second flush waits for the first to answer")

        pending[0](.delivered)
        telemetry.flush()
        XCTAssertEqual(try names(in: bodies[1]), ["send-started"])
    }

    /// Dropping under the cap stays correct: the requeued batch is not
    /// privileged, and the oldest events still go when there are too many.
    func testTheCapStillAppliesToARequeuedBatch() throws {
        let start = Date()
        var bodies: [Data] = []
        var outcome = Telemetry.BatchOutcome.undelivered
        let telemetry = Telemetry(sessionStart: start, now: { start })
        telemetry.send = { body, done in bodies.append(body); done(outcome) }
        telemetry.flushThreshold = .max

        // Distinct byte counts identify the order of the buffered events.
        for i in 0..<100 {
            telemetry.track(.photoCaptured(elapsedMs: i, bytes: i, mime: "image/jpeg"))
        }
        telemetry.flush()
        for i in 100..<150 {
            telemetry.track(.photoCaptured(elapsedMs: i, bytes: i, mime: "image/jpeg"))
        }
        outcome = .delivered
        telemetry.flush()

        let events = try decodedEvents(in: bodies[1])
        XCTAssertEqual(events.count, 100)
        XCTAssertEqual(events.first?["bytes"] as? Int, 50, "the oldest 50 went, requeued or not")
        XCTAssertEqual(events.last?["bytes"] as? Int, 149)
    }

    // MARK: - Reading a body back

    private func decodedEvents(in body: Data) throws -> [[String: Any]] {
        try XCTUnwrap(
            (JSONSerialization.jsonObject(with: body) as? [String: Any])?["events"] as? [[String: Any]]
        )
    }

    private func names(in body: Data) throws -> [String] {
        try decodedEvents(in: body).map { $0["name"] as? String ?? "" }
    }

    // MARK: - The privacy test

    func testDescriptionTextNeverAppearsInTheBody() throws {
        let secret = "FULL RUSLAFATA VIÐ STÍGINN 83721"
        let start = Date()
        var bodies: [Data] = []
        let telemetry = Telemetry(sessionStart: start, now: { start })
        telemetry.send = { body, done in bodies.append(body); done(.delivered) }

        // The closest the app ever brings a description to this channel:
        // only its length is passed, never the text.
        telemetry.track(.descriptionLength(length: secret.count))
        telemetry.track(.categoryChosen(elapsedMs: 1, slug: "ruslafotur"))
        telemetry.flush()

        // Two unwraps, not one: `bodies.first` is optional and the String
        // initialiser is failable, so `.map` produces a String?? and a single
        // XCTUnwrap leaves an optional behind.
        let data = try XCTUnwrap(bodies.first)
        let body = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(body.contains(secret), "the description text must never reach the wire")
        // No description field exists anywhere in the contract; a stray one
        // would be rejected by the relay and is a privacy violation here.
        XCTAssertFalse(body.contains("\"description\""))
        // The length is the whole signal, and it is present.
        XCTAssertTrue(body.contains("\"length\":\(secret.count)"))
    }

    // MARK: - The contract cannot drift

    func testEventNamesMatchTheContractExactly() throws {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try ContractSource.dataFile("relay-events.json")) as? [String: Any]
        )
        let contractEvents = try XCTUnwrap(json["events"] as? [String: Any])
        XCTAssertEqual(Set(contractEvents.keys), Set(TelemetryEvent.allNames))
    }

    func testEventFieldsMatchTheContractExactly() throws {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try ContractSource.dataFile("relay-events.json")) as? [String: Any]
        )
        let contractEvents = try XCTUnwrap(json["events"] as? [String: Any])

        for name in TelemetryEvent.allNames {
            let contract = try XCTUnwrap(contractEvents[name] as? [String: Any], "contract names \(name)")
            let contractFields = Set(try XCTUnwrap(contract["fields"] as? [String: Any]).keys)
            let clientFields = Set(sampleEvent(forName: name).fields.keys)
            XCTAssertEqual(clientFields, contractFields, "field set for \(name) drifted from the contract")
        }
    }

    /// One representative event per name, used to pin the field sets. A new
    /// field on a case is a compile error here, which is the point: the drift
    /// is caught at build time, not by the relay's 400.
    private func sampleEvent(forName name: String) -> TelemetryEvent {
        switch name {
        case "app-opened": return .appOpened
        case "camera-permission": return .cameraPermission(granted: true)
        case "location-permission": return .locationPermission(granted: true)
        case "photo-captured": return .photoCaptured(elapsedMs: 0, bytes: 0, mime: "image/jpeg")
        case "location-resolved": return .locationResolved(elapsedMs: 0, source: .device, accuracyM: 0)
        case "location-failed": return .locationFailed(elapsedMs: 0, reason: .timeout)
        case "category-chosen": return .categoryChosen(elapsedMs: 0, slug: "ruslafotur")
        case "description-length": return .descriptionLength(length: 0)
        case "send-started": return .sendStarted
        case "send-result": return .sendResult(elapsedMs: 0, status: 200, ok: true)
        case "send-failed": return .sendFailed(elapsedMs: 0, reason: .connection)
        case "screen-left": return .screenLeft(screen: .camera, completed: true)
        default: XCTFail("unknown event name \(name)"); return .appOpened
        }
    }
}

// MARK: - The enum values themselves

/// The bug this file exists to prevent recurring.
///
/// The pinning tests above check event NAMES and FIELD KEYS. They passed while
/// `LocationFailure.noExif` went out as "noExif", because Swift's implicit raw
/// value is the case name and the contract says "no-exif". The relay 400s the
/// whole batch on an unknown enum value, and telemetry swallows its failures by
/// design, so the only symptom was that a class of event never appeared.
///
/// Kotlin cannot make this mistake: it spells every wire value explicitly. Swift
/// can, so Swift gets a test.
extension TelemetryTest {

    /// Every fixed-enum value the client can emit must be a value the contract
    /// names, and every value the contract names must be one the client can
    /// emit. Both directions: an unused contract value is dead vocabulary, and
    /// an unknown client value is a 400.
    func testEveryEnumValueMatchesTheContract() throws {
        let contract = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try ContractSource.dataFile("relay-events.json"))
                as? [String: Any]
        )
        let events = try XCTUnwrap(contract["events"] as? [String: Any])

        func contractValues(event: String, field: String) throws -> Set<String> {
            let spec = try XCTUnwrap(events[event] as? [String: Any], "no event \(event)")
            let fields = try XCTUnwrap(spec["fields"] as? [String: Any])
            return Set(try XCTUnwrap(fields[field] as? [String], "\(event).\(field) is not an enum"))
        }

        let client: [(event: String, field: String, values: Set<String>)] = [
            (
                "location-resolved", "source",
                Set([TelemetryEvent.LocationSource.device, .exif].map(\.rawValue))
            ),
            (
                "location-failed", "reason",
                Set([
                    TelemetryEvent.LocationFailure.permission, .timeout, .unavailable, .noExif,
                ].map(\.rawValue))
            ),
            (
                "send-failed", "reason",
                Set([
                    TelemetryEvent.SendFailure.connection, .timeout, .encoding, .other,
                ].map(\.rawValue))
            ),
            (
                "screen-left", "screen",
                Set([TelemetryEvent.Screen.camera, .details, .confirm].map(\.rawValue))
            ),
        ]

        for entry in client {
            XCTAssertEqual(
                entry.values,
                try contractValues(event: entry.event, field: entry.field),
                "\(entry.event).\(entry.field) disagrees with data/relay-events.json"
            )
        }
    }

    /// The mime normaliser must land on a value the contract names, whatever it
    /// is handed. An iPhone shooting HEIC is the case that matters (#28).
    func testNormalizedMimeAlwaysLandsOnAContractValue() throws {
        let contract = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try ContractSource.dataFile("relay-events.json"))
                as? [String: Any]
        )
        let events = try XCTUnwrap(contract["events"] as? [String: Any])
        let spec = try XCTUnwrap(events["photo-captured"] as? [String: Any])
        let fields = try XCTUnwrap(spec["fields"] as? [String: Any])
        let allowed = Set(try XCTUnwrap(fields["mime"] as? [String]))

        for raw in [
            "image/jpeg", "image/png", "image/gif", "image/heic",
            "image/heif", "application/pdf", "", "IMAGE/JPEG",
        ] {
            XCTAssertTrue(
                allowed.contains(Telemetry.normalizedMime(raw)),
                "normalizedMime(\(raw)) produced a value the relay would refuse"
            )
        }
    }
}
