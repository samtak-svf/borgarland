import Foundation
import Combine
import CoreLocation
import Network
import BorgarlandCore

/// Which of the three screens the shell shows. The Kotlin reference models
/// this as a sealed interface; the Swift equivalent is an enum, and the app
/// switches on it exactly as MainActivity does a `when`.
enum Screen {
    /// Shown once, on the first launch, and never again once the phone holds
    /// an address (#163). Not on the path to a report: the report flow still
    /// opens on the camera, which is what AGENTS.md means by the camera being
    /// the entry point.
    case onboarding
    case camera
    case details
    case summary
}

/// What the person is told about a relay answer, and the answer itself.
///
/// Both, not either: the sentence is what the screen leads with, and the
/// relay's own body stays reachable behind a control they open on purpose. The
/// readout was right for a proof of concept driven by the people who wrote it;
/// the defect was that it was the ONLY thing anyone was shown (#77).
struct SendOutcome {
    /// Our sentence, or nil when data/relay-outcomes.json is not in the bundle
    /// to say it. The screen then shows the relay's own answer alone, which is
    /// exactly what it did before this issue.
    let outcome: RelayOutcome?
    /// The relay's answer, verbatim, status line included.
    let raw: String
    let status: Int
    let ok: Bool
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
    /// The permission is denied or restricted, not merely unanswered. The
    /// difference decides which way out the screen offers, because the system
    /// does not prompt twice and only Settings can undo it (#76).
    var locationDenied: Bool = false
    var locationError: String? = nil
    var selectedSlug: String? = nil
    var description: String = ""
    /// Where the city will send its confirmation (#163). Read from the device
    /// at startup, so somebody who has filed before finds it already there.
    var email: String = ""
    /// Whether that address is one we will send with. Resolved here rather
    /// than on the screen for the same reason `categoryDisplay` is: the rule
    /// lives in `ContactDetails`, and a screen that re-implemented it would be
    /// a second rule that can disagree with the first.
    var emailValid: Bool = false
    /// Whether captured photographs are also saved to the device gallery
    /// (#179). Device state, default ON, kept in `Settings` — never part of
    /// a report, and the relay learns nothing about it.
    var saveToGallery: Bool = true
    /// The toggle cannot lie: if the add-only photo permission has been
    /// refused, saving can never happen and the screen says so instead of
    /// sitting on "saving" while nothing is saved (#76's distinction,
    /// applied to #179).
    var galleryBlocked: Bool = false
    var outOfBounds: Bool = false
    var sending: Bool = false
    var sendOutcome: SendOutcome? = nil
    /// What is happening to THIS report when the relay has not answered: it is
    /// waiting for a network, or someone stopped the attempt. Separate from
    /// `sendOutcome`, which is what the relay answered and only exists once the
    /// relay has answered something (#73).
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

    /// Our sentences for what the relay answered (#77). Nil when the file is
    /// missing from the bundle, which costs the sentence and nothing else.
    private var relayOutcomes: RelayOutcomesFile?

    /// When the current photo was captured — the start of the location step.
    /// The telemetry channel's `elapsedMs` for the location and category
    /// events measures from here (data/relay-events.json).
    private var photoCapturedAt: Date?

    /// Reports that have not reached the relay yet, on disk (#73). Everything a
    /// person files goes in here BEFORE it is sent, so losing the network
    /// cannot lose the report.
    private let queue = ReportQueue.applicationDefault()

    /// The address the city answers to, on this phone (#163). Beside the
    /// queue, and read once at startup rather than on every screen.
    private let contact = ContactDetails.applicationDefault()
    /// The device's preferences, kept beside the address (#179). Read at
    /// capture time, never sent anywhere.
    private let settings = Settings.applicationDefault()

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

