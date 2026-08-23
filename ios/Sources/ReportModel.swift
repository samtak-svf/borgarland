import Foundation
import Combine
import CoreLocation
import Network
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
    /// What is happening to THIS report when the relay has not answered: it is
    /// waiting for a network, or someone stopped the attempt. Separate from
    /// `sendResult`, which is the relay's own words and only exists once the
    /// relay has said something (#73).
    var deliveryNote: String? = nil
    /// How many reports are on the phone waiting to be sent, this one
    /// included. The camera screen shows it, because after Byrja aftur that is
    /// the only place a waiting report is visible at all.
    var queuedCount: Int = 0
    /// Whether the report THIS screen is about is still waiting. Drives the
    /// discard control: a report that has arrived, or has already been thrown
    /// away, must not offer one.
    var currentReportIsQueued: Bool = false
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

    /// Reports that have not reached the relay yet, on disk (#73). Everything a
    /// person files goes in here BEFORE it is sent, so losing the network
    /// cannot lose the report.
    private let queue = ReportQueue.applicationDefault()

    /// The one delivery in flight, or nil. One at a time, always: it is what
    /// keeps a queued report from being sent twice, and it is why the send
    /// control can be cancelled by cancelling exactly one thing.
    private var delivery: Task<Void, Never>?

    /// The report the screen is currently about. Also the screen's claim on a
    /// result: a delivery only writes to the UI when its id still matches, so a
    /// report from an earlier walk finishing in the background cannot land on
    /// the screen of the one in front of the person.
    private var currentReportID: String?

    /// Watches for a network coming back, which is the second of the two
    /// retry triggers (the other is the app returning to the foreground). The
    /// handler also fires once when the monitor starts, which is how a report
    /// queued in a previous launch goes out without anyone doing anything.
    private let network = NWPathMonitor()

    /// What became of one attempt, from the queue's point of view rather than
    /// the person's.
    private enum Disposition {
        /// The relay took it. Nothing more is owed.
        case sent
        /// The relay read it and refused it. The same bytes would be refused
        /// again, so it stops waiting; the screen still holds it.
        case refused
        /// Nobody answered. Keep it and try later.
        case waiting
        /// Someone pressed cancel. Keep it, and say nothing to the instrument:
        /// nothing failed.
        case cancelled
    }

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

        refreshQueuedCount()
        network.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.deliverQueued() }
        }
        network.start(queue: DispatchQueue(label: "is.borgarland.connectivity"))
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

    /// Starts a new report. Deliberately does NOT cancel or discard a delivery
    /// in flight: before #73 this was the only live control on a stuck send
    /// screen, and pressing it abandoned the report. It now leaves the screen
    /// and leaves the report to the queue.
    func startOver() {
        Telemetry.shared.track(.screenLeft(screen: .confirm, completed: false))
        photoCapturedAt = nil
        currentReportID = nil
        let categories = state.categories
        let categoryDisplay = state.categoryDisplay
        let categoryHelp = state.categoryHelp
        let descriptionMaxLength = state.descriptionMaxLength
        let queuedCount = state.queuedCount
        let sending = state.sending
        state = ReportUiState(
            categories: categories,
            categoryDisplay: categoryDisplay,
            categoryHelp: categoryHelp,
            descriptionMaxLength: descriptionMaxLength,
            sending: sending,
            queuedCount: queuedCount
        )
    }

    /// Sends to OUR relay, which is the only thing this app can reach. The
    /// relay decides whether anything reaches the city, and it is in dry run
    /// by default. Decision 0002 put that decision on the server precisely so
    /// it is one deploy away from being changed rather than an app release.
    ///
    /// Written down first, then sent. The order is the whole fix for #73: the
    /// failure this guards against arrives AFTER the decision to send, so a
    /// report that exists only in memory at that moment is exactly the one
    /// that gets lost.
    func sendToRelay() {
        guard let payload = payload() else { return }
        guard relayRequest != nil else {
            update { state in
                state.sendResult = "relay-request.json vantar eða er ólæsilegt í assets. Ekki er hægt að senda."
            }
            return
        }
        update { state in
            state.sendResult = nil
            state.deliveryNote = nil
        }
        do {
            currentReportID = try queue.enqueue(payload).id
            update { state in state.currentReportIsQueued = true }
            refreshQueuedCount()
            deliverQueued()
        } catch {
            // The report could not be written down — a full disk, or a
            // container we cannot reach. Sending it anyway is worse than a
            // queue and better than refusing, and it is exactly the behaviour
            // the app had before this issue.
            sendUnqueued(payload)
        }
    }

    /// Sends what is waiting, oldest first. Safe to call from anywhere and as
    /// often as anything likes: a delivery already in flight makes this a
    /// no-op, which is what keeps a queued report from going twice.
    func deliverQueued() {
        guard delivery == nil, let contract = relayRequest else { return }
        guard !queue.pending().isEmpty else {
            refreshQueuedCount()
            return
        }
        update { state in state.sending = true }
        delivery = Task { [weak self] in
            await self?.drainQueue(contract: contract)
            guard let self else { return }
            self.delivery = nil
            self.update { state in state.sending = false }
            self.refreshQueuedCount()
        }
    }

    /// Stops the attempt in flight. The report stays queued: this is a way out
    /// of the wait, not a way to throw the report away. Before #73 the only
    /// control on this screen did the opposite.
    func cancelSend() {
        delivery?.cancel()
    }

    /// Throws away the report the screen is about. The one deliberate way a
    /// report leaves the queue without ever reaching the relay, so it is
    /// spelled out in the interface rather than implied by leaving a screen.
    func discardCurrentReport() {
        guard let id = currentReportID else { return }
        queue.remove(id)
        currentReportID = nil
        refreshQueuedCount()
        update { state in
            state.currentReportIsQueued = false
            state.deliveryNote = "Ábendingunni var eytt úr símanum og hún verður ekki send."
        }
    }

    /// Throws away everything waiting. Reached from the camera screen, where
    /// the count is the only thing visible, so the control there says how many
    /// it is about.
    func discardAllQueued() {
        for report in queue.pending() {
            queue.remove(report.id)
        }
        currentReportID = nil
        refreshQueuedCount()
    }

    private func refreshQueuedCount() {
        let count = queue.pending().count
        update { state in state.queuedCount = count }
    }

    /// One report at a time, in the order they were filed, until one of them
    /// has to wait. `handled` is not bookkeeping for its own sake: if a removal
    /// ever failed, the same entry would be at the head of the queue on the
    /// next turn of this loop and the loop would not end.
    private func drainQueue(contract: RelayRequestFile) async {
        var handled: Set<String> = []
        while let report = queue.pending().first(where: { !handled.contains($0.id) }) {
            if Task.isCancelled { return }
            handled.insert(report.id)

            let payload: Payload
            do {
                payload = try queue.payload(for: report)
            } catch {
                // The bytes are gone, so this entry can never be built. Left
                // alone it would sit at the head of the queue and stop every
                // report behind it.
                queue.remove(report.id)
                continue
            }

            queue.recordAttempt(report.id)
            switch await attempt(payload: payload, contract: contract, reportID: report.id) {
            case .sent, .refused:
                queue.remove(report.id)
                refreshQueuedCount()
            case .waiting, .cancelled:
                // It stays, and nothing behind it goes first: the order they
                // were filed in is the order they are owed.
                return
            }
        }
    }

    /// The old send path, still the only one when the report could not be
    /// written down. The token stands in for a queue id so a result arriving
    /// after Byrja aftur cannot land on the next report's screen.
    private func sendUnqueued(_ payload: Payload) {
        guard let contract = relayRequest else { return }
        guard delivery == nil else {
            // Another delivery is running and this report was never written
            // down, so there is nothing to hand it. Say so rather than
            // swallowing the press.
            update { state in
                state.deliveryNote = "Önnur ábending er í sendingu. Reyndu aftur eftir augnablik."
            }
            return
        }
        let token = UUID().uuidString
        currentReportID = token
        update { state in state.sending = true }
        delivery = Task { [weak self] in
            _ = await self?.attempt(payload: payload, contract: contract, reportID: token)
            guard let self else { return }
            self.delivery = nil
            self.update { state in state.sending = false }
        }
    }

    /// One attempt, with the telemetry around it and the answer rendered.
    private func attempt(
        payload: Payload,
        contract: RelayRequestFile,
        reportID: String
    ) async -> Disposition {
        Telemetry.shared.track(.sendStarted)
        let startedAt = Date()
        let result = await RelayClient.send(payload: payload, contract: contract)
        let elapsedMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))

        if Task.isCancelled {
            // Someone pressed cancel. Nothing failed — not the network, not the
            // relay, not the report — and the telemetry contract has no word
            // for this, so it gets none.
            show(nil, disposition: .cancelled, for: reportID)
            return .cancelled
        }

        if result.status != 0 {
            // The relay answered, whatever the status: the send completed.
            Telemetry.shared.track(.sendResult(elapsedMs: elapsedMs, status: result.status, ok: result.ok))
        } else {
            let reason: TelemetryEvent.SendFailure
            switch result.failure {
            case .connection: reason = .connection
            case .timeout: reason = .timeout
            case .encoding: reason = .encoding
            case .cancelled, .other, nil: reason = .other
            }
            Telemetry.shared.track(.sendFailed(elapsedMs: elapsedMs, reason: reason))
        }
        // A natural end point: the events around the report send go now.
        Telemetry.shared.flush()

        let disposition = Self.disposition(of: result)
        show(result, disposition: disposition, for: reportID)
        return disposition
    }

    /// What the queue should do about an answer. `ok` is the relay's own
    /// judgement and is trusted; below it, the split is between an answer that
    /// would be the same next time and no answer at all.
    private static func disposition(of result: RelayClient.Result) -> Disposition {
        if result.ok { return .sent }
        switch result.status {
        case 0, 408, 429:
            return .waiting
        case 400..<500:
            return .refused
        default:
            // A 5xx is the relay having a bad moment, not a bad report.
            return .waiting
        }
    }

    /// Writes an outcome to the screen, but only for the report the screen is
    /// about. A queued report from an earlier walk finishing while someone is
    /// looking at a new one must not answer for it (#73).
    private func show(_ result: RelayClient.Result?, disposition: Disposition, for reportID: String) {
        guard reportID == currentReportID else { return }
        update { state in
            switch disposition {
            case .sent, .refused:
                state.currentReportIsQueued = false
                state.deliveryNote = nil
                state.sendResult = result.map { "HTTP \($0.status)\n\($0.body)" }
            case .waiting:
                state.sendResult = nil
                state.deliveryNote = "Ekki náðist samband við þjónustu Borgarlands. Ábendingin bíður í símanum og fer af stað um leið og netið kemur aftur."
            case .cancelled:
                state.sendResult = nil
                state.deliveryNote = "Hætt við sendingu. Ábendingin bíður í símanum og fer af stað þegar reynt er aftur."
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
