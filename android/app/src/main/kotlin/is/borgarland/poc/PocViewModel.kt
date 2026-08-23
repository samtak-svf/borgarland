package `is`.borgarland.poc

import android.app.Application
import android.content.Context
import android.location.LocationManager
import `is`.borgarland.poc.net.RelayClient
import `is`.borgarland.poc.net.Telemetry
import `is`.borgarland.poc.net.TelemetryEvent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import `is`.borgarland.poc.data.Category
import `is`.borgarland.poc.data.Facts
import `is`.borgarland.poc.data.CategoryLabels
import `is`.borgarland.poc.data.CategoryLabelsFile
import `is`.borgarland.poc.data.FactsFile
import `is`.borgarland.poc.data.RelayRequest
import `is`.borgarland.poc.data.RelayRequestFile
import `is`.borgarland.poc.exif.ExifGps
import `is`.borgarland.poc.location.DeviceFix
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlin.math.max
import kotlin.math.roundToInt

sealed interface Screen {
    data object Camera : Screen

    data object Details : Screen

    data object Summary : Screen
}

data class Coordinate(val lat: Double, val lng: Double)

data class PocUiState(
    val screen: Screen = Screen.Camera,
    val factsError: String? = null,
    val categories: List<Category> = emptyList(),
    /**
     * What to SHOW for each slug, and the optional line under it. Resolved in
     * the model so the screen never has to know that an override exists (#40).
     */
    val categoryDisplay: Map<String, String> = emptyMap(),
    val categoryHelp: Map<String, String> = emptyMap(),
    val descriptionMaxLength: Int = 2500,
    val photo: Photo? = null,
    val photoError: String? = null,
    val coordinate: Coordinate? = null,
    val locationSource: String? = null,
    val locating: Boolean = false,
    val needsLocationPermission: Boolean = false,
    /**
     * The permission is denied for good, not merely unanswered. The difference
     * decides which way out the screen offers, because Android does not show
     * the dialog again once someone has refused twice and only app settings
     * can undo it (#76).
     */
    val locationDenied: Boolean = false,
    val locationError: String? = null,
    val selectedSlug: String? = null,
    val description: String = "",
    val outOfBounds: Boolean = false,
    val sending: Boolean = false,
    val sendResult: String? = null,
)

/**
 * Camera first, coordinate guarded, category and description chosen by a
 * person, payload shown and never sent. The facts file is loaded from assets
 * at startup; if it is missing or unparseable the app says so instead of
 * inventing the category list.
 */
class PocViewModel(application: Application) : AndroidViewModel(application) {

    private val _state = MutableStateFlow(PocUiState())
    val state: StateFlow<PocUiState> = _state

    private var facts: FactsFile? = null

    // Our own words for a category, where the city's are wrong for a walker
    // (#40). Optional on purpose: a missing or unreadable file falls back to
    // the city's names, which is a degraded picker rather than a dead app. The
    // facts file is the one that stops everything, because without it there
    // are no categories at all.
    private var categoryLabels: CategoryLabelsFile? = null

    // The relay request contract, from the same assets copy the facts file
    // uses. Sending is impossible without it: RelayClient writes parts under
    // exactly the names this file carries.
    private var relayRequest: RelayRequestFile? = null

    /**
     * When the current photo was captured — the start of the location step.
     * The telemetry channel's `elapsedMs` for the location and category
     * events measures from here (data/relay-events.json).
     */
    private var photoCapturedAtMs: Long? = null

