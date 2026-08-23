import SwiftUI
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
                    Telemetry.shared.flush()
                }
                if phase == .active {
                    // The second retry trigger for a queued report (#73). The
                    // first is the path monitor in the model, and it only
                    // notices a NETWORK coming back — a relay that was down
                    // while the phone had signal gives it nothing to see.
                    model.deliverQueued()
                }
            }
        }
    }
}
