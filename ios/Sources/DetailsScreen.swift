import SwiftUI
import BorgarlandCore

/// The suggestion slot sits above the category picker and is empty in this
/// POC. Per decision 0008 a suggestion may arrive late or never and must
/// never block, so the flow completes without it: the slot is present, the
/// send path does not depend on it.
struct DetailsScreen: View {
    @ObservedObject var model: ReportModel

    /// Whether the description field holds the keyboard. Without a focus to
    /// take away there was no way to put the keyboard down at all (#79): the
    /// screen had no scroll-to-dismiss, no focus state and no keyboard toolbar,
    /// so it went away only if the system happened to take it.
    @FocusState private var descriptionFocused: Bool

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
                .focused($descriptionFocused)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4)))
                .padding(.top, 8)

                Text("\(state.description.count) / \(state.descriptionMaxLength)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2)

                Button {
                    model.continueToSummary()
                } label: {
                    Text("Áfram")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 16)
                .disabled(state.selectedSlug == nil || descriptionIsBlank(state))

                if state.selectedSlug == nil || descriptionIsBlank(state) {
                    Text("Veldu flokk og skrifaðu lýsingu til að halda áfram. Borgin krefst lýsingar.")
                        .font(.caption)
                        .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .top, spacing: 0) { header("Skrá ábendingu") }
        // Two ways down, because one is a gesture nobody is told about and the
        // other is a control somebody can see (#79).
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Loka lyklaborði") { descriptionFocused = false }
            }
        }
    }

    /// The Kotlin's `isNotBlank()`: whitespace-only text does not count as a
    /// description, because the city enforces description as the one required
    /// field.
    private func descriptionIsBlank(_ state: ReportUiState) -> Bool {
        state.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
