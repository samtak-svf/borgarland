package `is`.borgarland

import `is`.borgarland.data.LocationPermission
import `is`.borgarland.data.RelayDisposition
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #89. Both of these decide something a person meets, and neither had a test:
 * they lived in PocViewModel, which needs an Application and therefore has no
 * plain JVM test, so a revert of #76 left every test in the repository green.
 * The Swift counterpart is DecisionsTest.swift, case for case.
 */
class DecisionsTest {

    @Test
    fun `the relays own judgement is trusted`() {
        assertEquals(RelayDisposition.SENT, RelayDisposition.of(201, true))
        assertEquals(RelayDisposition.SENT, RelayDisposition.of(200, true))
    }

    @Test
    fun `an answer that would be the same next time stops the report waiting`() {
        assertEquals(RelayDisposition.REFUSED, RelayDisposition.of(400, false))
        assertEquals(RelayDisposition.REFUSED, RelayDisposition.of(413, false))
        assertEquals(RelayDisposition.REFUSED, RelayDisposition.of(409, false))
    }

    @Test
    fun `no answer and try later both keep the report`() {
        assertEquals(RelayDisposition.WAITING, RelayDisposition.of(0, false))
        assertEquals(RelayDisposition.WAITING, RelayDisposition.of(408, false))
        assertEquals(RelayDisposition.WAITING, RelayDisposition.of(429, false))
        assertEquals(RelayDisposition.WAITING, RelayDisposition.of(500, false))
        assertEquals(RelayDisposition.WAITING, RelayDisposition.of(503, false))
    }

    @Test
    fun `an unrecognised status keeps the report rather than dropping it`() {
        assertEquals(RelayDisposition.WAITING, RelayDisposition.of(302, false))
        assertEquals(RelayDisposition.WAITING, RelayDisposition.of(999, false))
    }

    @Test
    fun `granted is granted whatever else is true`() {
        assertEquals(LocationPermission.GRANTED, LocationPermission.of(granted = true, canAskAgain = false))
        assertEquals(LocationPermission.GRANTED, LocationPermission.of(granted = true, canAskAgain = true))
    }

    /**
     * The distinction #76 exists for. Both are "not granted"; only one can be
     * fixed by asking again.
     */
    @Test
    fun `a refusal the system will revisit is not the same as one it will not`() {
        assertEquals(LocationPermission.UNANSWERED, LocationPermission.of(granted = false, canAskAgain = true))
        assertEquals(LocationPermission.DENIED_FOR_GOOD, LocationPermission.of(granted = false, canAskAgain = false))
    }

    @Test
    fun `the screen is never offered a retry that cannot work`() {
        assertEquals(LocationPermission.Exit.CARRY_ON, LocationPermission.GRANTED.exit)
        assertEquals(LocationPermission.Exit.ASK_AGAIN, LocationPermission.UNANSWERED.exit)
        assertEquals(LocationPermission.Exit.OPEN_SYSTEM_SETTINGS, LocationPermission.DENIED_FOR_GOOD.exit)
    }

    @Test
    fun `the walk resumes only when the reason it stopped is gone`() {
        assertTrue(LocationPermission.shouldResume(LocationPermission.DENIED_FOR_GOOD, nowGranted = true))
        assertFalse(LocationPermission.shouldResume(LocationPermission.DENIED_FOR_GOOD, nowGranted = false))
        assertFalse(LocationPermission.shouldResume(LocationPermission.UNANSWERED, nowGranted = true))
        assertFalse(LocationPermission.shouldResume(LocationPermission.GRANTED, nowGranted = true))
    }

    // #139: the event that records being asked exists to measure the gap
    // between the dialog going up and somebody answering it. A launcher that
    // returns without showing anything is not an ask, and counting it fills the
    // measurement with values that were never waits.

    @Test
    fun `a granted permission prompts nothing`() {
        assertFalse(LocationPermission.willPrompt(granted = true, canAskAgain = true, askedBefore = false))
        assertFalse(LocationPermission.willPrompt(granted = true, canAskAgain = false, askedBefore = true))
    }

    @Test
    fun `the first ask on a fresh install prompts`() {
        // No rationale and no memory of asking: this is the first dialog, not a
        // refusal. Reading it the other way is #76 one question further back.
        assertTrue(LocationPermission.willPrompt(granted = false, canAskAgain = false, askedBefore = false))
    }

    @Test
    fun `a soft refusal still prompts`() {
        assertTrue(LocationPermission.willPrompt(granted = false, canAskAgain = true, askedBefore = true))
    }

    @Test
    fun `a permanent refusal prompts nothing`() {
        // The launcher answers immediately with no dialog. This is the case the
        // unguarded emit re-counted on every photo carrying no usable EXIF GPS.
        assertFalse(LocationPermission.willPrompt(granted = false, canAskAgain = false, askedBefore = true))
    }

    @Test
    fun `the memory is the only thing separating the first ask from the last`() {
        // Same platform answer, opposite meaning. Without askedBefore the two
        // are indistinguishable, which is the whole reason LocationAsks exists.
        assertTrue(LocationPermission.willPrompt(granted = false, canAskAgain = false, askedBefore = false))
        assertFalse(LocationPermission.willPrompt(granted = false, canAskAgain = false, askedBefore = true))
    }
}
