package `is`.borgarland

/**
 * The one rule this project enforces that the city does not. The city accepts
 * a report with no coordinate (data/reykjavik-form.json,
 * validation.onlyDescriptionIsEnforced) and nobody could act on it, so this
 * POC refuses to continue without one. Rejects anything non-finite and
 * anything outside WGS84 decimal degrees, mirroring send-report.mjs.
 */
fun isUsableCoordinate(lat: Double, lng: Double): Boolean =
    lat.isFinite() && lng.isFinite() && lat in -90.0..90.0 && lng in -180.0..180.0
