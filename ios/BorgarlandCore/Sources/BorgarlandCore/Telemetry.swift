import Foundation
import Security

/// The client half of the telemetry channel, the counterpart of
/// android/.../net/Telemetry.kt. data/relay-events.json is the contract and
/// the allowlist that is the privacy boundary: every event name and every
/// field below is spelled there, the Worker rejects anything it does not
/// name, and there is deliberately no free-text field anywhere in that file.
///
/// The privacy rules this type exists to enforce:
///
///   1. No content ever. Only the contract's fields: numbers, booleans and
///      fixed enum values. `description-length` carries the LENGTH of what
///      was typed, never the text; `accuracyM` is a radius in whole metres,
///      never a position.
///   2. The session id is generated fresh per instance (per app LAUNCH in the
///      app) from a secure random source, is never persisted and is never
///      derived from a device/vendor/advertising identifier. It groups one
///      sitting and cannot follow a person between sessions.
///   3. Telemetry never affects the report. Every failure is swallowed, the
///      send is fire-and-forget off the UI thread, and nothing here can
///      block, delay or retry into a report send.
///   4. Batched, not spammed: the buffer flushes at ~20 events, at the
///      natural end points (the report send result, app background), and
///      never exceeds 100 per batch (the relay refuses a longer one).
///
/// Testable by injection: `send` is a closure a test replaces to capture the
/// body without a network, and `now`/`sessionStart`/`sessionID` are
/// constructor parameters so the envelope and the timing are deterministic.
public final class Telemetry {
    /// The app-wide instance. One instance = one session id, and the app
    /// creates exactly one of these per launch.
    public static let shared = Telemetry()

    // MARK: Configuration

    /// The app's own version string in the envelope's format, "0.1.0 (3)".
    /// The shell sets this at launch; the package cannot read the app's bundle.
    ///
    /// The default is a placeholder rather than an empty string on purpose. An
    /// empty value fails the relay's envelope check, so every batch would 400
    /// and, because telemetry swallows its failures, a shell that forgot to set
    /// this would produce silence indistinguishable from a tester who never
    /// opened the app. "unset" is accepted, lands in the data, and is
    /// diagnosable at a glance.
    public var appVersion = "unset"

    /// Injectable network send. A unit test replaces it to capture the body;
    /// nil means the default fire-and-forget URLSession post.
    public var send: ((Data) -> Void)?

    /// Flush when the buffer reaches this many events.
    public var flushThreshold = 20

    /// The relay refuses a batch longer than this (data/relay-events.json).
    public var maxBatch = 100

    // MARK: Session

    /// Fresh per launch, 32 lowercase hex characters, never persisted.
    public let sessionID: String
    /// The moment the session started; `atMs` is the offset from here.
    public let sessionStart: Date
    /// The clock, injectable so tests control `atMs` deterministically.
    public let now: () -> Date

    // MARK: State

    private var buffer: [BufferedEvent] = []
    private let lock = NSLock()

    private struct BufferedEvent {
        let event: TelemetryEvent
        /// Milliseconds since `sessionStart`, recorded when the event
        /// happened (not at flush time: a batch must carry each event's own
        /// moment).
        let atMs: Int
    }

