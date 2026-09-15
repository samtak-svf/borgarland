package `is`.borgarland

import `is`.borgarland.capture.WalkCapture
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #164: in a test build the walk photographs itself, and a release build cannot.
 *
 * Two kinds of test here, and the difference matters.
 *
 * The first two are about behaviour: a capture that is switched off does
 * nothing at all, and one that is on numbers its images in the order the steps
 * happened and names each after its event.
 *
 * The third is a source guard, in the shape [NoCityEndpointTest] and
 * [AppOpenedOncePerProcessTest] already use: the rule "a release build cannot
 * capture" is a property of where the flag comes from, and no unit test can
 * observe `BuildConfig.DEBUG` being false, because it never is in a unit test.
 * The same reasoning applies to the missing permission: it is not a property
 * of this code either, it is a property of which API is used, and it is stated
 * in `WalkCapture`'s own comment because grep cannot tell `PixelCopy` from
 * `MediaProjection` in a way that would not break on the comment explaining
 * why one of them is wrong.
 */
class WalkCaptureTest {

    private fun mainSources(): List<File> {
        val src = File("src/main/kotlin")
        assertTrue("expected ${src.absolutePath} to exist", src.isDirectory)
        return src.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
    }

    @Test
    fun `a capture that is not enabled writes nothing and creates nothing`() {
        val dir = File("build/tmp/walk-capture-test/disabled")
        dir.deleteRecursively()
        var grabs = 0

        val capture = WalkCapture(enabled = false, dir = dir, grab = { grabs++ })
        capture.record("photo-captured")
        capture.record("location-resolved")

        assertEquals("a disabled capture must not reach the grab at all", 0, grabs)
        assertFalse("and must not leave a directory behind either", dir.exists())
    }

    @Test
    fun `an enabled capture numbers its images in the order the steps happened`() {
        val dir = File("build/tmp/walk-capture-test/enabled")
        dir.deleteRecursively()
        val written = mutableListOf<String>()

        val capture = WalkCapture(enabled = true, dir = dir, grab = { written += it.name })
        capture.record("photo-captured")
        capture.record("category-chosen")
        capture.record("send-result")

        assertEquals(
            listOf("01-photo-captured.jpg", "02-category-chosen.jpg", "03-send-result.jpg"),
            written,
        )
    }

    @Test
    fun `an event that is not a step is not photographed, and does not advance the numbering`() {
        val dir = File("build/tmp/walk-capture-test/steps")
        dir.deleteRecursively()
        val written = mutableListOf<String>()

        val capture = WalkCapture(enabled = true, dir = dir, grab = { written += it.name })
        capture.record("photo-captured")
        // Six keystrokes, which is one sentence in the first walk this ran on.
        repeat(6) { capture.record("description-length") }
        capture.record("category-chosen")

        assertEquals(
            "a keystroke is not a step, and must not consume a number either",
            listOf("01-photo-captured.jpg", "02-category-chosen.jpg"),
            written,
        )
    }

    @Test
    fun `the one wiring site gates the capture on the build type`() {
        val sources = mainSources()
        val wiring = sources.filter { "onTrack =".toRegex().containsMatchIn(it.readText()) }

        assertEquals(
            "exactly one place may wire a self-capture; found: ${wiring.map { it.name }}",
            1,
            wiring.size,
        )
        val text = wiring.single().readText()
        assertTrue(
            "the wiring site must pass BuildConfig.DEBUG, so a release build cannot capture; " +
                "found: ${text.lines().firstOrNull { it.contains("WalkCapture.fromActivity") }}",
            text.contains("WalkCapture.fromActivity(this, enabled = BuildConfig.DEBUG)"),
        )

        val unconditional = sources.filter {
            Regex("""enabled\s*=\s*true""").containsMatchIn(KotlinSource.stripComments(it.readText()))
        }
        assertTrue(
            "no capture may be enabled unconditionally; found: ${unconditional.map { it.name }}",
            unconditional.isEmpty(),
        )
    }
}