    init {
        val text = runCatching {
            getApplication<Application>().assets.open("reykjavik-form.json")
                .bufferedReader().use { it.readText() }
        }.getOrNull()
        val parsed = text?.let { runCatching { Facts.parse(it) }.getOrNull() }
        val relayText = runCatching {
            getApplication<Application>().assets.open("relay-request.json")
                .bufferedReader().use { it.readText() }
        }.getOrNull()
        relayRequest = relayText?.let { runCatching { RelayRequest.parse(it) }.getOrNull() }
        val labelsText = runCatching {
            getApplication<Application>().assets.open("category-labels.json")
                .bufferedReader().use { it.readText() }
        }.getOrNull()
        categoryLabels = labelsText?.let { runCatching { CategoryLabels.parse(it) }.getOrNull() }
        if (parsed == null) {
            _state.update {
                it.copy(factsError = "reykjavik-form.json vantar eða er ólæsilegt í assets. Ekki er hægt að halda áfram.")
            }
        } else {
            facts = parsed
            _state.update {
                it.copy(
                    categories = parsed.categories,
                    categoryDisplay = parsed.categories.associate {
                        it.slug to CategoryLabels.display(it, categoryLabels)
                    },
                    categoryHelp = parsed.categories.mapNotNull { c ->
                        CategoryLabels.help(c, categoryLabels)?.let { c.slug to it }
                    }.toMap(),
                    descriptionMaxLength = parsed.fields.description.maxLength,
                )
            }
        }

        // No app-opened here, deliberately (#70). This init runs once per
        // ViewModel, and a ViewModel is cleared when its Activity finishes —
        // Back, a swipe out of recents — while the process, and with it the
        // telemetry session, carries on. Emitting here therefore emitted twice
        // in one session. The event marks the start of a session, and a
        // session is a process, so BorgarlandApplication.onCreate owns it.
    }

    /**
     * Whole milliseconds since the current photo was captured; 0 when there
     * is no photo, which callers only hit in paths where one exists.
     */
    private fun elapsedSincePhoto(): Int {
        val start = photoCapturedAtMs ?: return 0
        return max(0, (System.currentTimeMillis() - start).toInt())
    }

    /**
     * Whether any location provider is enabled at all — the contract's
     * timeout/unavailable split for a failed fix.
     */
    private fun locationServicesEnabled(): Boolean {
        val manager = getApplication<Application>().getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        return manager?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true ||
            manager?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true
    }

    fun onPhotoCaptured(bytes: ByteArray, rotationDegrees: Int, captureElapsedMs: Int) {
        val photo = Photo(bytes = bytes, name = "mynd.jpg", mime = "image/jpeg", rotationDegrees = rotationDegrees)
        _state.update {
            it.copy(
                photo = photo,
                photoError = null,
                coordinate = null,
                locationSource = null,
                locating = false,
                needsLocationPermission = false,
                locationDenied = false,
                locationError = null,
            )
        }
        photoCapturedAtMs = System.currentTimeMillis()
        Telemetry.shared.track(
            TelemetryEvent.PhotoCaptured(captureElapsedMs, bytes.size, Telemetry.normalizedMime(photo.mime)),
        )
        val gps = ExifGps.read(bytes)
        if (gps != null && isUsableCoordinate(gps.lat, gps.lng)) {
            // EXIF carries no radius; 0 is the "no radius reported" value.
            Telemetry.shared.track(
                TelemetryEvent.LocationResolved(elapsedSincePhoto(), TelemetryEvent.LocationSource.EXIF, 0),
            )
            Telemetry.shared.track(TelemetryEvent.ScreenLeft(TelemetryEvent.Screen.CAMERA, true))
            _state.update {
                it.copy(
                    coordinate = Coordinate(gps.lat, gps.lng),
                    locationSource = "EXIF GPS úr mynd",
                    screen = Screen.Details,
                )
            }
        } else {
            // The EXIF route yielded nothing for this photo; the flow falls
            // through to the device fix, and the failed attempt is recorded.
            Telemetry.shared.track(
                TelemetryEvent.LocationFailed(elapsedSincePhoto(), TelemetryEvent.LocationFailure.NO_EXIF),
            )
            // Photo carries no usable GPS: ask the device for a fix.
            _state.update { it.copy(needsLocationPermission = true) }
        }
    }

    fun onPhotoError(message: String) {
        _state.update { it.copy(photoError = message) }
    }

