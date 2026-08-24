package `is`.borgarland

import `is`.borgarland.data.LocationAsks
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The round trip, through the File twin rather than a Context, on the pattern
 * FollowUps settled on in #129: reaching filesDir needs a Context, and mocking
 * one would test the mock.
 *
 * What this pins is the only property the file has to have (#139): it says no
 * before the first ask and yes forever after, because that is the difference
 * Android itself will not report.
 */
class LocationAsksTest {
    private fun dir() = java.nio.file.Files.createTempDirectory("location-asks").toFile()

    @Test
    fun `a fresh install has never asked`() {
        assertFalse(LocationAsks.asked(dir()))
    }

    @Test
    fun `an ask is remembered`() {
        val dir = dir()
        LocationAsks.remember(dir)
        assertTrue(LocationAsks.asked(dir))
    }

    @Test
    fun `asking twice is still asked`() {
        val dir = dir()
        LocationAsks.remember(dir)
        LocationAsks.remember(dir)
        assertTrue(LocationAsks.asked(dir))
    }

    @Test
    fun `one installs memory is not another's`() {
        val asked = dir()
        LocationAsks.remember(asked)
        assertFalse(LocationAsks.asked(dir()))
    }
}