        // Our words for what the relay answered (#77). Optional for the same
        // reason as the labels: without it the screen shows the relay's own
        // body alone, which is a worse screen rather than a dead app.
        relayOutcomes = Bundle.main.url(forResource: "relay-outcomes.json", withExtension: nil)
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? RelayOutcomes.parse($0) }

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

        // The address the city answers to, from the last time somebody typed
        // one on this phone (#163). Absent on a fresh install, which is the
        // one walk where it has to be asked for.
        if let storedEmail = contact.read() {
            state.email = storedEmail
            state.emailValid = ContactDetails.isValid(storedEmail)
        } else {
            // A phone with no address is a phone that has not been asked yet.
            // Everything else starts where it always did.
            state.screen = .onboarding
        }
        // The save toggle's honest state at startup: the permission answer
        // that cannot change without the system Settings app.
        state.saveToGallery = settings.saveToGallery()
        state.galleryBlocked = state.saveToGallery && PhotoLibrarySaver.isDeniedForGood

        // The telemetry channel is fire-and-forget by contract
        // (data/relay-events.json): it must never affect the report. One
        // instance per launch, configured at the single place the app starts,
        // and the app-opened event belongs to that moment.
        Telemetry.shared.appVersion = Self.currentAppVersion
        Telemetry.shared.track(.appOpened)

        #if DEBUG
        applyUITestSeamIfAsked()
        #endif

        refreshQueuedCount()
        network.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.deliverQueued() }
        }
        network.start(queue: DispatchQueue(label: "is.borgarland.connectivity"))
    }

    #if DEBUG
    /// A way onto the details screen for a UI test, and no way anywhere else.
    ///
    /// The app opens on the camera and a simulator has no camera, so every
    /// screen past the first is unreachable to XCUITest without a seam. That
    /// is why #110 — a keyboard covering the button under a text field — was
    /// invisible to every check this project had and was found by a person
    /// holding a phone.
    ///
    /// Inside `#if DEBUG` because a launch argument that fabricates a report
    /// must not exist in a build anybody can install. `ios-release.yml` builds
    /// Release, where this method is not compiled at all, so the seam cannot
    /// ship even if the argument were somehow passed.
    ///
    /// The photograph is four bytes of JPEG marker rather than a real image:
    /// nothing on this screen decodes it, and the test is about the keyboard,
    /// not the picture. Nothing is ever sent — reaching the summary screen
    /// still requires the same guards it always did.
    private func applyUITestSeamIfAsked() {
        applyOnboardingSeamIfAsked()
        guard ProcessInfo.processInfo.arguments.contains("-uiTestDetailsScreen") else { return }
        guard let first = state.categories.first else { return }
        state.photo = Photo(
            bytes: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            name: "uitest.jpg",
            mime: "image/jpeg",
            rotationDegrees: 0
        )
        state.coordinate = Coordinate(latitude: 64.14658919, longitude: -21.93279823)
        state.locationSource = "UI test"
        state.selectedSlug = first.slug
        // Seeded like the photo and the coordinate: the details screen's
        // control is enabled only with an address (#163), and a UI test about
        // the KEYBOARD covering that control must not be measuring a button
        // disabled for an unrelated reason. Never reachable outside DEBUG.
        state.email = "uitest@example.is"
        state.emailValid = ContactDetails.isValid(state.email)
        state.screen = .details
    }

    /// A way onto the ONBOARDING screen for a UI test, and no way anywhere
    /// else.
    ///
    /// It exists because that screen is otherwise unreachable to a test on the
    /// second run. Onboarding is shown when the phone holds no address, and it
    /// writes one the moment somebody leaves it — so a simulator, whose
    /// container survives between runs, shows the screen once and the camera
    /// forever after. A test that quietly starts on the camera would pass by
    /// asserting nothing.
    ///
    /// So the seam CLEARS the stored address rather than just setting the
    /// screen: the screen and the condition that produces it are made to agree,
    /// which also means the run exercises the real startup rule instead of a
    /// state fabricated around it.
    ///
    /// Inside `#if DEBUG` for the same reason the details seam is: an argument
    /// that erases something a person typed must not exist in a build anybody
    /// can install. `ios-release.yml` builds Release, where this is not
    /// compiled at all.
    private func applyOnboardingSeamIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestOnboardingScreen") else { return }
        contact.write(nil)
        // Assigned directly, like the details seam above: this runs inside
        // init, where `update`'s publish-on-change wrapper has no subscriber
        // to notify yet.
        state.email = ""
        state.emailValid = false
        state.screen = .onboarding
    }
    #endif

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
            state.locationDenied = false
            state.locationError = nil
        }
        // The gallery copy, when the person wants one (#179). On its own
        // task: the permission dialog and the library write must never hold
        // up the report, and a failed save is not a failed capture.
        if settings.saveToGallery() {
            Task {
                await PhotoLibrarySaver.save(data: bytes)
            }
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

    /// `permanentlyDenied` is the caller's answer to a question this model
    /// cannot ask the platform: whether the refusal can still change its mind.
    /// A screen that treats the two the same offers a button that can only
    /// ever return the same refusal, which is what the first field test walked
    /// into (#76).
    func onLocationPermissionResult(_ granted: Bool, permanentlyDenied: Bool = false) {
        Telemetry.shared.track(.locationPermission(granted: granted))
        if granted {
            requestDeviceFix()
        } else {
            Telemetry.shared.track(.locationFailed(elapsedMs: elapsedSincePhoto(), reason: .permission))
            update { state in
                state.needsLocationPermission = false
                state.locating = false
                state.locationDenied = permanentlyDenied
                state.locationError = permanentlyDenied
                    ? "Staðsetningarleyfi er lokað fyrir Borgarland í stillingum símans. Ábending þarf hnit, annars getur enginn brugðist við henni, og leyfið verður ekki opnað nema í stillingunum."
                    : "Staðsetningarleyfi vantar. Borgin samþykkir ábendingu án hnitanna, en þá getur enginn brugðist við henni."
            }
        }
    }

    /// Someone may have opened the permission in system settings and come
    /// back. If they did, the walk carries on from where it stopped rather
    /// than making them find a button (#76).
    func recheckLocationPermission() {
        let stopped: LocationPermission = state.locationDenied ? .deniedForGood : .unanswered
        guard LocationPermission.shouldResume(after: stopped, nowGranted: DeviceFix.shared.isAuthorized) else {
            return
        }
        Telemetry.shared.track(.locationPermission(granted: true))
        update { state in
            state.locationDenied = false
            state.locationError = nil
        }
        requestDeviceFix()
    }

    func requestDeviceFix() {
        update { state in
            state.locating = true
            state.locationError = nil
            state.locationDenied = false
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
                    state.locationError = "Myndin ber enga GPS staðsetningu og tækið fékk enga staðsetningu. Ekki er hægt að halda áfram án hnitanna, enda getur enginn brugðist við ábendingu án staðsetningar."
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
            state.locationDenied = false
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

    /// Leaves the one-time onboarding screen for the camera, having written
    /// the address down. No telemetry: see OnboardingScreen for why the event
    /// allowlist is deliberately not extended for this.
    func completeOnboarding() {
        guard ContactDetails.isValid(state.email) else { return }
        let email = ContactDetails.normalise(state.email)
        contact.write(email)
        update { state in
            state.email = email
            state.screen = .camera
        }
    }

    /// No telemetry of any kind. The event allowlist names no free-text field
    /// (data/relay-events.json) and this is the most personal thing the app
    /// holds, so not even its length travels — a length is a small thing to
    /// know about an address and there is no question it would answer.
    func onEmailChange(_ text: String) {
        update { state in
            state.email = text
            state.emailValid = ContactDetails.isValid(text)
        }
    }

    func continueToSummary() {
        let s = state
        guard let facts,
              facts.categories.contains(where: { $0.slug == s.selectedSlug }),
              let coord = s.coordinate,
              !s.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              // Required by us, not by the city (#163). Refused here rather
              // than at the send, so nobody reaches a summary screen for a
              // report that cannot go out.
              ContactDetails.isValid(s.email)
        else { return }
        // The city's own map bounds are for its form's map view and cover
        // more than the municipality; the registry check that would tell a
        // Kópavogur coordinate from a Reykjavík one lives in the relay. This
        // is the Kotlin's bounds comparison, ported unchanged.
        let outside = coord.latitude < facts.map.bounds.south || coord.latitude > facts.map.bounds.north
            || coord.longitude < facts.map.bounds.west || coord.longitude > facts.map.bounds.east
        Telemetry.shared.track(.screenLeft(screen: .details, completed: true))
        // Written down now rather than after a successful send: the address is
        // the device's, and a walk that fails to send should still not make
        // the next one retype it.
        let email = ContactDetails.normalise(s.email)
        contact.write(email)
        update { state in
            state.email = email
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
        // The address survives a new report: it belongs to the phone, not to
        // the ábending that was just filed (#163).
        let email = state.email
        let emailValid = state.emailValid
        state = ReportUiState(
            categories: categories,
            categoryDisplay: categoryDisplay,
            categoryHelp: categoryHelp,
            descriptionMaxLength: descriptionMaxLength,
            email: email,
            emailValid: emailValid,
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
                state.deliveryNote = "relay-request.json vantar eða er ólæsilegt í assets. Ekki er hægt að senda."
            }
            return
        }
        update { state in
            state.sendOutcome = nil
            state.deliveryNote = nil
        }

        // Already written down, so this press is a RETRY of that report rather
        // than a second one. Without this the same ábending is queued again
        // every time somebody presses the button after a failed attempt, and
        // every copy goes out when the network returns. The button is disabled
        // only while a delivery is running, so the press is available the
        // moment an attempt gives up (#85 is the same duplicate after a
        // SUCCESS, and is a different hole).
        if state.currentReportIsQueued {
            deliverQueued()
            return
        }

        do {
            currentReportID = try queue.enqueue(payload).id
            update { state in state.currentReportIsQueued = true }
            refreshQueuedCount()
            deliverQueued()
        } catch ReportQueue.QueueError.full(let reports, _) {
            // The queue is at its bound (#82). Not a failure to fix by trying
            // again: something has to go out or be thrown away first, and the
            // person is the only one who can decide which. So this says so and
            // does NOT send, because a send that cannot be retried is how the
            // report was lost in the first place.
            update { state in
                state.deliveryNote = "\(reports) ábendingar bíða sendingar og fleiri komast ekki fyrir. Sendu þær sem bíða, eða eyddu einhverri, og reyndu svo aftur."
            }
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
    /// no-op, so two deliveries never run at once.
    ///
    /// That is not on its own what stops a report going twice. Nothing here
    /// prevents the SAME report being queued a second time; `sendToRelay`
    /// refuses that, and #85 is the case neither of them covers.
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
    /// has to wait. `handled` is not bookkeeping for its own sake: a removal
    /// that failed would leave the same entry at the head of the queue, and
    /// without this the loop would take it again forever.
    ///
    /// It ends the loop; it does not fix the removal. An entry that survives
    /// its own removal is re-read by the NEXT drain and sent a second time,
    /// and the relay has no idempotency key to catch that.
    private func drainQueue(contract: RelayRequestFile) async {
        var handled: Set<String> = []
        while let report = queue.pending().first(where: { !handled.contains($0.id) }) {
            if Task.isCancelled { return }
            handled.insert(report.id)

            let payload: Payload
            do {
                // The address comes from the phone, not from the record:
                // a report that waited goes out to the address the phone
                // holds now (#163).
                payload = try queue.payload(for: report, email: emailToSend())
            } catch {
                // The bytes are gone, so this entry can never be built. Left
                // alone it would sit at the head of the queue and stop every
                // report behind it.
                queue.remove(report.id)
                // And if it was the one on screen, the screen must stop saying
                // it is waiting and stop offering to discard something that is
                // already gone.
                if report.id == currentReportID {
                    currentReportID = nil
                    update { state in
                        state.currentReportIsQueued = false
                        state.deliveryNote = "Myndin fannst ekki lengur í símanum, svo ekki var hægt að senda ábendinguna. Taktu nýja mynd."
                    }
                }
                refreshQueuedCount()
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
    private func sendUnqueued(_ unidentified: Payload) {
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
        // The token is the report's id on the wire as well as the screen's
        // claim on the result. It was only ever the second, which left the one
        // path where an ambiguous timeout is MOST likely — the disk was just
        // failing — as the one path the relay could not deduplicate (#88).
        let token = RandomHex.id()
        currentReportID = token
        let payload = Payload(
            categorySlug: unidentified.categorySlug,
            latitude: unidentified.latitude,
            longitude: unidentified.longitude,
            description: unidentified.description,
            photos: unidentified.photos,
            email: unidentified.email,
            reportId: token,
            session: unidentified.session,
        )
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

    /// What the relay's answer means for a report that is waiting.
    ///
    /// The decision itself lives in BorgarlandCore, where it has tests (#89);
    /// this only widens it by the one case the package cannot know about, a
    /// person pressing cancel.
    private static func disposition(of result: RelayClient.Result) -> Disposition {
        switch RelayDisposition.of(status: result.status, ok: result.ok) {
        case .sent: return .sent
        case .refused: return .refused
        case .waiting: return .waiting
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
                state.sendOutcome = result.map { result in
                    SendOutcome(
                        outcome: RelayOutcomes.sentence(
                            status: result.status,
                            body: result.body,
                            in: relayOutcomes
                        ),
                        raw: "HTTP \(result.status)\n\(result.body)",
                        status: result.status,
                        ok: result.ok
                    )
                }
            case .waiting:
                state.sendOutcome = nil
                // Only the queued path may promise that it waits. On the
                // fallback path the report was never written down, nothing
                // retries it, and saying otherwise is the assurance that makes
                // somebody leave the screen and lose it.
                state.deliveryNote = state.currentReportIsQueued
                    ? "Ekki náðist samband við þjónustu Borgarlands. Ábendingin bíður í símanum og fer af stað um leið og netið kemur aftur."
                    : "Ekki náðist samband við þjónustu Borgarlands, og ekki tókst að geyma ábendinguna í símanum. Hún bíður ekki, svo ekki loka appinu: reyndu að senda aftur."
            case .cancelled:
                state.sendOutcome = nil
                state.deliveryNote = state.currentReportIsQueued
                    ? "Hætt við sendingu. Ábendingin bíður í símanum og fer af stað þegar reynt er aftur."
                    : "Hætt við sendingu. Ábendingin er ekki geymd í símanum, svo hún bíður ekki: reyndu að senda aftur."
            }
        }
    }

    /// The address as it goes on the wire, or nil when there is none. One
    /// accessor rather than the same trim-and-nil expression at each call
    /// site, so a report and a queued retry cannot disagree about it.
    private func emailToSend() -> String? {
        let value = ContactDetails.normalise(state.email)
        return value.isEmpty ? nil : value
    }
    /// The gallery-save toggle (#179). Device state, written like the
    /// address: read at save time, never sent anywhere. `galleryBlocked`
    /// recomputes with it, so a toggle that cannot be honoured is shown as
    /// blocked, not as on.
    func setSaveToGallery(_ save: Bool) {
        settings.setSaveToGallery(save)
        state.saveToGallery = save
        state.galleryBlocked = save && PhotoLibrarySaver.isDeniedForGood
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
            photos: s.photo.map { [$0] } ?? [],
            email: emailToSend(),
            session: Telemetry.shared.sessionID,
        )
    }
}
