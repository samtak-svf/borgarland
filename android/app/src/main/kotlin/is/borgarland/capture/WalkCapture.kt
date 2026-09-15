package `is`.borgarland.capture

import android.app.Activity
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import java.io.File
import java.io.FileOutputStream
import `is`.borgarland.net.Telemetry

/**
 * A test-mode walk photographs itself (#164).
 *
 * "When new test data arrives" in AGENTS.md asks for screenshots and then has
 * to say where they came from: a chat thread, because the only person who can
 * take one is holding the phone. That is the wrong place for evidence, twice
 * over — it depends on somebody remembering in the moment, and it arrives
 * somewhere that is not durable. The 2026-08-24 sweep found five images where
 * there had been eight, and caught it only because a person asked.
 *
 * So in a test build the app captures its own window at each moment the
 * telemetry already names, and writes the image beside the report on the
 * device. The telemetry records what the app DID and can never record what the
 * person SAW; an image per step is the only artefact that can falsify a
 * timeline, which is why AGENTS.md's step 3 cross-checks the two.
 *
 * Three properties this type exists to hold:
 *
 *   1. **A release build cannot capture.** `enabled` is passed in, and the one
 *      wiring site passes `BuildConfig.DEBUG`
 *      ([WalkCaptureTest] asserts that over the source rather than trusting
 *      this comment). A screenshot is a privacy surface, and a release that can
 *      be talked into capturing itself is a defect.
 *   2. **Own window, not the screen.** [copyWindow] goes through `PixelCopy`,
 *      which needs no permission and cannot see another app. MediaProjection
 *      would ask the person a question they should not have to answer, and the
 *      answer is stored by the system for every app afterwards.
 *   3. **The images join to the walk.** The directory is the session id the
 *      telemetry envelope carries, and each file is numbered and named after
 *      the event that caused it, so the image set and the event timeline are
 *      the same walk by construction.
 *
 * What a capture contains is not nothing: the details screen shows the
 * reporter's own email address, which decision 0015 keeps on the phone
 * deliberately. So captures belong in the gitignored `private/screenshots`,
 * indexed in `private/testers.json`, and never in this repository.
 */
class WalkCapture(
    private val enabled: Boolean,
    private val dir: File,
    private val grab: (File) -> Unit,
) {
    private val lock = Any()
    private var index = 0

    /**
     * One image for one step, numbered in the order the steps happened.
     *
     * Does nothing at all when [enabled] is false: no directory is created, the
     * grab is not called, and a counter does not advance. That is what the
     * release-build test checks, so it has to be the first thing this method
     * does.
     *
     * Nothing is captured for an event that is not in [STEPS], and the counter
     * does not move for one either — the numbering counts images, not events.
     *
     * The event name is a fixed enum from `data/relay-events.json`, so a
     * filename can never carry anything a person typed.
     */
    fun record(event: String) {
        if (!enabled) return
        if (event !in STEPS) return
        val n = synchronized(lock) { ++index }
        grab(File(dir, "%02d-%s.jpg".format(n, event)))
    }

    companion object {
        /**
         * The events worth an image: the steps a walk is reconstructed from,
         * and the list #164 names — the photo captured, the location resolved,
         * the category chosen, a screen left, the relay answered.
         *
         * `description-length` is deliberately NOT in here, and that is a
         * correction the first walk made (#164, 2026-09-15). This class first
         * captured every event the telemetry channel records, which produced
         * **six near-identical screenshots of one sentence being typed** —
         * because the event fires on every keystroke. The telemetry buffer
         * coalesces consecutive ones; this list is the same idea one layer up,
         * and it is the difference between five images for a walk and fifty.
         *
         * `camera-permission` and `app-opened` are out for the same reason:
         * they belong to a screen, not to a step, and the first walk captured
         * one of them before the window had a size, which is a file that never
         * appears.
         */
        private val STEPS = setOf(
            "photo-captured",
            "location-resolved",
            "category-chosen",
            "screen-left",
            "send-result",
        )

        /**
         * The real thing, wired once in `MainActivity`: this app's own window,
         * and a directory under the app's private storage named after the
         * session.
         *
         * The caller decides [enabled]. It is a parameter rather than
         * `BuildConfig.DEBUG` read in here so that the test can construct both
         * sides of it, and so that the single decision about whether a build
         * may capture is written where a reader looks for it.
         */
        fun fromActivity(activity: Activity, enabled: Boolean): WalkCapture = WalkCapture(
            enabled = enabled,
            dir = File(activity.filesDir, "walk-captures/${Telemetry.shared.sessionId}"),
            grab = { file -> copyWindow(activity, file) },
        )

        /**
         * Copies the window into a JPEG, off the UI thread once the pixels are
         * in hand.
         *
         * `PixelCopy` is asynchronous and delivers on the main looper, so the
         * encode and the write happen on a thread of their own: a capture must
         * not be able to make the app jank, and the walk it is recording is
         * somebody using the app.
         *
         * Nothing here throws and nothing is reported. A capture that fails
         * leaves a missing image, which is visible in the numbering, and the
         * walk itself goes on — the same posture as the telemetry channel it
         * hangs off.
         */
        private fun copyWindow(activity: Activity, file: File) {
            val view = activity.window.decorView
            val width = view.width
            val height = view.height
            // Before the first layout there is nothing to copy, and asking for
            // a zero-sized bitmap throws. The next event will have one.
            if (width <= 0 || height <= 0) return

            val bitmap = try {
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            } catch (_: Exception) {
                return
            }

            PixelCopy.request(
                activity.window,
                bitmap,
                { result ->
                    if (result != PixelCopy.SUCCESS) {
                        bitmap.recycle()
                        return@request
                    }
                    Thread {
                        runCatching {
                            file.parentFile?.mkdirs()
                            FileOutputStream(file).use { out ->
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                            }
                        }
                        bitmap.recycle()
                    }.start()
                },
                Handler(Looper.getMainLooper()),
            )
        }
    }
}
