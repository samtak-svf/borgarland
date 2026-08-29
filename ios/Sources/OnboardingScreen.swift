import SwiftUI
import BorgarlandCore

/// Asked once, on the first launch, and never again (#163).
///
/// The city answers an ábending by email and by nothing else — its form has no
/// phone field and the app shows no ticket handle — so a report filed without
/// an address goes into silence. Asking here rather than on the report screen
/// is the difference between answering a question once and being asked it on
/// every walk.
///
/// **This does not make a form the entry point.** AGENTS.md says the camera is,
/// and no path into a REPORT starts with a form: this screen is not on that
/// path. It appears when the phone holds no address and never afterwards, and
/// the report flow behind it still opens on the camera.
///
/// Deliberately emits no telemetry. `screen-left` in data/relay-events.json
/// carries a fixed enum of screen names, and adding one to it is a relay
/// deploy that must land BEFORE any build that sends it — otherwise the whole
/// event batch is refused as invalid-event-batch and the app is never told.
/// That cost is not worth a count of a screen shown once per install, and the
/// address itself deliberately carries no telemetry of any kind.
struct OnboardingScreen: View {
    @ObservedObject var model: ReportModel

    @FocusState private var emailFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Velkomin í Borgarland")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("""
                    Borgin svarar ábendingum í tölvupósti og hvergi annars staðar. \
                    Hún sendir staðfestingu með tilvísunarnúmeri á netfangið þitt, \
                    og það er eina leiðin sem þú heyrir frá henni.
                    """)

                Text("""
                    Netfangið er geymt hér í símanum og hvergi annars staðar. Það \
                    fylgir hverri ábendingu til borgarinnar, en við geymum það ekki.
                    """)

                TextField(
                    "Netfang",
                    text: Binding(
                        get: { model.state.email },
                        set: { model.onEmailChange($0) }
                    )
                )
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($emailFocused)
                .accessibilityIdentifier("onboarding-email-field")
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(looksWrong ? Color.red : Color(.systemGray4))
                )

                // In the scroll content, not the pinned footer: every point the
                // footer occupies is a point of content it covers at rest, and
                // on the details screen a footer carrying both the button and
                // its explanatory line reached far enough up to cover a text
                // field's centre — which is where a tap lands.
                if !model.state.emailValid {
                    Text("Sláðu inn netfang til að halda áfram. Þú getur breytt því síðar á skjánum þar sem ábendingin er skrifuð.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Pinned, not scrolled to — the same fix the details screen needed on
        // the first CI run after #163 (see DetailsScreen). This screen carries
        // MORE prose than that one and has one field and one button, which is
        // exactly #110's shape, and unlike the details screen it has no
        // simulator test to catch it. Applied here on the strength of the
        // measurement rather than waiting for somebody to meet it: on Android
        // the equivalent control cleared the keyboard by 277 px on a 2316-tall
        // display, which is room on a large phone and not obviously room on a
        // small one.
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        // The same two ways down the details screen has (#79): a gesture, and
        // a control somebody can see.
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Loka lyklaborði") { emailFocused = false }
            }
        }
    }

    /// The button that leaves this screen, plus the line saying why it is
    /// refused. Opaque, because the content scrolls underneath it.
    private var footer: some View {
        Button {
            model.completeOnboarding()
        } label: {
            Text("Áfram").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.state.emailValid)
        .accessibilityIdentifier("onboarding-continue-button")
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    /// Red only once there is something to be wrong ABOUT — an untouched field
    /// on a first launch is not a mistake somebody has made.
    private var looksWrong: Bool {
        !model.state.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.state.emailValid
    }
}
