package `is`.borgarland

import kotlin.math.roundToInt

/**
 * The one rule this project enforces that the city does not. The city accepts
 * a report with no coordinate (data/reykjavik-form.json,
 * validation.onlyDescriptionIsEnforced) and nobody could act on it, so this
 * POC refuses to continue without one. Rejects anything non-finite and
 * anything outside WGS84 decimal degrees, mirroring send-report.mjs.
 */
fun isUsableCoordinate(lat: Double, lng: Double): Boolean =
    lat.isFinite() && lng.isFinite() && lat in -90.0..90.0 && lng in -180.0..180.0

/**
 * The radius a REPORT states for a device fix, in whole metres, or null when
 * the fix carries none (#223). Null rather than 0 because the relay prints the
 * number beside the coordinate the crew reads, and "±0 m" would describe a
 * perfect fix: the one claim a fix with no radius cannot support.
 *
 * Android's `Location.getAccuracy()` answers 0.0 when `hasAccuracy()` is
 * false, so the flag is read rather than the number trusted. A non-finite or
 * negative value is no radius either. The telemetry event keeps its own
 * clamped value, because the event contract's `accuracyM` is not optional.
 */
fun reportedAccuracyM(hasAccuracy: Boolean, accuracyMetres: Float): Int? =
    if (hasAccuracy && accuracyMetres.isFinite() && accuracyMetres >= 0f) accuracyMetres.roundToInt() else null