    /**
     * [permanentlyDenied] is the caller's answer to a question this view model
     * cannot ask the platform: whether the refusal can still change its mind.
     * A screen that treats the two the same offers a button that can only ever
     * return the same refusal, which is what the first field test walked into
     * on the iOS side (#76).
     */
    fun onLocationPermissionResult(granted: Boolean, permanentlyDenied: Boolean = false) {
        Telemetry.shared.track(TelemetryEvent.LocationPermission(granted))
        if (granted) {
            requestDeviceFix()
        } else {
            Telemetry.shared.track(
                TelemetryEvent.LocationFailed(elapsedSincePhoto(), TelemetryEvent.LocationFailure.PERMISSION),
            )
            _state.update {
                it.copy(
                    needsLocationPermission = false,
                    locating = false,
                    locationDenied = permanentlyDenied,
                    locationError = if (permanentlyDenied) {
                        "Staðsetningarleyfi er lokað fyrir Borgarland í stillingum símans. Ábending þarf hnit, annars getur enginn brugðist við henni, og leyfið verður ekki opnað nema í stillingunum."
                    } else {
                        "Staðsetningarleyfi vantar. Borgin samþykkir ábendingu án hnitanna, en þá getur enginn brugðist við henni."
                    },
                )
            }
        }
    }

    /**
     * Someone may have opened the permission in app settings and come back. If
     * they did, the walk carries on from where it stopped rather than making
     * them find a button (#76).
     */
    fun onLocationPermissionRechecked(granted: Boolean) {
        if (!granted || !_state.value.locationDenied) return
        Telemetry.shared.track(TelemetryEvent.LocationPermission(true))
        _state.update { it.copy(locationDenied = false, locationError = null) }
        requestDeviceFix()
    }

    fun requestDeviceFix() {
        _state.update {
            it.copy(locating = true, locationError = null, locationDenied = false, needsLocationPermission = false)
        }
        viewModelScope.launch {
            val location = DeviceFix(getApplication()).request()
            if (location != null && isUsableCoordinate(location.latitude, location.longitude)) {
                Telemetry.shared.track(
                    TelemetryEvent.LocationResolved(
                        elapsedSincePhoto(),
                        TelemetryEvent.LocationSource.DEVICE,
                        max(0, location.accuracy.roundToInt()),
                    ),
                )
                Telemetry.shared.track(TelemetryEvent.ScreenLeft(TelemetryEvent.Screen.CAMERA, true))
                _state.update {
                    it.copy(
                        locating = false,
                        coordinate = Coordinate(location.latitude, location.longitude),
                        locationSource = "Tækjastaðsetning (GPS)",
                        screen = Screen.Details,
                    )
                }
            } else {
                // A null fix means either nothing answered in time or the
                // platform has location services off entirely; that is
                // exactly the contract's timeout/unavailable split.
                val reason = if (locationServicesEnabled()) {
                    TelemetryEvent.LocationFailure.TIMEOUT
                } else {
                    TelemetryEvent.LocationFailure.UNAVAILABLE
                }
                Telemetry.shared.track(TelemetryEvent.LocationFailed(elapsedSincePhoto(), reason))
                _state.update {
                    it.copy(
                        locating = false,
                        locationError = "Myndin ber enga GPS staðsetningu og tækið fékk enga staðsetningu. Ekki er hægt að halda áfram án hnitanna, enda getur enginn brugðist við ábendingu án staðsetningar.",
                    )
                }
            }
        }
    }

    fun retakePhoto() {
        photoCapturedAtMs = null
        _state.update {
            it.copy(
                photo = null,
                photoError = null,
                coordinate = null,
                locationSource = null,
                locating = false,
                needsLocationPermission = false,
                locationDenied = false,
                locationError = null,
            )
        }
    }

    fun selectCategory(slug: String) {
        Telemetry.shared.track(TelemetryEvent.CategoryChosen(elapsedSincePhoto(), slug))
        _state.update { it.copy(selectedSlug = slug) }
    }

