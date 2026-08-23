package `is`.borgarland.poc

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #70 as a test rather than a comment.
 *
 * `app-opened` marks the start of a telemetry session, and a session is a
 * process: `Telemetry.shared` is created once per process and its session id
 * lives exactly that long. The event therefore has to be emitted from
 * something with the same lifetime.
 *
 * It used to be emitted from `PocViewModel`'s `init`. A ViewModel is cleared
 * when its Activity FINISHES — Back, a swipe out of the recents list, an
 * explicit finish() — while the process stays warm, so the next launch built a
 * second one and emitted again into the same session. It is not cleared by a
 * rotation or by backgrounding: surviving a configuration change is the whole
 * point of a ViewModel, and Home does not destroy the Activity at all. The
 * first Android field test measured two `app-opened` events 16 minutes apart
 * inside one session, which quietly inflates the denominator of every funnel
 * the channel exists to support.
 *
 * A unit test cannot construct an `AndroidViewModel` or an `Application`
 * without a device, and it cannot observe an Activity being recreated at all.
 * So this guards the property that is checkable from the source: there is
 * exactly one emission site, and it is the `Application`. It is the same shape
 * as [NoCityEndpointTest], for the same reason — the rule is about what the
 * code can reach, and the source is where that is decided.
 */
class AppOpenedOncePerProcessTest {

    private fun sourceFiles(): List<File> {
        val src = File("src/main/kotlin")
        assertTrue("expected ${src.absolutePath} to exist", src.isDirectory)
        return src.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
    }

    @Test
    fun `app-opened is emitted from exactly one place`() {
        // No file is excluded, Telemetry.kt least of all. It owns the channel
        // and is the most plausible home for a future startSession() hook,
        // which is exactly where a second emission site would appear. It does
        // not contain the literal today: the declaration reads
        // `object AppOpened : TelemetryEvent("app-opened")`, which never spells
        // TelemetryEvent.AppOpened.
        val emitters = sourceFiles()
            .flatMap { file ->
                KotlinSource.stripComments(file.readText())
                    .lines()
                    .filter { it.contains("TelemetryEvent.AppOpened") }
                    .map { file.name }
            }

        assertEquals(
            "app-opened must have exactly one emission site; found: $emitters",
            listOf("BorgarlandApplication.kt"),
            emitters,
        )
    }

    @Test
    fun `the emission site has the lifetime of a process`() {
        val application = File("src/main/kotlin/is/borgarland/poc/BorgarlandApplication.kt")
        assertTrue("expected ${application.absolutePath} to exist", application.isFile)

        val code = KotlinSource.stripComments(application.readText())
        assertTrue(
            "the emitter must be an Application, whose onCreate runs once per process",
            code.contains("class BorgarlandApplication : Application()"),
        )
        // substringAfter returns the WHOLE string when the delimiter is
        // missing, so this has to assert the delimiter exists first or it
        // passes vacuously on a file that no longer overrides onCreate.
        assertTrue(
            "the emitter must override onCreate; nothing else in an Application " +
                "runs once per process before the first Activity",
            code.contains("override fun onCreate()"),
        )
        assertTrue(
            "the emission must happen in onCreate",
            code.substringAfter("override fun onCreate()").contains("TelemetryEvent.AppOpened"),
        )
    }

    @Test
    fun `the manifest names the Application, or nothing constructs it`() {
        val manifest = File("src/main/AndroidManifest.xml")
        assertTrue("expected ${manifest.absolutePath} to exist", manifest.isFile)

        assertTrue(
            "an Application class Android is not told about is never instantiated, " +
                "and app-opened would then never fire at all",
            manifest.readText().contains("""android:name=".BorgarlandApplication""""),
        )
    }
}
