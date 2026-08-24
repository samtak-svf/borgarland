package `is`.borgarland

import `is`.borgarland.data.FollowUps
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

/**
 * The round trip, which nothing covered until #129.
 *
 * These reach the real file logic through the `File`-based twins, so they test
 * the store rather than a mock of it. A temporary directory stands in for
 * `filesDir`, which is the only thing a Context was ever needed for.
 */
class FollowUpsStoreTest {
    private val day = 24L * 60L * 60L * 1000L
    private val now = 1_700_000_000_000L

    private fun dir(): java.io.File =
        java.nio.file.Files.createTempDirectory("follow-ups").toFile()

    @Test
    fun `a recorded report becomes due after the interval and not before`() {
        val d = dir()
        FollowUps.record(d, "a".repeat(32), "ruslafotur", now)
        assertNull(FollowUps.due(d, now + (13 * day)))
        assertEquals("a".repeat(32), FollowUps.due(d, now + (14 * day))?.id)
    }

    @Test
    fun `an answer survives a failed post and is offered for retry`() {
        val d = dir()
        val id = "b".repeat(32)
        FollowUps.record(d, id, "nidurfoll", now)
        FollowUps.markAnswered(d, id, fixed = true)
        // The relay was never told, so the answer is still owed.
        assertEquals(listOf(FollowUps.Unposted(id, true)), FollowUps.unposted(d))
        FollowUps.markPosted(d, id)
        assertTrue(FollowUps.unposted(d).isEmpty())
    }

    @Test
    fun `an answered report is not asked again`() {
        val d = dir()
        val id = "c".repeat(32)
        FollowUps.record(d, id, "gras-og-grodur", now)
        assertEquals(id, FollowUps.due(d, now + (14 * day))?.id)
        FollowUps.markAnswered(d, id, fixed = false)
        assertNull(FollowUps.due(d, now + (14 * day)))
    }

    @Test
    fun `a dismissal is asked once and owes the relay nothing`() {
        val d = dir()
        val id = "d".repeat(32)
        FollowUps.record(d, id, "holur-i-gotu", now)
        FollowUps.markDismissed(d, id)
        assertNull(FollowUps.due(d, now + (14 * day)))
        assertTrue(FollowUps.unposted(d).isEmpty())
    }

    @Test
    fun `only the oldest due report is offered, one question at a time`() {
        val d = dir()
        FollowUps.record(d, "e".repeat(32), "ruslafotur", now)
        FollowUps.record(d, "f".repeat(32), "nidurfoll", now + day)
        assertEquals("e".repeat(32), FollowUps.due(d, now + (20 * day))?.id)
    }

    @Test
    fun `recording the same id twice does not create a second row`() {
        val d = dir()
        val id = "g".repeat(32)
        FollowUps.record(d, id, "ruslafotur", now)
        FollowUps.record(d, id, "ruslafotur", now)
        assertEquals(1, FollowUps.counts(d).first)
    }

    /**
     * The dangerous one. `read` treats unparseable content as an empty list,
     * which the original called resilience; the effect was that a truncated
     * file silently erased every remembered report and the next write made the
     * loss permanent. Writes are atomic now, so the only way to see a corrupt
     * file is to write one by hand.
     */
    @Test
    fun `a corrupt file does not throw and does not take the app down`() {
        val d = dir()
        java.io.File(d, "follow-ups.json").writeText("{ this is not json")
        assertNull(FollowUps.due(d, now))
        assertTrue(FollowUps.unposted(d).isEmpty())
        // And the store still works afterwards.
        FollowUps.record(d, "h".repeat(32), "ruslafotur", now)
        assertEquals("h".repeat(32), FollowUps.due(d, now + (14 * day))?.id)
    }

    @Test
    fun `no temporary file is left behind after a write`() {
        val d = dir()
        FollowUps.record(d, "i".repeat(32), "ruslafotur", now)
        assertTrue(java.io.File(d, "follow-ups.json").exists())
        assertTrue(!java.io.File(d, "follow-ups.json.tmp").exists())
    }
}
