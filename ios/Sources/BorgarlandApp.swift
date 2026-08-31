import SwiftUI
import UIKit
import FirebaseCore
import BorgarlandCore

/// The shell around BorgarlandCore, mirroring MainActivity.kt: the facts
/// file decides whether the app exists at all, and the screen is a `switch`
/// on a sealed enum rather than a navigation stack. Portrait and
/// single-window are enforced by the Info.plist (project.yml), not here.
///
/// No explicit `@MainActor`: the `App` protocol already carries it, so the
/// `@StateObject` can hold the MainActor-isolated model without help. Stating
/// it again is a second place for the two to disagree.
@main
struct BorgarlandApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = ReportModel()

    /// Crashlytics, and nothing else from Firebase. A crash on a tester's phone
    /// is the one failure this app cannot report on its own: our own
    /// instrumentation posts to the relay, and a process that has just died
    /// posts nothing.
    ///
    /// The project is `borgarland-app` on the personal Google account, the same
    /// owner as the Worker and its D1. Not the party's Firebase project, which
    /// is where Rósa Parks still sends its crashes: this is a Samtak svf. app
    /// and its data should not sit on Sósíalistaflokkurinn infrastructure (#37).
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let factsError = model.state.factsError {
                    // Same as the Android shell: a missing or unparseable
                    // facts file is a show-stopper, never a fallback list.
                    Text(factsError)
                        .foregroundStyle(.red)
                        .padding(16)
                } else {
                    switch model.state.screen {
                    case .onboarding:
                        OnboardingScreen(model: model)
                    case .camera:
                        CameraScreen(model: model)
                    case .details:
                        DetailsScreen(model: model)
                    case .summary:
                        // payload() re-checks the same guards that got us
                        // here (a category and a coordinate), so it cannot
                        // be nil on this screen; the shell just refuses to
                        // render if it ever were.
                        if let payload = model.payload() {
                            SummaryScreen(model: model, payload: payload)
                        }
                    }
                }
            }
            // One of the telemetry channel's natural flush points: the buffer
            // goes out when the app leaves the foreground, so a session that
            // ends in the background is not lost (data/relay-events.json).
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    flushBeforeSuspending()
                }
                if phase == .active {
                    // The second retry trigger for a queued report (#73). The
                    // first is the path monitor in the model, and it only
                    // notices a NETWORK coming back — a relay that was down
                    // while the phone had signal gives it nothing to see.
                    model.deliverQueued()
                    // And the way back from the Settings app, which is the only
                    // place a denied location permission can be opened (#76).
                    model.recheckLocationPermission()
                    // The follow-up question (#57): asked on every foreground
                    // so a report that passes its fourteenth day while the app
                    // is backgrounded is not missed, and delivered answers
                    // that failed to reach the relay are retried.
                    model.refreshFollowUp()
                    model.deliverOutcomes()
                }
            }
            // The follow-up question, asked once about one report this phone
            // filed a fortnight ago (#57, decision 0013). It sits over
            // whatever screen is showing because it is not part of filing a
            // report; it is a different conversation that happens to start
            // when the app opens. ABOVE the factsError branch, so a missing
            // facts file cannot swallow it (the Android shell says the same
            // about its own overlay).
            .alert(
                "Var þetta lagað?",
                isPresented: Binding(
                    get: { model.state.followUp != nil },
                    set: { if !$0 { model.dismissFollowUp() } }
                ),
                presenting: model.state.followUp
            ) { pending in
                Button("Já") { model.answerFollowUp(fixed: true) }
                Button("Nei") { model.answerFollowUp(fixed: false) }
                Button("Sleppa", role: .cancel) { model.dismissFollowUp() }
            } message: { pending in
                Text(
                    "Þú sendir inn ábendingu um \(model.state.categoryDisplay[pending.categorySlug] ?? pending.categorySlug) fyrir tveimur vikum. Var vandamálið lagað?"
                )
            }
        }
    }

    /// The background flush, with an execution window to finish in.
    ///
    /// #126: App Store Connect counted fourteen build-5 sessions on
    /// 2026-08-24 and the relay recorded one. The mechanism is here rather
    /// than in the queue or in a lost iOS version. A person who opens the app,
    /// looks and leaves reaches none of the other flush points — there is no
    /// report, so no send-result flush, and far fewer than the twenty events
    /// the threshold wants — so the whole session rests on this one call. And
    /// this one call posted with `URLSession.shared` from a process iOS was
    /// already suspending, with nothing asking it to wait. The buffer is
    /// memory only, so a batch that does not make it out dies with the
    /// process and leaves nothing anywhere to say a session happened.
    ///
    /// `beginBackgroundTask` is the ask. It buys the seconds the POST needs
    /// and is ended the moment `flush` reports, so the app is not held awake
    /// past its own work. The expiration handler is iOS running out of
    /// patience first; there is nothing to salvage at that point, and the
    /// batch is already back in the buffer where it will die with the process,
    /// which is the honest outcome rather than a silent one.
    ///
    /// `ended` guards the pair: the completion and the expiration handler can
    /// both arrive, and ending an assertion twice is a crash. Both hops go
    /// through the main queue, so the flag needs no lock of its own.
    private func flushBeforeSuspending() {
        let assertion = BackgroundAssertion()
        assertion.identifier = UIApplication.shared
            .beginBackgroundTask(withName: "telemetry-flush") { [assertion] in
                assertion.end()
            }
        guard assertion.identifier != .invalid else {
            // No assertion granted. Flush anyway: that is exactly the
            // behaviour this replaces, and it is strictly better than not
            // flushing at all.
            Telemetry.shared.flush()
            return
        }
        Telemetry.shared.flush { [assertion] in
            // The transport answers on its own thread; the assertion is UIKit.
            DispatchQueue.main.async { assertion.end() }
        }
    }
}

/// Owns one background-task assertion so it can only be ended once.
///
/// Both callers can arrive: `flush`'s completion when the POST is done, and
/// the expiration handler when iOS runs out of patience first. Ending the same
/// assertion twice traps, so the identifier lives in one place rather than in
/// a local variable two closures each captured. Only ever touched on the main
/// queue, which is why it carries no lock.
private final class BackgroundAssertion {
    var identifier: UIBackgroundTaskIdentifier = .invalid

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
