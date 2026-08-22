import SwiftUI

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
    @StateObject private var model = ReportModel()

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
        }
    }
}
