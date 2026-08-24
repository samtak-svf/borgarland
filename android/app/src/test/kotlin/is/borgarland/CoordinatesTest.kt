package `is`.borgarland

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The one rule this project enforces that the city does not: a usable
 * coordinate is present, finite and inside WGS84 bounds. A non-finite value
 * can reach this guard via EXIF rationals with a zero denominator, so it is
 * rejected rather than assumed impossible.
 */
class CoordinatesTest {

    @Test
    fun rejectsNonFinite() {
        assertFalse(isUsableCoordinate(Double.NaN, 0.0))
        assertFalse(isUsableCoordinate(0.0, Double.POSITIVE_INFINITY))
        assertFalse(isUsableCoordinate(Double.NEGATIVE_INFINITY, -22.0))
    }

    @Test
    fun rejectsOutOfWgs84Range() {
        assertFalse(isUsableCoordinate(91.0, 0.0))
        assertFalse(isUsableCoordinate(-91.0, 0.0))
        assertFalse(isUsableCoordinate(0.0, 181.0))
        assertFalse(isUsableCoordinate(0.0, -181.0))
    }

    @Test
    fun acceptsReykjavikCoordinate() {
        assertTrue(isUsableCoordinate(64.1467, -21.9429))
        assertTrue(isUsableCoordinate(0.0, 0.0)) // finite and in range; the map-bounds warning handles the rest
    }
}
