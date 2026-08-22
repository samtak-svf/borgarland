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

    var body: some View {
        let state = model.state
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Það sem yrði sent")
                    .font(.title2)
                    .fontWeight(.semibold)

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
                    Text(state.sending ? "Sendi..." : "Senda á relay")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 16)
                .disabled(state.sending)

                Text("Sendist á \(RelayClient.baseURL), ekki til borgarinnar. Relay-ið er í þurrkeyrslu og framsendir ekkert.")
                    .font(.caption)
                    .padding(.top, 8)

                if let result = state.sendResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Svar frá relay")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(result)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
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
