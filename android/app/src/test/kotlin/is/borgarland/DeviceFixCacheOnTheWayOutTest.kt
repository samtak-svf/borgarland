package `is`.borgarland

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #122. `DeviceFix.request` must ask the platform's cache again after the live
 * fix gives up, not only before it starts.
 *
 * This is a source guard rather than a behaviour test, and the reason is worth
 * stating: `DeviceFix` reaches straight into `LocationManager`, which does not
 * exist on the JVM these tests run on, so there is no seam to inject a fake
 * through and no unit test can watch the call happen. A guard that stops the
 * line being deleted is what is actually available, and it is the same idiom
 * [NoCityEndpointTest] uses for the same reason.
 *
 * The defect it pins: the first person to install from Google Play waited out
 * the whole fifteen-second bound, was told no location could be had, tapped
 * "Reyna aftur", and had an answer 2.3 seconds later. Nothing retried on its
 * own — that second attempt was her finger, and it succeeded only because a
 * fresh call reaches `lastKnown` on its way in. The fix the live request had
 * spent fifteen seconds provoking landed just after `removeUpdates` stopped
 * anyone listening for it, so we discarded an answer the system kept.
 */
class DeviceFixCacheOnTheWayOutTest {

    private val source =
        File("src/main/kotlin/is/borgarland/location/DeviceFix.kt")

    @Test
    fun `the cache is asked again after the live fix gives up`() {
        assertTrue("expected ${source.absolutePath} to exist", source.isFile)
        val code = KotlinSource.stripComments(source.readText())

        assertTrue(
            "DeviceFix.request must fall back to lastKnown when liveFix returns null (#122); " +
                "without it a fix that arrives a moment after the timeout is thrown away, and the " +
                "only route to it is a failure message and a button",
            code.contains("liveFix(manager, timeoutMillis) ?: lastKnown(manager)"),
        )
    }

    @Test
    fun `the fallback is a cache read and not a second live request`() {
        val code = KotlinSource.stripComments(source.readText())
        val liveCalls = Regex("liveFix\\(").findAll(code).count()

        // One declaration, one call. A second call would double a bound that is
        // already longer than anyone will stand still at a bin holding a phone,
        // which is the half of #122 that is a wait rather than an accuracy.
        assertTrue(
            "request must not re-run liveFix; found $liveCalls occurrences of `liveFix(`",
            liveCalls == 2,
        )
    }
}
