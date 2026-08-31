import SwiftUI
import BorgarlandCore

/// The suggestion slot sits above the category picker and is empty in this
/// POC. Per decision 0008 a suggestion may arrive late or never and must
/// never block, so the flow completes without it: the slot is present, the
/// send path does not depend on it.
struct DetailsScreen: View {
    @ObservedObject var model: ReportModel

    /// Which field holds the keyboard, or none. Without a focus to take away
    /// there was no way to put the keyboard down at all (#79): the screen had
    /// no scroll-to-dismiss, no focus state and no keyboard toolbar, so it
    /// went away only if the system happened to take it.
    ///
    /// An enum rather than a Bool since #163 added a second field. The
    /// toolbar's way down has to work from whichever field is up, and a
    /// per-field Bool is how one of them quietly stops having one.
    @FocusState private var focused: Field?

    private enum Field { case description, email }

    /// The title, pinned above the scroll view rather than carried inside it.
    ///
    /// `safeAreaInset` does two things at once and both are the fix: it puts an
    /// opaque strip between the status bar and the content, and it insets the
    /// scroll view's own safe area so the content stops at the strip instead of
    /// passing under it. In the field-test screenshot the clock sat on top of a
    /// category name and both were unreadable (#78).
    private func header(_ title: String) -> some View {
        Text(title)
            .font(.title2)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(Color(.systemBackground))
    }

