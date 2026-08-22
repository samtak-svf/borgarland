import XCTest
@testable import BorgarlandCore

/// The guard behind #29: a release build must not be able to carry a loopback
/// URL. These assertions are what make that a build failure rather than a
/// discovery on a tester's phone.
final class RelayEndpointTest: XCTestCase {
    func testProductionIsHttps() {
        XCTAssertTrue(
            RelayEndpoint.production.hasPrefix("https://"),
            "the deployed relay must be https; cleartext is permitted only to the loopback"
        )
    }

    func testProductionIsNotLoopback() {
        // The whole failure this file exists to prevent: on a phone, these
        // hosts are the phone.
        for loopback in ["127.0.0.1", "localhost", "::1", "0.0.0.0"] {
            XCTAssertFalse(
                RelayEndpoint.production.contains(loopback),
                "the deployed relay must not be \(loopback): on a real device that is the device"
            )
        }
    }

    func testNeitherEndpointCarriesAPath() {
        // The path comes from data/relay-request.json and is appended by the
        // client. A trailing slash or a baked-in path would produce
        // //api/reports, which the Worker answers with a 404.
        for endpoint in [RelayEndpoint.development, RelayEndpoint.production] {
            XCTAssertFalse(endpoint.hasSuffix("/"), "\(endpoint) must not end in a slash")
            let afterScheme = endpoint.drop(while: { $0 != "/" }).dropFirst(2)
            XCTAssertFalse(afterScheme.contains("/"), "\(endpoint) must be a host, not a path")
        }
    }

    func testDevelopmentIsTheLoopbackAppTransportSecurityPermits() {
        // Info.plist allows cleartext to local networking only, so a
        // development value that is not the loopback would be blocked at
        // runtime with an error that does not name this setting.
        XCTAssertTrue(RelayEndpoint.development.contains("127.0.0.1"))
    }
}
