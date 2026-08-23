import Foundation

/// One thing to say to a person about what the relay answered.
public struct RelayOutcome: Decodable, Equatable {
    /// What happened, in one sentence.
    public let says: String
    /// What they can do about it, when there is anything. Often there is not,
    /// and a made-up suggestion is worse than none.
    public let advice: String?

    public init(says: String, advice: String?) {
        self.says = says
        self.advice = advice
    }
}

/// Our words for what the relay answered, from data/relay-outcomes.json.
///
/// A sibling of CategoryLabels and separate from Facts for the same reason: the
/// facts file records what the city says, this one is what WE say to a person.
/// The relay's own answer is not replaced by any of this — it stays on the
/// screen, behind a control the person opens on purpose (#77).
///
/// No Icelandic sentence appears in this file. That is deliberate and it is why
/// `sentence` returns an Optional rather than falling back to something written
/// here: a second place for our words to live is a second place for them to
/// drift, and a screen with no sentence still has the relay's own answer on it.
public struct RelayOutcomesFile: Decodable, Equatable {
    /// The relay sent it to the city and the city took it.
    public let sent: RelayOutcome
    /// The relay took it and forwarded nothing, which is the state it is in
    /// today and will be in for every test build.
    public let dryRun: RelayOutcome
    /// Nobody answered at all.
    public let noAnswer: RelayOutcome
    /// The relay answered with a code this file does not name. Should be
    /// unreachable — worker/tests/outcomes.test.ts fails the build when the
    /// relay can return a code with no sentence — and exists because "should
    /// be unreachable" is not a thing to show somebody raw JSON over.
    public let unknown: RelayOutcome
    /// One entry per error code the relay can answer with.
    public let outcomes: [String: RelayOutcome]
}

public enum RelayOutcomes {

    /// The two things an app needs out of a relay answer, without modelling the
    /// rest of it. The rest is the relay's internal state machine — the stored
    /// row, the follow-through fields, the whole city payload — and an app that
    /// parsed it would be coupled to every one of them.
    public struct Answer: Equatable {
        public let errorCode: String?
        public let dryRun: Bool?

        public init(errorCode: String?, dryRun: Bool?) {
            self.errorCode = errorCode
            self.dryRun = dryRun
        }
    }

    public static func parse(_ data: Data) throws -> RelayOutcomesFile {
        try JSONDecoder().decode(RelayOutcomesFile.self, from: data)
    }

    /// Reads a relay answer. A body that is not JSON, or is JSON of some other
    /// shape, answers nil to both questions rather than throwing: this runs on
    /// the failure path, where the thing least worth doing is failing again.
    public static func read(_ body: String) -> Answer {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Answer(errorCode: nil, dryRun: nil)
        }
        let report = object["report"] as? [String: Any]
        return Answer(errorCode: object["error"] as? String, dryRun: report?["dryRun"] as? Bool)
    }

    /// What to tell the person, or nil when the file is not there to say it.
    ///
    /// `status` is 0 when nothing answered, matching the transport's own
    /// convention on both platforms.
    public static func sentence(status: Int, body: String, in file: RelayOutcomesFile?) -> RelayOutcome? {
        guard let file else { return nil }
        if status == 0 { return file.noAnswer }
        let answer = read(body)
        if (200..<300).contains(status) {
            return answer.dryRun == true ? file.dryRun : file.sent
        }
        if let code = answer.errorCode, let known = file.outcomes[code] { return known }
        return file.unknown
    }
}
