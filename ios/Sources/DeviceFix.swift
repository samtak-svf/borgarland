import Foundation
import CoreLocation
import BorgarlandCore

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
    /// Every caller waiting on the same dialog. A single slot stranded the
    /// earlier caller for the life of the process, and the poll that guarded
    /// it answered the later one without waiting (#139).
    private var authorizationWaiters: [CheckedContinuation<Bool, Never>] = []

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
    ///
    /// It waits for as long as the person takes. It used to give up after a
    /// minute and call that a refusal (#134); see the note at the prompt.
    func requestWhenInUseAuthorization() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            // A second caller joins the queue instead of prompting again or
            // clobbering the first. What stood here before was a single slot
            // guarded by a 10 Hz poll, and both halves were wrong. The slot
            // stranded the earlier caller for the life of the process. The
            // poll, once #134 removed the sixty-second bound below, could spin
            // forever -- and when it did stop it returned `isAuthorized`, which
            // is false while the dialog is still on the screen. That is #134
            // exactly, one call further out: an unanswered permission reported
            // as a refusal.
            //
            // The comment those lines carried said the second caller was
            // reachable because the retry control stays tappable during the
            // dialog. It is not: an iOS permission alert is modal, so nothing
            // behind it can be tapped. The path is latent, and a queue costs
            // nothing to make it correct rather than arguing about whether it
            // can be entered.
            let alreadyAsking = !authorizationWaiters.isEmpty
            // NO TIME BOUND, deliberately (#134). There used to be one: sixty
            // seconds, and on expiry it resumed with `isAuthorized`, which is
            // false for `.notDetermined` -- a dialog still on the screen. A
            // tester spent about a hundred seconds reading it, was told the
            // permission was missing, answered it thirty-eight seconds after
            // the app had already decided she had refused, and then had to
            // press Reyna aftur to get the coordinate she had just granted.
            //
            // The bound cannot be repaired by making it longer, because the
            // failure is not the length: it is answering a question nobody has
            // answered yet. This is the same `unanswered != refused` confusion
            // as #76 and #86, and the guard forty lines below already gets it
            // right for the delegate path.
            //
            // Nothing is lost by waiting. iOS shows this dialog once in the
            // life of an install, so there is no second prompt to protect and
            // nothing to give up on; `locationManagerDidChangeAuthorization`
            // resumes whenever the answer comes. Android has never had a bound
            // here either -- its launcher callback simply fires when the person
            // answers -- so removing it closes a divergence rather than opening
            // one. If somebody never answers at all, every waiter stays
            // suspended for the life of the process. That is a parked task and
            // not a spinning one, which is the whole difference from the poll
            // this branch used to run (#139).
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                authorizationWaiters.append(continuation)
                guard !alreadyAsking else { return }
                // Emitted HERE, in the one branch that puts a dialog up, and
                // once per dialog rather than once per caller (#139). The
                // caller cannot know: it sees `needsLocationPermission`, which
                // is true for every photo carrying no usable EXIF GPS, while
                // every settled status above returns without showing
                // anything. Emitting there recorded an event that did not
                // happen on every report after the first answered one, and the
                // gap between being asked and answering -- the one measurement
                // #134 exists to make possible -- filled with milliseconds that
                // were never waits. data/relay-events.json already says "the
                // dialog was put up"; this is the line that makes that true.
                Telemetry.shared.track(.locationPermissionAsked)
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return false
        }
    }

    /// Each waiter is resumed exactly once, on the same pattern as `resumeFix`:
    /// the queue is emptied before anything is resumed, so a re-entrant
    /// delegate callback finds nothing left to resume twice.
    ///
    /// All of them get the same answer, because there was only ever one dialog
    /// and one person answering it.
    private func resumeAuthorization(_ granted: Bool) {
        guard !authorizationWaiters.isEmpty else { return }
        let waiting = authorizationWaiters
        authorizationWaiters = []
        for continuation in waiting {
            continuation.resume(returning: granted)
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
            // `notDetermined` is not an answer, and treating it as one is #86.
            // This delegate is called when the location manager is CREATED as
            // well as when authorization changes, and the instance is created
            // lazily by the very call that then sets the continuation — so the
            // creation callback can arrive after it, find it, and report a
            // refusal nobody gave. Both field testers were told the permission
            // was missing 37 and 118 ms after their photograph, while the
            // dialog asking for it was still on their screen.
            guard manager.authorizationStatus != .notDetermined else { return }
            resumeAuthorization(isAuthorized)
        }
    }
}
