import SwiftUI
import BorgarlandCore

/// The POC ends here: every field that would be posted, displayed exactly.
/// The send step exists (unlike the Android POC, which had no networking
/// dependency at all) but posts only to our relay, which is in dry run and
/// forwards nothing. Decision 0002 put that decision on the server so it is
/// a deploy away, not an App Store release.
struct SummaryScreen: View {
    @ObservedObject var model: ReportModel
    let payload: Payload

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
                Text("Ekkert fer til borgarinnar. Þetta app sendir aðeins á okkar relay (ákvörðun 0002) og relay-ið er í þurrkeyrslu og framsendir ekkert. Hér fyrir neðan er nákvæmlega það sem færi yfir línuna.")
                    .font(.footnote)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 12)

                if state.outOfBounds {
                    Text("Viðvörun: hnitin falla utan þess svæðis sem kort borgarinnar sýnir.")
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }

                FieldRow(label: "category", value: payload.categorySlug)
                FieldRow(label: "latitude", value: payload.latitudeText)
                FieldRow(label: "longitude", value: payload.longitudeText)
                FieldRow(label: "description", value: payload.description)

                Text("photo")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.top, 12)

                // By offset, not by name: every photo the app produces is
                // called mynd.jpg, and the contract allows the photo part to
                // repeat, so names are not identities here.
                ForEach(Array(payload.photos.enumerated()), id: \.offset) { _, file in
                    HStack(spacing: 12) {
                        if let image = PhotoBytes.image(from: file.bytes) {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                            Text("\(file.mime), \(file.sizeBytes) bytes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Text("Staðsetning úr: \(state.locationSource ?? "")")
                    .font(.caption)
                    .padding(.top, 12)

                Button {
                    model.sendToRelay()
                } label: {
                    HStack(spacing: 8) {
                        // Something moving, so the wait is legible as a wait
                        // rather than as a dead screen (#73).
                        if state.sending {
                            ProgressView()
                        }
                        Text(state.sending ? "Sendi..." : "Senda á relay")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 16)
                .disabled(state.sending)

                // The way out. Before #73 the send control was dead for
                // eighty-four seconds and the only live thing beside it was
                // Byrja aftur, which abandoned the report instead of stopping
                // the request. This stops the request; the report waits.
                if state.sending {
                    Button {
                        model.cancelSend()
                    } label: {
                        Text("Hætta við")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }

                // Where the report goes, in words rather than a hostname. A URL tells
                // a reader nothing they can act on, and the loopback one told them
                // something false (#29).
                Text("Sendist á þjónustu Borgarlands, ekki beint til borgarinnar. Þjónustan er í þurrkeyrslu og framsendir ekkert.")
                    .font(.caption)
                    .padding(.top, 8)

                if let note = state.deliveryNote {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note)
                            .font(.footnote)
                        // The one deliberate way a report leaves the phone
                        // without reaching the relay. Spelled out, because
                        // leaving a screen must not be how a report is thrown
                        // away.
                        if state.currentReportIsQueued {
                            Button(role: .destructive) {
                                model.discardCurrentReport()
                            } label: {
                                Text("Eyða ábendingunni")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 12)
                }

                if let sent = state.sendOutcome {
                    VStack(alignment: .leading, spacing: 8) {
                        // The sentence first, and in the person's language. A
                        // tester read the raw refusal off this screen and asked
                        // what it meant (#77).
                        if let outcome = sent.outcome {
                            Text(outcome.says)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if let advice = outcome.advice {
                                Text(advice)
                                    .font(.footnote)
                            }
                        }

                        // Still reachable, and still exactly what the relay
                        // said: it is the fastest way to see what happened, and
                        // losing it would trade one defect for another. Behind
                        // a control the person opens on purpose, so the default
                        // screen is a sentence rather than a diagnostic dump.
                        DisclosureGroup("Tæknilegt svar") {
                            Text(sent.raw)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                        .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 12)
                }

                Button {
                    model.startOver()
                } label: {
                    Text("Byrja aftur")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 16)
            }
            .padding(16)
        }
        // The same exposure as the details screen, never photographed doing it
        // but identical in shape (#78).
        .safeAreaInset(edge: .top, spacing: 0) { header("Það sem yrði sent") }
    }
}

/// The Kotlin's FieldRow: a divider, the wire field name in small secondary
/// type, and the value in monospace. The wire names are shown raw to the
/// user on purpose — this screen documents the contract.
private struct FieldRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
                .padding(.vertical, 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}
