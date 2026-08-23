import Foundation
import CoreLocation

/// Fallback location source for a photo that carries no EXIF GPS. The
/// CoreLocation counterpart of DeviceFix.kt.
///
/// The Android version asks every enabled provider, not just GPS, because
/// GPS never fixes under a roof and most reports are made in a courtyard,
/// under trees or beside a tall building, where the network or fused
/// providers are holding a recent fix. CoreLocation has no provider list, so
/// the equivalent is: accept the fix the system is already holding when it is
/// recent enough to still describe where the reporter is standing, and
/// otherwise request one with a timeout, taking whichever source answers.
///
/// A coarse answer is accepted rather than refused: desiredAccuracy is a
/// hundred metres, not best. Returns nil only when nothing answers in time,
/// and the caller then refuses to continue rather than sending a report
/// nobody can act on.
@MainActor
final class DeviceFix: NSObject, CLLocationManagerDelegate {
    /// Shared because CLLocationManager wants a long-lived delegate, and
    /// because the system keeps a manager's cached fix warm between requests.
    static let shared = DeviceFix()

    private let manager = CLLocationManager()
    private var liveContinuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var authorizationContinuation: CheckedContinuation<Bool, Never>?

    // Internal, not private: an override cannot be less accessible than the
    // inherited initializer, and the singleton above is the only instance
    // the app ever holds.
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// The instance property, not the class method of the same name: the
    /// class method has been deprecated since iOS 14 and reports the app's
    /// status rather than this manager's.
    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        default:
            return false
        }
    }

    /// How old a cached fix may be and still answer for where the reporter is
    /// standing. Two minutes is roughly a city block at walking pace, which is
    /// the resolution this whole app is about; the Android side gets the same
    /// property for free because it reads the system's own last-known fix on
    /// every call rather than remembering one.
    private static let staleAfter: TimeInterval = 120

    /// Denied or restricted: the system will not prompt for this again, and
    /// the only place the decision can be undone is the Settings app.
    ///
    /// Deliberately not the same question as `!isAuthorized`, which is also
    /// true before anyone has been asked. Confusing the two is what put a
    /// Reyna aftur button in front of a permission that could never say yes
    /// to it (#76).
    var isDenied: Bool {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    /// The permission dance the Android launcher performs. Returns true when
    /// already authorized, prompts for whenInUse when undetermined, and
    /// reports the denial otherwise. A caller that shows something to a person
    /// on a false answer must ask `isDenied` too: the two refusals look the
    /// same here and are not the same situation.
    func requestWhenInUseAuthorization() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return false
        }
    }

    /// A fix, or nil after the timeout.
    ///
    /// The shortcut reads `manager.location`, the fix the system already
    /// holds, and only when it is recent. An earlier draft cached the first
    /// delivery in a property and returned it forever, which is wrong in a way
    /// that matters here specifically: a second report in the same session
    /// would carry the coordinate of the first one, and this app exists
    /// because the coordinate is where the thing is. The Kotlin has no such
    /// bug because it re-reads the providers' own last-known fix each time
    /// rather than remembering one.
    ///
    /// The full CLLocation is returned, not just the coordinate, because the
    /// telemetry channel reports the fix's radius (`accuracyM` in
    /// data/relay-events.json): horizontalAccuracy is part of the same answer.
    func request(timeout: TimeInterval = 15) async -> CLLocation? {
        if let cached = manager.location,
           Date().timeIntervalSince(cached.timestamp) < Self.staleAfter {
            return cached
        }
        manager.startUpdatingLocation()
        defer { manager.stopUpdatingLocation() }

        // Resumed exactly once: resumeFix nils the continuation before
        // resuming, so whichever path wins (a delivery or the timeout)
        // leaves nothing for the other to resume. Everything runs on the
        // main actor, so the continuation is never touched concurrently.
        let fix = await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            liveContinuation = continuation
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.resumeFix(nil)
            }
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        return fix
    }

    private func resumeFix(_ location: CLLocation?) {
        guard let continuation = liveContinuation else { return }
        liveContinuation = nil
        continuation.resume(returning: location)
    }

    // The delegate methods are nonisolated because the protocol is: a
    // MainActor-isolated conformance is a warning today and an error in the
    // Swift 6 language mode. CoreLocation delivers callbacks on the queue the
    // manager was created on, and this manager is created on the main actor,
    // so assumeIsolated states a fact rather than hoping for one. It is also
    // synchronous, which matters: hopping through a Task would let a delivery
    // and the timeout both see a live continuation.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            resumeFix(location)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard let continuation = authorizationContinuation else { return }
            authorizationContinuation = nil
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                continuation.resume(returning: true)
            default:
                continuation.resume(returning: false)
            }
        }
    }
}