    fun onDescriptionChange(text: String) {
        val max = _state.value.descriptionMaxLength
        _state.update { it.copy(description = if (text.length > max) text.take(max) else text) }
        // The LENGTH of what was typed, never the text (data/relay-events.json).
        Telemetry.shared.track(TelemetryEvent.DescriptionLength(_state.value.description.length))
    }

    fun continueToSummary() {
        val s = _state.value
        val category = facts?.categories?.firstOrNull { it.slug == s.selectedSlug } ?: return
        val coord = s.coordinate ?: return
        if (s.description.isBlank()) return
        val f = facts ?: return
        val outside = coord.lat < f.map.bounds.south || coord.lat > f.map.bounds.north ||
            coord.lng < f.map.bounds.west || coord.lng > f.map.bounds.east
        Telemetry.shared.track(TelemetryEvent.ScreenLeft(TelemetryEvent.Screen.DETAILS, true))
        _state.update { it.copy(screen = Screen.Summary, outOfBounds = outside) }
    }

    fun startOver() {
        Telemetry.shared.track(TelemetryEvent.ScreenLeft(TelemetryEvent.Screen.SUMMARY, false))
        photoCapturedAtMs = null
        _state.update {
            PocUiState(
                categories = it.categories,
                categoryDisplay = it.categoryDisplay,
                categoryHelp = it.categoryHelp,
                descriptionMaxLength = it.descriptionMaxLength,
            )
        }
    }

    /**
     * Sends to OUR relay, which is the only thing this app can reach. The
     * relay decides whether anything reaches the city, and it is in dry run by
     * default. Decision 0002 put that decision on the server precisely so it
     * is one deploy away from being changed rather than an app release.
     */
    fun sendToRelay() {
        val payload = payload() ?: return
        val contract = relayRequest
        if (contract == null) {
            _state.update {
                it.copy(
                    sendResult = "relay-request.json vantar eða er ólæsilegt í assets. Ekki er hægt að senda.",
                )
            }
            return
        }
        _state.update { it.copy(sending = true, sendResult = null) }
        Telemetry.shared.track(TelemetryEvent.SendStarted)
        val startedAt = System.currentTimeMillis()
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) { RelayClient.send(payload, contract) }
            val elapsedMs = max(0, (System.currentTimeMillis() - startedAt).toInt())
            if (result.status != 0) {
                // The relay answered, whatever the status: the send completed.
                Telemetry.shared.track(TelemetryEvent.SendResult(elapsedMs, result.status, result.ok))
            } else {
                val reason = result.failure?.let {
                    when (it) {
                        RelayClient.Failure.CONNECTION -> TelemetryEvent.SendFailure.CONNECTION
                        RelayClient.Failure.TIMEOUT -> TelemetryEvent.SendFailure.TIMEOUT
                        RelayClient.Failure.ENCODING -> TelemetryEvent.SendFailure.ENCODING
                        RelayClient.Failure.OTHER -> TelemetryEvent.SendFailure.OTHER
                    }
                } ?: TelemetryEvent.SendFailure.OTHER
                Telemetry.shared.track(TelemetryEvent.SendFailed(elapsedMs, reason))
            }
            // A natural end point: the events around the report send go now.
            Telemetry.shared.flush()
            _state.update {
                it.copy(
                    sending = false,
                    sendResult = if (result.ok) {
                        "HTTP ${result.status}\n${result.body}"
                    } else if (result.status == 0) {
                        "Náði ekki sambandi við þjónustu Borgarlands (${RelayClient.BASE_URL}): ${result.body}"
                    } else {
                        "HTTP ${result.status}\n${result.body}"
                    },
                )
            }
        }
    }

    fun payload(): Payload? {
        val s = _state.value
        val category = facts?.categories?.firstOrNull { it.slug == s.selectedSlug } ?: return null
        val coord = s.coordinate ?: return null
        return Payload(
            categorySlug = category.slug,
            latitude = coord.lat,
            longitude = coord.lng,
            description = s.description,
            photos = listOfNotNull(s.photo),
        )
    }
}
