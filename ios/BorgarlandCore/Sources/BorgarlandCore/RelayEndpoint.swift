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
///
/// **The loopback does not exist in a release build.** That is what `#if DEBUG`
/// below buys, and it is worth more than it looks:
///
///   - It makes the artifact check decisive. Build 2 was inspected with
///     `strings` and contained BOTH hosts, because both were unconditional
///     public constants, so the inspection could not say which one the app
///     would actually use. A release binary now contains one host, and finding
///     `127.0.0.1` in it is proof of a defect rather than noise.
///   - It turns a wrong `#if` in RelayClient into a compile error. Previously,
///     inverting that switch shipped the loopback again with every test still
///     green, because the tests assert these constants and never the selection
///     between them. Now the release build simply fails to find the symbol,
///     which is the same guarantee android/app/build.gradle.kts gives.
public enum RelayEndpoint {
    #if DEBUG
    /// Development. The POC reaches the development machine over a loopback
    /// tunnel, which is also the only host
    /// `NSAppTransportSecurity.NSAllowsLocalNetworking` permits in cleartext.
    /// Compiled only into a debug build; see the note above.
    public static let development = "http://127.0.0.1:8787"
    #endif

    /// The deployed relay. A custom domain on the Cloudflare Worker rather
    /// than the implicit *.workers.dev name, because this string is compiled
    /// into a release: moving off it later costs an App Store review before
    /// anyone can report anything (worker/wrangler.jsonc carries the route).
    public static let production = "https://borgarland.samtak.is"
}
