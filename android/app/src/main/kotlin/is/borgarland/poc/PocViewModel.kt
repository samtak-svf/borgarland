package `is`.borgarland.poc

import android.app.Application
import `is`.borgarland.poc.net.RelayClient
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import `is`.borgarland.poc.data.Category
import `is`.borgarland.poc.data.Facts
import `is`.borgarland.poc.data.FactsFile
import `is`.borgarland.poc.data.RelayRequest
import `is`.borgarland.poc.data.RelayRequestFile
import `is`.borgarland.poc.exif.ExifGps
import `is`.borgarland.poc.location.DeviceFix
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

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
    val descriptionMaxLength: Int = 2500,
    val photo: Photo? = null,
    val photoError: String? = null,
    val coordinate: Coordinate? = null,
    val locationSource: String? = null,
    val locating: Boolean = false,
    val needsLocationPermission: Boolean = false,
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

    // The relay request contract, from the same assets copy the facts file
    // uses. Sending is impossible without it: RelayClient writes parts under
    // exactly the names this file carries.
    private var relayRequest: RelayRequestFile? = null

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
        if (parsed == null) {
            _state.update {
                it.copy(factsError = "reykjavik-form.json vantar eða er ólæsilegt í assets. Ekki er hægt að halda áfram.")
            }
        } else {
            facts = parsed
            _state.update {
                it.copy(
                    categories = parsed.categories,
                    descriptionMaxLength = parsed.fields.description.maxLength,
                )
            }
        }
    }

    fun onPhotoCaptured(bytes: ByteArray, rotationDegrees: Int) {
        val photo = Photo(bytes = bytes, name = "mynd.jpg", mime = "image/jpeg", rotationDegrees = rotationDegrees)
        _state.update {
            it.copy(
                photo = photo,
                photoError = null,
                coordinate = null,
                locationSource = null,
                locating = false,
                needsLocationPermission = false,
                locationError = null,
            )
        }
        val gps = ExifGps.read(bytes)
        if (gps != null && isUsableCoordinate(gps.lat, gps.lng)) {
            _state.update {
                it.copy(
                    coordinate = Coordinate(gps.lat, gps.lng),
                    locationSource = "EXIF GPS úr mynd",
                    screen = Screen.Details,
                )
            }
        } else {
            // Photo carries no usable GPS: ask the device for a fix.
            _state.update { it.copy(needsLocationPermission = true) }
        }
    }

    fun onPhotoError(message: String) {
        _state.update { it.copy(photoError = message) }
    }

    fun onLocationPermissionResult(granted: Boolean) {
        if (granted) {
            requestDeviceFix()
        } else {
            _state.update {
                it.copy(
                    needsLocationPermission = false,
                    locating = false,
                    locationError = "Staðsetningarleyfi vantar. Borgin samþykkir skýrslu án hnitanna, en þá getur enginn brugðist við henni.",
                )
            }
        }
    }

    fun requestDeviceFix() {
        _state.update { it.copy(locating = true, locationError = null, needsLocationPermission = false) }
        viewModelScope.launch {
            val location = DeviceFix(getApplication()).request()
            _state.update {
                if (location != null && isUsableCoordinate(location.latitude, location.longitude)) {
                    it.copy(
                        locating = false,
                        coordinate = Coordinate(location.latitude, location.longitude),
                        locationSource = "Tækjastaðsetning (GPS)",
                        screen = Screen.Details,
                    )
                } else {
                    it.copy(
                        locating = false,
                        locationError = "Myndin ber enga GPS staðsetningu og tækið fékk enga staðsetningu. Ekki er hægt að halda áfram án hnitanna, enda getur enginn brugðist við skýrslu án staðsetningar.",
                    )
                }
            }
        }
    }

    fun retakePhoto() {
        _state.update {
            it.copy(
                photo = null,
                photoError = null,
                coordinate = null,
                locationSource = null,
                locating = false,
                needsLocationPermission = false,
                locationError = null,
            )
        }
    }

    fun selectCategory(slug: String) {
        _state.update { it.copy(selectedSlug = slug) }
    }

    fun onDescriptionChange(text: String) {
        val max = _state.value.descriptionMaxLength
        _state.update { it.copy(description = if (text.length > max) text.take(max) else text) }
    }

    fun continueToSummary() {
        val s = _state.value
        val category = facts?.categories?.firstOrNull { it.slug == s.selectedSlug } ?: return
        val coord = s.coordinate ?: return
        if (s.description.isBlank()) return
        val f = facts ?: return
        val outside = coord.lat < f.map.bounds.south || coord.lat > f.map.bounds.north ||
            coord.lng < f.map.bounds.west || coord.lng > f.map.bounds.east
        _state.update { it.copy(screen = Screen.Summary, outOfBounds = outside) }
    }

    fun startOver() {
        _state.update {
            PocUiState(categories = it.categories, descriptionMaxLength = it.descriptionMaxLength)
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
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) { RelayClient.send(payload, contract) }
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
