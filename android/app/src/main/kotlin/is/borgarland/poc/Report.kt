package `is`.borgarland.poc

/**
 * What would be posted, field for field, to OUR relay. The city's type,
 * display name and summary are derived by the relay's adapter from the slug
 * (worker/src/adapters/reykjavik.ts); this app never sees or sends them
 * (AGENTS.md: the adapter is the only place allowed to know the city's
 * vocabulary). The wire names of the parts are the contract's field keys
 * (data/relay-request.json), applied in net/RelayClient.kt.
 *
 * The POC only ever displays this and sends it to the relay; it has no
 * capability to reach the city (decisions/0002).
 */
data class Photo(
    val bytes: ByteArray,
    val name: String,
    val mime: String,
    val rotationDegrees: Int,
) {
    val sizeBytes: Int get() = bytes.size
}

data class Payload(
    /** Category slug, one of the twelve in the facts file. */
    val categorySlug: String,
    val latitude: Double,
    val longitude: Double,
    val description: String,
    val photos: List<Photo>,
) {
    /** Formatted the way send-report.mjs formats them: shortest round-trip decimal. */
    val latitudeText: String get() = latitude.toString()
    val longitudeText: String get() = longitude.toString()
}
