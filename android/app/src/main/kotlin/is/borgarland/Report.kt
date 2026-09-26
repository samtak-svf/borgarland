package `is`.borgarland

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
    /**
     * Where the city sends its confirmation, and the only channel it has back
     * to the person who filed this (#163). Held on the device rather than
     * asked for each time (data/ContactDetails.kt), and required by us though
     * the city treats it as optional — the same override the coordinate gets.
     *
     * Nullable because the type has to be able to express a report without
     * one; the contract's `required` flag is what refuses to send it, in
     * net/RelayClient.kt, so there is exactly one gate rather than two that
     * can disagree.
     */
    val email: String? = null,
    /**
     * Which report this IS, so sending it twice cannot file it twice (#88).
     * The relay stores it as the row's own id and answers a repeat with the row
     * it already has. Optional because the relay generates one when the app
     * sends none, which is what an older build does.
     */
    val reportId: String? = null,
    /**
     * Which launch of the app filed this report (#186) — the same per-launch
     * session id the telemetry envelope carries, so the relay can join the
     * report row to the events of the walk that produced it. Optional because
     * the contract says so: a build that predates the field sends none.
     */
    val session: String? = null,
    /**
     * How wrong the device fix behind the coordinate might be, in whole metres
     * (#223, decision 0023). The relay appends it to the block the crew reads,
     * so a distance rounded to ten metres is not mistaken for a ten-metre fix.
     *
     * Null in two real cases rather than as a precaution: a coordinate that
     * came from the photograph's EXIF, which carries no radius (decision 0023,
     * point 4), and a build older than the relay that first accepted the part.
     * Nothing on either side gates on it.
     */
    val accuracyM: Int? = null,
) {
    /** Formatted the way send-report.mjs formats them: shortest round-trip decimal. */
    val latitudeText: String get() = latitude.toString()
    val longitudeText: String get() = longitude.toString()
}
