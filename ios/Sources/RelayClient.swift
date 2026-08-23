import Foundation
import BorgarlandCore

/// Posts a report to OUR relay. Never to the city.
///
/// Decision 0002: the apps post to our relay, never to the city directly.
/// That is why there is no city hostname anywhere in this app. The relay's own
/// host is not a literal here at all any more: both candidates live in
/// BorgarlandCore.RelayEndpoint and this file only selects between them. The
/// relay decides whether anything is forwarded, and it does so in dry run by
/// default, on infrastructure we can fix with a deploy rather than an App
/// Store review.
///
/// The request shape comes from data/relay-request.json: the multipart body
/// is built byte for byte by BorgarlandCore.MultipartBodyBuilder, pinned by
/// the package's own test against the Kotlin reference. This file is only
/// the transport — the URL, the method and path from the contract, the
/// boundary in the Content-Type header, timeouts, and the result tuple.
enum RelayClient {
    /// Where the relay lives for this build. Both values, and the assertions
    /// that keep the release one from being a loopback, are in
    /// BorgarlandCore.RelayEndpoint (#29).
    #if DEBUG
    static let baseURL = RelayEndpoint.development
    #else
    static let baseURL = RelayEndpoint.production
    #endif

    /// Our own session, because the shared one's defaults are not the promise
    /// this app makes.
    ///
    /// `URLRequest.timeoutInterval` is a per-request IDLE timeout, not a
    /// ceiling on the operation, and a request that restarts on a network
    /// change starts its idle clock again. That is not a theory: the first iOS
    /// field test set a phone to airplane mode, pressed send with 30 written
    /// on line 56, and the failure arrived at **84.1 seconds** (#73). The one
    /// that bounds the whole operation is `timeoutIntervalForResource`, and
    /// nothing was setting it.
    ///
    /// 60 rather than 30 for the ceiling: the body carries a photograph of a
    /// few megabytes and a slow-but-working upload is not a failure. What made
    /// 84 seconds unbearable was not its length but that the screen was dead
    /// for all of it, and that the report died with the attempt. Both of those
    /// are fixed where they belong — a cancel control and a queue — leaving
    /// this number free to be generous to a bad connection.
    ///
    /// `waitsForConnectivity` is false, which is the default, stated because it
    /// is now a decision: with a queue behind it, failing at once and waiting
    /// for a better moment is better than holding someone at a spinner.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    struct Result {
        /// Why a non-HTTP failure happened, when it did. Feeds the telemetry
        /// channel's `send-failed` reason (data/relay-events.json); nil means
        /// the relay answered, whatever the status.
        enum Failure: Equatable {
            case connection
            case timeout
            case encoding
            case cancelled
            case other
        }

        let ok: Bool
        let status: Int
        let body: String
        let failure: Failure?
    }

    static func send(payload: Payload, contract: RelayRequestFile) async -> Result {
        let boundary = "----borgarland\(Int(Date().timeIntervalSince1970 * 1000))"
        guard let url = URL(string: baseURL + contract.endpoint.path) else {
            return Result(ok: false, status: 0, body: "ógilt vistfang", failure: .other)
        }
        var request = URLRequest(url: url)
        request.httpMethod = contract.endpoint.method
        // The Kotlin splits this into connect (10 s) and read (30 s)
        // timeouts; URLRequest has one per-request idle timeout, so the read
        // value is the one that survives here. Set explicitly rather than left
        // to the session: a request's own timeoutInterval OVERRIDES the
        // configuration's, and its default is 60, so omitting this line would
        // quietly double the idle timeout the app promises.
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        do {
            let body = try MultipartBodyBuilder.buildBody(payload: payload, contract: contract, boundary: boundary)
            let (data, response) = try await session.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8) ?? ""
            return Result(ok: (200...299).contains(status), status: status, body: text, failure: nil)
        } catch {
            // The Kotlin maps any exception to status 0; the model renders
            // that as "could not reach the relay". The failure class is for
            // the telemetry channel only and never changes the report path.
            return Result(
                ok: false,
                status: 0,
                body: error.localizedDescription,
                failure: Self.classify(error)
            )
        }
    }

    /// The telemetry contract's send-failed reasons (connection, timeout,
    /// encoding, other), mapped from the transport error. Approximate by
    /// nature — the goal is a signal, not a network diagnostic.
    private static func classify(_ error: Error) -> Result.Failure {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return .other }
        switch ns.code {
        case NSURLErrorTimedOut:
            return .timeout
        case NSURLErrorCancelled:
            // Someone pressed the cancel control. The caller checks
            // Task.isCancelled and never reports this as a failure; the value
            // is here so the switch does not silently call it `other`.
            return .cancelled
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost,
             NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed:
            return .connection
        default:
            return .other
        }
    }
}
