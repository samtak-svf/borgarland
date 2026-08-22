package `is`.borgarland.poc

/**
 * What would be posted, field for field. The POC only ever displays this; the
 * send step does not exist in this app, by design (decisions/0002 and the
 * AGENTS.md rule that this app has no capability to reach the city).
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
    val type: String,
    val category: String,
    val summary: String,
    val lat: Double,
    val lng: Double,
    val description: String,
    val files: List<Photo>,
) {
    /** Formatted the way send-report.mjs formats them: shortest round-trip decimal. */
    val latText: String get() = lat.toString()
    val lngText: String get() = lng.toString()
}
