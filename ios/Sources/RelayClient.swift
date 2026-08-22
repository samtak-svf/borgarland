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

    struct Result {
        let ok: Bool
        let status: Int
        let body: String
    }

    static func send(payload: Payload, contract: RelayRequestFile) async -> Result {
        let boundary = "----borgarland\(Int(Date().timeIntervalSince1970 * 1000))"
        guard let url = URL(string: baseURL + contract.endpoint.path) else {
            return Result(ok: false, status: 0, body: "ógilt vistfang")
        }
        var request = URLRequest(url: url)
        request.httpMethod = contract.endpoint.method
        // The Kotlin splits this into connect (10 s) and read (30 s)
        // timeouts; URLRequest has one per-request idle timeout, so the read
        // value is the one that survives here.
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        do {
            let body = try MultipartBodyBuilder.buildBody(payload: payload, contract: contract, boundary: boundary)
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8) ?? ""
            return Result(ok: (200...299).contains(status), status: status, body: text)
        } catch {
            // The Kotlin maps any exception to status 0; the model renders
            // that as "could not reach the relay".
            return Result(ok: false, status: 0, body: error.localizedDescription)
        }
    }
}
