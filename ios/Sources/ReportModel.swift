import Foundation
import Combine
import CoreLocation
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
    /// What to SHOW for each slug, and the optional line under it. Resolved in
    /// the model so the screen never has to know an override exists (#40).
    var categoryDisplay: [String: String] = [:]
    var categoryHelp: [String: String] = [:]
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

    /// When the current photo was captured — the start of the location step.
    /// The telemetry channel's `elapsedMs` for the location and category
    /// events measures from here (data/relay-events.json).
    private var photoCapturedAt: Date?

    init() {
        let factsData = Bundle.main.url(forResource: "reykjavik-form.json", withExtension: nil)
            .flatMap { try? Data(contentsOf: $0) }
        let parsed = factsData.flatMap { try? Facts.parse($0) }
        relayRequest = Bundle.main.url(forResource: "relay-request.json", withExtension: nil)
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? RelayRequest.parse($0) }

        // Our own words for a category, where the city's are wrong for a walker
        // (#40). Optional on purpose: a missing or unreadable file falls back to
        // the city's names, which is a degraded picker rather than a dead app.
        // The facts file is the one that stops everything, because without it
        // there are no categories at all.
        let labels = Bundle.main.url(forResource: "category-labels.json", withExtension: nil)
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? CategoryLabels.parse($0) }

        if let parsed {
            facts = parsed
            var display: [String: String] = [:]
            var help: [String: String] = [:]
            for category in parsed.categories {
                display[category.slug] = CategoryLabels.display(category, in: labels)
                if let line = CategoryLabels.help(category, in: labels) {
                    help[category.slug] = line
                }
            }
            state = ReportUiState(
                categories: parsed.categories,
                categoryDisplay: display,
                categoryHelp: help,
                descriptionMaxLength: parsed.fields.description.maxLength
            )
        } else {
            state = ReportUiState(
                factsError: "reykjavik-form.json vantar eða er ólæsilegt í assets. Ekki er hægt að halda áfram."
            )
        }

        // The telemetry channel is fire-and-forget by contract
        // (data/relay-events.json): it must never affect the report. One
        // instance per launch, configured at the single place the app starts,
        // and the app-opened event belongs to that moment.
        Telemetry.shared.appVersion = Self.currentAppVersion
        Telemetry.shared.track(.appOpened)
    }

    /// The envelope's app version in "0.1.0 (3)" form — the marketing
    /// version and the build number, the same pair the Android side builds
    /// from BuildConfig.
    private static var currentAppVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(short) (\(build))"
    }

    /// Whole milliseconds since the current photo was captured; 0 when there
    /// is no photo, which callers only hit in paths where one exists.
    private func elapsedSincePhoto() -> Int {
        guard let photoCapturedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(photoCapturedAt) * 1000))
    }

    /// The Swift counterpart of the Kotlin's `it.copy(...)`: the state is
    /// immutable outside the model, so every change goes through a copy.
    private func update(_ change: (inout ReportUiState) -> Void) {
        var copy = state
        change(&copy)
        state = copy
    }

    func onPhotoCaptured(bytes: Data, rotationDegrees: Int, captureElapsedMs: Int) {
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
        photoCapturedAt = Date()
        Telemetry.shared.track(.photoCaptured(
            elapsedMs: captureElapsedMs,
            bytes: bytes.count,
            mime: Telemetry.normalizedMime(photo.mime)
        ))

        // EXIF first on every path, as in the Kotlin: a photo we captured
        // ourselves carries no GPS unless asked for it, so the device fix is
        // the primary source on the capture path but the code still tries
        // EXIF and falls through (AGENTS.md's location section).
        if let gps = ExifGps.read(from: bytes),
           Coordinates.isUsable(latitude: gps.latitude, longitude: gps.longitude) {
            // EXIF carries no radius; 0 is the "no radius reported" value.
            Telemetry.shared.track(.locationResolved(
                elapsedMs: elapsedSincePhoto(),
                source: .exif,
                accuracyM: 0
            ))
            Telemetry.shared.track(.screenLeft(screen: .camera, completed: true))
            update { state in
                state.coordinate = Coordinate(latitude: gps.latitude, longitude: gps.longitude)
                state.locationSource = "EXIF GPS úr mynd"
                state.screen = .details
            }
        } else {
            // The EXIF route yielded nothing for this photo; the flow falls
            // through to the device fix, and the failed attempt is recorded.
            Telemetry.shared.track(.locationFailed(elapsedMs: elapsedSincePhoto(), reason: .noExif))
            // Photo carries no usable GPS: ask the device for a fix.
            update { state in state.needsLocationPermission = true }
        }
    }

    func onPhotoError(_ message: String) {
        update { state in state.photoError = message }
    }

    func onLocationPermissionResult(_ granted: Bool) {
        Telemetry.shared.track(.locationPermission(granted: granted))
        if granted {
            requestDeviceFix()
        } else {
            Telemetry.shared.track(.locationFailed(elapsedMs: elapsedSincePhoto(), reason: .permission))
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
                   Coordinates.isUsable(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) {
                    Telemetry.shared.track(.locationResolved(
                        elapsedMs: elapsedSincePhoto(),
                        source: .device,
                        accuracyM: max(0, Int(location.horizontalAccuracy.rounded()))
                    ))
                    Telemetry.shared.track(.screenLeft(screen: .camera, completed: true))
                    state.locating = false
                    state.coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    state.locationSource = "Tækjastaðsetning (GPS)"
                    state.screen = .details
                } else {
                    // A nil fix means either nothing answered in time or the
                    // platform has location services off entirely; that is
                    // exactly the contract's timeout/unavailable split.
                    let reason: TelemetryEvent.LocationFailure =
                        CLLocationManager.locationServicesEnabled() ? .timeout : .unavailable
                    Telemetry.shared.track(.locationFailed(elapsedMs: elapsedSincePhoto(), reason: reason))
                    state.locating = false
                    state.locationError = "Myndin ber enga GPS staðsetningu og tækið fékk enga staðsetningu. Ekki er hægt að halda áfram án hnitanna, enda getur enginn brugðist við skýrslu án staðsetningar."
                }
            }
        }
    }

    func retakePhoto() {
        photoCapturedAt = nil
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
        Telemetry.shared.track(.categoryChosen(elapsedMs: elapsedSincePhoto(), slug: slug))
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
        // The LENGTH of what was typed, never the text (data/relay-events.json).
        Telemetry.shared.track(.descriptionLength(length: state.description.count))
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
        Telemetry.shared.track(.screenLeft(screen: .details, completed: true))
        update { state in
            state.screen = .summary
            state.outOfBounds = outside
        }
    }

    func startOver() {
        Telemetry.shared.track(.screenLeft(screen: .confirm, completed: false))
        photoCapturedAt = nil
        let categories = state.categories
        let categoryDisplay = state.categoryDisplay
        let categoryHelp = state.categoryHelp
        let descriptionMaxLength = state.descriptionMaxLength
        state = ReportUiState(
            categories: categories,
            categoryDisplay: categoryDisplay,
            categoryHelp: categoryHelp,
            descriptionMaxLength: descriptionMaxLength
        )
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
        Telemetry.shared.track(.sendStarted)
        let startedAt = Date()
        Task {
            let result = await RelayClient.send(payload: payload, contract: contract)
            let elapsedMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
            if result.status != 0 {
                // The relay answered, whatever the status: the send completed.
                Telemetry.shared.track(.sendResult(elapsedMs: elapsedMs, status: result.status, ok: result.ok))
            } else {
                let reason: TelemetryEvent.SendFailure
                switch result.failure {
                case .connection: reason = .connection
                case .timeout: reason = .timeout
                case .encoding: reason = .encoding
                case .other: reason = .other
                case nil: reason = .other
                }
                Telemetry.shared.track(.sendFailed(elapsedMs: elapsedMs, reason: reason))
            }
            // A natural end point: the events around the report send go now.
            Telemetry.shared.flush()
            update { state in
                state.sending = false
                state.sendResult = if result.ok {
                    "HTTP \(result.status)\n\(result.body)"
                } else if result.status == 0 {
                    "Náði ekki sambandi við þjónustu Borgarlands (\(RelayClient.baseURL)): \(result.body)"
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