    var body: some View {
        let state = model.state
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Staðsetning: \(state.locationSource ?? "")")
                    .font(.footnote)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tillaga úr myndinni")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Engin tillaga enn. Þegar greining verður til birtist tillagan hér, seint eða aldrei. Hún kemur aldrei í veg fyrir áframhald.")
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 16)

                Text("Flokkur")
                    .font(.headline)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                ForEach(state.categories, id: \.slug) { category in
                    let selected = state.selectedSlug == category.slug
                    Button {
                        model.selectCategory(category.slug)
                    } label: {
                        HStack(spacing: 12) {
                            // Material's radio dot has no exact SF Symbol;
                            // the filled large circle reads the same.
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                // Our name where we have one, the city's
                                // otherwise (data/category-labels.json). The
                                // model resolves it, so this screen never
                                // learns that an override exists.
                                Text(state.categoryDisplay[category.slug] ?? category.category)
                                // The line under it is a help string for a
                                // category whose scope is not obvious, and most
                                // have none.
                                //
                                // This used to render the city's
                                // general/specific `type`, which put "Almenn
                                // ábending" under a category also called
                                // "Almenn ábending" (#40). That subtitle was
                                // the city's own taxonomy and told a walker
                                // nothing they could act on; removing it fixes
                                // the collision at the root rather than
                                // renaming one half of it.
                                if let help = state.categoryHelp[category.slug] {
                                    Text(help)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }

                TextField(
                    "Lýsing",
                    // The getter reads the model, not the `state` snapshot
                    // taken at the top of body: a text field whose getter can
                    // lag the value it is editing is a class of bug worth not
                    // having, even where body re-evaluation happens to hide it.
                    text: Binding(
                        get: { model.state.description },
                        set: { model.onDescriptionChange($0) }
                    ),
                    axis: .vertical
                )
                .lineLimit(4...10)
                .focused($focused, equals: .description)
                // Named for the UI test that asserts the control below stays
                // hittable with the keyboard up (#110, #125). A SwiftUI
                // TextField with `axis: .vertical` is a text VIEW to XCUITest
                // on some iOS versions and a text FIELD on others, so the
                // query is by identifier rather than by element type.
                .accessibilityIdentifier("description-field")
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4)))
                .padding(.top, 8)

                Text("\(state.description.count) / \(state.descriptionMaxLength)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2)

                // The city answers a report by email and by nothing else, so a
                // report without one is filed into silence (#163). Asked for
                // here, once per phone: the model prefills it from the device
                // and writes it back when this screen is left, so a second
                // walk finds it already filled.
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
                .focused($focused, equals: .email)
                .accessibilityIdentifier("email-field")
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(emailLooksWrong(state) ? Color.red : Color(.systemGray4))
                )
                .padding(.top, 12)

                Text("Borgin sendir staðfestingu og tilvísunarnúmer á þetta netfang. Það er eina leiðin sem þú heyrir frá henni.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                // The gallery save toggle (#179). Device state, default ON —
                // the surprising behaviour was the one that kept nothing — and
                // it is not part of a report: the relay learns nothing about
                // it. `galleryBlocked` is the add-only permission refused for
                // good, which no switch can undo: the screen says so instead
                // of sitting on "saving" while nothing is saved.
                Toggle(
                    isOn: Binding(
                        get: { model.state.saveToGallery },
                        set: { model.setSaveToGallery($0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vista mynd í myndasafni")
                        Text(
                            model.state.galleryBlocked
                                ? "Borgarland hefur ekki leyfi til að vista í myndasafnið. Leyfið er opnað í stillingum símans."
                                : "Myndin sem þú tekur er einnig vistuð í myndasafnið þitt, í möppunni Borgarland."
                        )
                        .font(.caption)
                        .foregroundStyle(
                            model.state.galleryBlocked ? Color.red : Color.secondary
                        )
                    }
                }
                .padding(.top, 12)

                // The line saying why Áfram is refused. It lives HERE rather
                // than in the pinned footer: every point the footer occupies is
                // a point of content it covers at rest, and on an iPhone 17 Pro
                // a footer carrying both the button and this line reached far
                // enough up to cover the description field's centre — which is
                // where XCUITest taps, so the field never took focus and both
                // keyboard tests failed on typing rather than on layout.
                if blocked(state) {
                    Text("Veldu flokk, skrifaðu lýsingu og settu inn netfang til að halda áfram. Borgin krefst lýsingar; netfangið krefjumst við, svo svarið rati til þín.")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                }

            }
            .padding(16)
        }
        .safeAreaInset(edge: .top, spacing: 0) { header("Skrá ábendingu") }
        // The control that ends the screen is PINNED, not scrolled to (#110,
        // again). It used to be the last thing inside the ScrollView, and that
        // held only because the content above it happened to be short enough:
        // adding the address field and its caption (#163) pushed it under the
        // keyboard, and the simulator test caught it on the first CI run — the
        // regression a compile cannot see, which is why that test exists.
        //
        // safeAreaInset(edge: .bottom) makes the button part of the scroll
        // view's safe area instead of its content, so it sits ABOVE the
        // keyboard rather than behind it, and the scrollable content is inset
        // to match. That is the same modifier already holding the title still
        // at the top, used for the same reason at the other end — and it is
        // now independent of how much this screen grows, which the previous
        // arrangement never was.
        .safeAreaInset(edge: .bottom, spacing: 0) { footer(state) }
        // Two ways down, because one is a gesture nobody is told about and the
        // other is a control somebody can see (#79).
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Loka lyklaborði") { focused = nil }
            }
        }
    }

    /// The button that ends the screen, plus the line saying why it is refused.
    /// Pinned to the bottom rather than carried in the scroll view — see the
    /// safeAreaInset above. Opaque, because the content scrolls underneath it.
    private func footer(_ state: ReportUiState) -> some View {
        Button {
            model.continueToSummary()
        } label: {
            Text("Áfram")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(blocked(state))
        // The control #110 was about: the keyboard covered it, and a compile
        // cannot see that.
        .accessibilityIdentifier("continue-button")
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    /// Why Áfram is refused, in one place so the button and the line beneath
    /// the form cannot disagree about it.
    private func blocked(_ state: ReportUiState) -> Bool {
        state.selectedSlug == nil || descriptionIsBlank(state) || !state.emailValid
    }

    /// The Kotlin's `isNotBlank()`: whitespace-only text does not count as a
    /// description, because the city enforces description as the one required
    /// field.
    private func descriptionIsBlank(_ state: ReportUiState) -> Bool {
        state.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Red only once there is something to be wrong ABOUT. An empty field on a
    /// fresh install is not an error, it is a field nobody has reached yet, and
    /// marking it red before the first keystroke tells somebody they have made
    /// a mistake by opening the app.
    private func emailLooksWrong(_ state: ReportUiState) -> Bool {
        !state.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !state.emailValid
    }
}
