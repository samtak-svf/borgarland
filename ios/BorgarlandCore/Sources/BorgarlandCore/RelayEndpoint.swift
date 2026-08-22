import Foundation

/// Where the relay lives, per build (#29).
///
/// This is the counterpart of `BuildConfig.RELAY_BASE_URL` in
/// android/app/build.gradle.kts, and it exists for the same reason: a release
/// build that carries the loopback is dead in the field. On a real phone
/// `127.0.0.1` is the phone itself, so every send fails with a connection
/// refused, and nothing in a test or a CI run notices — the app builds, runs,
/// photographs and locates, and only the last step fails, on someone else's
/// device.
///
/// Both values live here rather than at the call site so that
/// `RelayEndpointTest` can assert the production one is a real https host. A
/// `#if DEBUG` around a pair of string literals is not testable; this is.
public enum RelayEndpoint {
    /// Development. The POC reaches the development machine over a loopback
    /// tunnel, which is also the only host
    /// `NSAppTransportSecurity.NSAllowsLocalNetworking` permits in cleartext.
    public static let development = "http://127.0.0.1:8787"

    /// The deployed relay. A custom domain on the Cloudflare Worker rather
    /// than the implicit *.workers.dev name, because this string is compiled
    /// into a release: moving off it later costs an App Store review before
    /// anyone can report anything (worker/wrangler.jsonc carries the route).
    public static let production = "https://borgarland.samtak.is"
}
