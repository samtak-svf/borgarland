import Foundation
import Combine
import BorgarlandCore

/// Which of the three screens the shell shows. The Kotlin reference models
/// this as a sealed interface; the Swift equivalent is an enum, and the app
/// switches on it exactly as MainActivity does a `when`.
enum Screen {
    case camera
    case details
    case summary
}

/// A usable coordinate. The full words are our vocabulary
/// (data/relay-request.json); the city's short field names are deliberately
/// absent from the whole app (AGENTS.md).
struct Coordinate {
    let latitude: Double
    let longitude: Double
}

/// The same state fields as PocUiState, in the same order, so a reader can
/// diff the two files by eye. Defaults are the Kotlin defaults; the facts
/// file replaces categories and descriptionMaxLength at startup.
struct ReportUiState {
    var screen: Screen = .camera
    var factsError: String? = nil
    // Module-qualified: the SDK carries a type of the same name, and an
    // unqualified `Category` is ambiguous at type position.
    var categories: [BorgarlandCore.Category] = []
    var descriptionMaxLength: Int = 2500
    var photo: Photo? = nil
    var photoError: String? = nil
    var coordinate: Coordinate? = nil
    var locationSource: String? = nil
    var locating: Bool = false
    var needsLocationPermission: Bool = false
    var locationError: String? = nil
    var selectedSlug: String? = nil
    var description: String = ""
    var outOfBounds: Bool = false
    var sending: Bool = false
    var sendResult: String? = nil
}

/// Camera first, coordinate guarded, category and description chosen by a
/// person, payload shown and never sent. The facts file is loaded from the
/// bundle at startup; if it is missing or unparseable the app says so instead
/// of inventing the category list (AGENTS.md).
@MainActor
final class ReportModel: ObservableObject {
    /// read-only outside the model, like the Kotlin's private `_state` with
    /// a public `state` on top.
    @Published private(set) var state = ReportUiState()

    private var facts: FactsFile?

    // The relay request contract, from the same bundle copy the facts file
    // uses. Sending is impossible without it: RelayClient writes parts under
    // exactly the names this file carries.
    private var relayRequest: RelayRequestFile?

    init() {
        let factsData = Bundle.main.url(forResource: "reykjavik-form.json", withExtension: nil)
            .flatMap { try? Data(contentsOf: $0) }
        let parsed = factsData.flatMap { try? Facts.parse($0) }
        relayRequest = Bundle.main.url(forResource: "relay-request.json", withExtension: nil)
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? RelayRequest.parse($0) }

