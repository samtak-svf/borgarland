package `is`.borgarland

import `is`.borgarland.data.FollowUps
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The follow-up interval (#57, decision 0013).
 *
 * Only the boundary is tested here, deliberately. The rest of `FollowUps` is
 * file-backed and needs a `Context`, which a JVM unit test has no way to give
 * it; pretending otherwise with a mock would test the mock. What a test CAN
 * pin is the arithmetic, and that is where an off-by-one would hide: a wrong
 * unit turns fourteen days into fourteen seconds and every report is asked
 * about immediately.
 */
class FollowUpsTest {
    private val day = 24L * 60L * 60L * 1000L

    @Test
    fun `the interval is fourteen days`() {
        assertEquals(14, FollowUps.ASK_AFTER_DAYS)
    }

    @Test
    fun `a report sent just now is not due`() {
        val now = 1_700_000_000_000L
        assertFalse(FollowUps.isDue(sentAtMs = now, nowMs = now))
    }

    @Test
    fun `a report is not due one millisecond before the interval`() {
        val now = 1_700_000_000_000L
        assertFalse(FollowUps.isDue(sentAtMs = now - (14 * day) + 1, nowMs = now))
    }

    @Test
    fun `a report is due exactly at the interval`() {
        val now = 1_700_000_000_000L
        assertTrue(FollowUps.isDue(sentAtMs = now - (14 * day), nowMs = now))
    }

    @Test
    fun `an older report stays due`() {
        val now = 1_700_000_000_000L
        assertTrue(FollowUps.isDue(sentAtMs = now - (90 * day), nowMs = now))
    }

    /**
     * A clock that went backwards must not make everything due. Phones do
     * change their clock, and the consequence of getting this wrong is asking
     * about every report at once.
     */
    @Test
    fun `a report sent in the future is not due`() {
        val now = 1_700_000_000_000L
        assertFalse(FollowUps.isDue(sentAtMs = now + (5 * day), nowMs = now))
    }
}