    public init(
        sessionID: String = Telemetry.newSessionID(),
        sessionStart: Date = Date(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.sessionID = sessionID
        self.sessionStart = sessionStart
        self.now = now
    }

    /// 32 lowercase hex characters from the system's secure random source.
    public static func newSessionID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "secure random is unavailable")
        return bytes.map { String(format: "%02x", Int($0)) }.joined()
    }

    /// The contract's mime enum, with an `other` fallback for anything the
    /// contract does not name.
    public static func normalizedMime(_ raw: String) -> String {
        ["image/jpeg", "image/png", "image/gif", "image/heic"].contains(raw) ? raw : "other"
    }

    /// Records an event. Never throws and never blocks on the network: the
    /// buffer is capped, the flush is fire-and-forget.
    public func track(_ event: TelemetryEvent) {
        let atMs = clamp(Int(now().timeIntervalSince(sessionStart) * 1000))
        var shouldFlush = false
        lock.lock()
        // description-length is emitted on every keystroke; coalesce
        // consecutive ones so a long description keeps one event, not one per
        // character. Every other event fires at a discrete moment.
        if case .descriptionLength = event,
           case .descriptionLength? = buffer.last?.event {
            buffer.removeLast()
        } else if buffer.count >= maxBatch {
            // The relay refuses an over-long batch rather than truncating it,
            // so the oldest events go instead. This is instrumentation, not
            // the report: dropping is correct, blocking is not.
            buffer.removeFirst()
        }
        buffer.append(BufferedEvent(event: event, atMs: atMs))
        shouldFlush = buffer.count >= flushThreshold
        lock.unlock()
        if shouldFlush { flush() }
    }

    /// Sends whatever is buffered, if anything. Safe to call from anywhere
    /// and any thread; the network send itself never blocks the caller.
    public func flush() {
        let batch: [BufferedEvent]
        lock.lock()
        if buffer.count > maxBatch {
            buffer.removeFirst(buffer.count - maxBatch)
        }
        batch = buffer
        buffer = []
        lock.unlock()

        guard !batch.isEmpty, let body = encode(batch) else { return }
        (send ?? httpSend)(body)
    }

    // MARK: Encoding

    /// The envelope from data/relay-events.json: session, platform, the
    /// app's version string, and the events — each `{ name, atMs, ...fields }`
    /// with the fields flattened to the top level, exactly as the Worker
    /// validates them.
    private func encode(_ batch: [BufferedEvent]) -> Data? {
        let envelope: [String: Any] = [
            "session": sessionID,
            "platform": "ios",
            "appVersion": appVersion,
            "events": batch.map { buffered in
                var object: [String: Any] = ["name": buffered.event.name, "atMs": buffered.atMs]
                for (key, value) in buffered.event.fields {
                    object[key] = value
                }
                return object
            },
        ]
        guard JSONSerialization.isValidJSONObject(envelope) else { return nil }
        return try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    // MARK: Transport

    /// The relay host comes from BorgarlandCore.RelayEndpoint, exactly like
    /// RelayClient (#29): the loopback for debug builds (adb reverse / the
    /// local tunnel), the deployed https host for release. No literal here.
    private var baseURL: String {
        #if DEBUG
        return RelayEndpoint.development
        #else
        return RelayEndpoint.production
        #endif
    }

    /// Fire and forget: a dataTask posts the body and nobody looks at the
    /// answer. Errors are swallowed by design — if the relay is down the user
    /// must not notice (data/relay-events.json, endpoint.notes).
    private func httpSend(_ body: Data) {
        guard let url = URL(string: baseURL + "/api/events") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    /// A day in milliseconds; an offset beyond that is a broken clock, not a
    /// session (the Worker's own bound).
    private func clamp(_ ms: Int) -> Int {
        max(0, min(ms, 86_400_000))
    }
}

/// One event this client can emit. The cases, the names and the fields are
/// exactly data/relay-events.json: TelemetryTest pins the full set against
/// the file so the client and the contract cannot drift. The constrained
/// value enums below are the contract's fixed enums, spelled once.
public enum TelemetryEvent {
    case appOpened
    case cameraPermission(granted: Bool)
    case locationPermission(granted: Bool)
    case photoCaptured(elapsedMs: Int, bytes: Int, mime: String)
    case locationResolved(elapsedMs: Int, source: LocationSource, accuracyM: Int)
    case locationFailed(elapsedMs: Int, reason: LocationFailure)
    case categoryChosen(elapsedMs: Int, slug: String)
    case descriptionLength(length: Int)
    case sendStarted
    case sendResult(elapsedMs: Int, status: Int, ok: Bool)
    case sendFailed(elapsedMs: Int, reason: SendFailure)
    case screenLeft(screen: Screen, completed: Bool)

    public enum LocationSource: String {
        case device
        case exif
    }

    public enum LocationFailure: String {
        case permission
        case timeout
        case unavailable
        // Spelled out. Swift's implicit raw value is the CASE name, so this
        // was "noExif" on the wire while the contract says "no-exif", and the
        // relay 400s the whole batch. Silently, because telemetry swallows its
        // failures by design. TelemetryTest now pins every value in this file
        // against the contract for exactly this reason.
        case noExif = "no-exif"
    }

    public enum SendFailure: String {
        case connection
        case timeout
        case encoding
        case other
    }

    public enum Screen: String {
        case camera
        case details
        /// `confirm`, not `summary`: the city has a payload field by that name
        /// and NoCityEndpointTest forbids the library from spelling one. The
        /// app's screen is still called SummaryScreen; only the wire word moved.
        case confirm
    }

    /// The wire name.
    public var name: String {
        switch self {
        case .appOpened: return "app-opened"
        case .cameraPermission: return "camera-permission"
        case .locationPermission: return "location-permission"
        case .photoCaptured: return "photo-captured"
        case .locationResolved: return "location-resolved"
        case .locationFailed: return "location-failed"
        case .categoryChosen: return "category-chosen"
        case .descriptionLength: return "description-length"
        case .sendStarted: return "send-started"
        case .sendResult: return "send-result"
        case .sendFailed: return "send-failed"
        case .screenLeft: return "screen-left"
        }
    }

    /// The contract's fields for this event, and nothing else. No content
    /// ever passes through here: every value is a number, a boolean or a
    /// fixed enum value, which is the whole point of the allowlist.
    public var fields: [String: Any] {
        switch self {
        case .appOpened:
            return [:]
        case .cameraPermission(let granted):
            return ["granted": granted]
        case .locationPermission(let granted):
            return ["granted": granted]
        case .photoCaptured(let elapsedMs, let bytes, let mime):
            return ["elapsedMs": elapsedMs, "bytes": bytes, "mime": mime]
        case .locationResolved(let elapsedMs, let source, let accuracyM):
            return ["elapsedMs": elapsedMs, "source": source.rawValue, "accuracyM": accuracyM]
        case .locationFailed(let elapsedMs, let reason):
            return ["elapsedMs": elapsedMs, "reason": reason.rawValue]
        case .categoryChosen(let elapsedMs, let slug):
            return ["elapsedMs": elapsedMs, "slug": slug]
        case .descriptionLength(let length):
            return ["length": length]
        case .sendStarted:
            return [:]
        case .sendResult(let elapsedMs, let status, let ok):
            return ["elapsedMs": elapsedMs, "status": status, "ok": ok]
        case .sendFailed(let elapsedMs, let reason):
            return ["elapsedMs": elapsedMs, "reason": reason.rawValue]
        case .screenLeft(let screen, let completed):
            return ["screen": screen.rawValue, "completed": completed]
        }
    }

    /// The full set of event names this client can emit, in the contract
    /// file's order. TelemetryTest asserts this equals the `events` keys of
    /// data/relay-events.json, so a drift in either direction is a red build.
    public static let allNames: [String] = [
        "app-opened",
        "camera-permission",
        "location-permission",
        "photo-captured",
        "location-resolved",
        "location-failed",
        "category-chosen",
        "description-length",
        "send-started",
        "send-result",
        "send-failed",
        "screen-left",
    ]
}