        if let parsed {
            facts = parsed
            state = ReportUiState(
                categories: parsed.categories,
                descriptionMaxLength: parsed.fields.description.maxLength
            )
        } else {
            state = ReportUiState(
                factsError: "reykjavik-form.json vantar eða er ólæsilegt í assets. Ekki er hægt að halda áfram."
            )
        }
    }

    /// The Swift counterpart of the Kotlin's `it.copy(...)`: the state is
    /// immutable outside the model, so every change goes through a copy.
    private func update(_ change: (inout ReportUiState) -> Void) {
        var copy = state
        change(&copy)
        state = copy
    }

    func onPhotoCaptured(bytes: Data, rotationDegrees: Int) {
        let photo = PhotoBytes.photo(from: bytes, rotationDegrees: rotationDegrees)
        update { state in
            state.photo = photo
            state.photoError = nil
            state.coordinate = nil
            state.locationSource = nil
            state.locating = false
            state.needsLocationPermission = false
            state.locationError = nil
        }

        // EXIF first on every path, as in the Kotlin: a photo we captured
        // ourselves carries no GPS unless asked for it, so the device fix is
        // the primary source on the capture path but the code still tries
        // EXIF and falls through (AGENTS.md's location section).
        if let gps = ExifGps.read(from: bytes),
           Coordinates.isUsable(latitude: gps.latitude, longitude: gps.longitude) {
            update { state in
                state.coordinate = Coordinate(latitude: gps.latitude, longitude: gps.longitude)
                state.locationSource = "EXIF GPS úr mynd"
                state.screen = .details
            }
        } else {
            // Photo carries no usable GPS: ask the device for a fix.
            update { state in state.needsLocationPermission = true }
        }
    }

    func onPhotoError(_ message: String) {
        update { state in state.photoError = message }
    }

    func onLocationPermissionResult(_ granted: Bool) {
        if granted {
            requestDeviceFix()
        } else {
            update { state in
                state.needsLocationPermission = false
                state.locating = false
                state.locationError = "Staðsetningarleyfi vantar. Borgin samþykkir skýrslu án hnitanna, en þá getur enginn brugðist við henni."
            }
        }
    }

    func requestDeviceFix() {
        update { state in
            state.locating = true
            state.locationError = nil
            state.needsLocationPermission = false
        }
        Task {
            let location = await DeviceFix.shared.request()
            update { state in
                if let location,
                   Coordinates.isUsable(latitude: location.latitude, longitude: location.longitude) {
                    state.locating = false
                    state.coordinate = Coordinate(latitude: location.latitude, longitude: location.longitude)
                    state.locationSource = "Tækjastaðsetning (GPS)"
                    state.screen = .details
                } else {
                    state.locating = false
                    state.locationError = "Myndin ber enga GPS staðsetningu og tækið fékk enga staðsetningu. Ekki er hægt að halda áfram án hnitanna, enda getur enginn brugðist við skýrslu án staðsetningar."
                }
            }
        }
    }

    func retakePhoto() {
        update { state in
            state.photo = nil
            state.photoError = nil
            state.coordinate = nil
            state.locationSource = nil
            state.locating = false
            state.needsLocationPermission = false
            state.locationError = nil
        }
    }

    func selectCategory(_ slug: String) {
        update { state in state.selectedSlug = slug }
    }

    func onDescriptionChange(_ text: String) {
        let max = state.descriptionMaxLength
        // Kotlin truncates with take(max); Swift truncates on characters
        // rather than UTF-16 code units, which is the same count for the
        // text this field gets and never goes over the limit.
        update { state in
            state.description = text.count > max ? String(text.prefix(max)) : text
        }
    }

    func continueToSummary() {
        let s = state
        guard let facts,
              facts.categories.contains(where: { $0.slug == s.selectedSlug }),
              let coord = s.coordinate,
              !s.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        // The city's own map bounds are for its form's map view and cover
        // more than the municipality; the registry check that would tell a
        // Kópavogur coordinate from a Reykjavík one lives in the relay. This
        // is the Kotlin's bounds comparison, ported unchanged.
        let outside = coord.latitude < facts.map.bounds.south || coord.latitude > facts.map.bounds.north
            || coord.longitude < facts.map.bounds.west || coord.longitude > facts.map.bounds.east
        update { state in
            state.screen = .summary
            state.outOfBounds = outside
        }
    }

    func startOver() {
        let categories = state.categories
        let descriptionMaxLength = state.descriptionMaxLength
        state = ReportUiState(categories: categories, descriptionMaxLength: descriptionMaxLength)
    }

    /// Sends to OUR relay, which is the only thing this app can reach. The
    /// relay decides whether anything reaches the city, and it is in dry run
    /// by default. Decision 0002 put that decision on the server precisely so
    /// it is one deploy away from being changed rather than an app release.
    func sendToRelay() {
        guard let payload = payload() else { return }
        guard let contract = relayRequest else {
            update { state in
                state.sendResult = "relay-request.json vantar eða er ólæsilegt í assets. Ekki er hægt að senda."
            }
            return
        }
        update { state in
            state.sending = true
            state.sendResult = nil
        }
        Task {
            let result = await RelayClient.send(payload: payload, contract: contract)
            update { state in
                state.sending = false
                state.sendResult = if result.ok {
                    "HTTP \(result.status)\n\(result.body)"
                } else if result.status == 0 {
                    "Náði ekki sambandi við relay á \(RelayClient.baseURL): \(result.body)"
                } else {
                    "HTTP \(result.status)\n\(result.body)"
                }
            }
        }
    }

    func payload() -> Payload? {
        let s = state
        guard let category = facts?.categories.first(where: { $0.slug == s.selectedSlug }),
              let coord = s.coordinate else { return nil }
        return Payload(
            categorySlug: category.slug,
            latitude: coord.latitude,
            longitude: coord.longitude,
            description: s.description,
            photos: s.photo.map { [$0] } ?? []
        )
    }
}
