package `is`.borgarland.net

import `is`.borgarland.BuildConfig
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * The client half of the telemetry channel, the counterpart of
 * ios/BorgarlandCore/.../Telemetry.swift. data/relay-events.json is the
 * contract and the allowlist that is the privacy boundary: every event name
 * and every field below is spelled there, the Worker rejects anything it does
 * not name, and there is deliberately no free-text field anywhere in that
 * file.
 *
 * The privacy rules this type exists to enforce:
 *
 *   1. No content ever. Only the contract's fields: numbers, booleans and
 *      fixed enum values. `description-length` carries the LENGTH of what was
 *      typed, never the text; `accuracyM` is a radius in whole metres, never
 *      a position.
 *   2. The session id is generated fresh per instance (per app LAUNCH in the
 *      app) from a secure random source, is never persisted and is never
 *      derived from a device/vendor/advertising identifier. It groups one
 *      sitting and cannot follow a person between sessions.
 *   3. Telemetry never affects the report. Every failure is swallowed, the
 *      send is fire-and-forget off the UI thread, and nothing here can
 *      block, delay or retry into a report send.
 *   4. Batched, not spammed: the buffer flushes at ~20 events, at the
 *      natural end points (the report send result, app background), and
 *      never exceeds 100 per batch (the relay refuses a longer one).
 *   5. A batch the relay did not take goes back in the buffer (#74). The
 *      flush points include app background, which is the moment someone
 *      reaches the airplane-mode toggle, so the flush most likely to fail is
 *      the one carrying the outage we are trying to measure. Dropping under
 *      the cap is still correct; dropping on a failed request is not.
 *
 * Testable by injection: [send] is a closure a test replaces to capture the
 * body without a network.
 */
class Telemetry {

    companion object {
        // Declared before `shared`: the instance constructor reads it while
        // the companion object is still being initialized.
        private val secureRandom = SecureRandom()

        /** The app-wide instance. One instance = one session id, and the app
         * creates exactly one of these per launch. */
        val shared = Telemetry()

        private fun newSessionId(): String {
            val bytes = ByteArray(16)
            secureRandom.nextBytes(bytes)
            return bytes.joinToString("") { b -> "%02x".format(b.toInt() and 0xff) }
        }

        /** The contract's mime enum, with an `other` fallback for anything
         * the contract does not name. */
        fun normalizedMime(raw: String): String =
            if (raw in ALLOWED_MIMES) raw else "other"

        private val ALLOWED_MIMES = setOf("image/jpeg", "image/png", "image/gif", "image/heic")

        private const val PLATFORM = "android"
        private const val ENDPOINT_PATH = "/api/events"

        /** A day in milliseconds; beyond that is a broken clock, not a session. */
        private const val MAX_AT_MS = 86_400_000

        /**
         * A status the relay answered with, read as keep-or-drop. 4xx is the
         * relay saying this body is wrong, and it will say it again to the same
         * bytes; 408 and 429 are the two that mean try later instead.
         */
        fun outcomeForStatus(status: Int): BatchOutcome = when (status) {
            in 200..299 -> BatchOutcome.DELIVERED
            408, 429 -> BatchOutcome.UNDELIVERED
            in 400..499 -> BatchOutcome.REJECTED
            else -> BatchOutcome.UNDELIVERED
        }
    }

    /** Fresh per launch, 32 lowercase hex characters, never persisted. */
    val sessionId: String = newSessionId()

    /** The moment the session started; `atMs` is the offset from here. */
    private val sessionStartMs: Long = System.currentTimeMillis()

    // The relay host comes from BuildConfig, exactly like RelayClient (#29):
    // the loopback for debug builds (adb reverse), the deployed https host
    // for release. No literal here.
    private val baseUrl: String = BuildConfig.RELAY_BASE_URL

    /** The envelope's app version in "0.1.0 (3)" form, from BuildConfig. */
    private val appVersion: String = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

    /**
     * What became of a batch handed to the transport. The distinction that
     * matters is between a relay that refused this body and always will, and
     * one that simply did not answer: the first must be dropped or it poisons
     * the buffer forever, the second must be kept or the outage erases its own
     * evidence. The Swift side's `noExif` bug is the first case — an unknown
     * enum value made the relay 400 every batch that contained one.
     */
    enum class BatchOutcome {
        /** The relay took it. */
        DELIVERED,

        /** The relay refused it and would refuse it again. Dropping is correct. */
        REJECTED,

        /** Nobody answered, or the relay may take it later. Keep the events. */
        UNDELIVERED,
    }

    /**
     * Injectable so a unit test can capture the body without a network.
     *
     * The closure must invoke its completion exactly once. Invoking it late is
     * fine and is the normal case.
     *
     * Never invoking it wedges the channel for the rest of the session:
     * [finish] is the only place `inFlight` is cleared, so every later flush
     * returns at once and the buffer never drains at all. [track] keeps shedding
     * its oldest event at the cap, so events are lost silently, which is the
     * hole #74 was about wearing a different hat. Failures here are swallowed by
     * design, so nothing would ever say so.
     */
    var send: ((String, (BatchOutcome) -> Unit) -> Unit)? = null

    /** Flush when the buffer reaches this many events. */
    var flushThreshold: Int = 20

    /** The relay refuses a batch longer than this (data/relay-events.json). */
    var maxBatch: Int = 100

    private val lock = Any()
    private val buffer = ArrayDeque<BufferedEvent>()

    /**
     * One batch in flight at a time. Without this, every event past the
     * threshold starts another post while offline, and a batch that failed
     * could be requeued underneath a later one that carried the same events.
     */
    private var inFlight = false

    /** The fire-and-forget transport; its dispatcher never touches the UI
     * thread. */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private data class BufferedEvent(val event: TelemetryEvent, val atMs: Int)

    /** Records an event. Never throws and never blocks on the network: the
     * buffer is capped, and the flush returns before its request does. */
    fun track(event: TelemetryEvent) {
        val atMs = clampAtMs(System.currentTimeMillis() - sessionStartMs)
        var shouldFlush = false
        synchronized(lock) {
            // description-length is emitted on every keystroke; coalesce
            // consecutive ones so a long description keeps one event, not one
            // per character. Every other event fires at a discrete moment.
            if (event is TelemetryEvent.DescriptionLength &&
                buffer.lastOrNull()?.event is TelemetryEvent.DescriptionLength
            ) {
                buffer.removeLast()
            } else if (buffer.size >= maxBatch) {
                // The relay refuses an over-long batch rather than truncating
                // it, so the oldest events go instead. This is instrumentation,
                // not the report: dropping is correct, blocking is not.
                buffer.removeFirst()
            }
            buffer.addLast(BufferedEvent(event, atMs))
            shouldFlush = buffer.size >= flushThreshold
        }
        if (shouldFlush) flush()
    }

    /**
     * Sends whatever is buffered, if anything. Safe to call from anywhere and
     * any thread; the network send itself never blocks the caller.
     *
     * A batch that fails to reach the relay is put back (see [finish]), so this
     * is at-least-once rather than at-most-once: a batch the relay stored and
     * then failed to acknowledge is sent again and lands twice. That trade is
     * deliberate. A duplicated event is visible in the timeline and can be read
     * around; a missing one is indistinguishable from someone standing still,
     * which is exactly how #74 hid for a whole field test.
     */
    fun flush() {
        val batch: List<BufferedEvent> = synchronized(lock) {
            if (inFlight) return
            while (buffer.size > maxBatch) buffer.removeFirst()
            val taken = buffer.toList()
            buffer.clear()
            inFlight = taken.isNotEmpty()
            taken
        }
        if (batch.isEmpty()) return
        val transport = send ?: ::httpSend
        transport(encode(batch)) { outcome -> finish(batch, outcome) }
    }

    /**
     * Closes out a flush: the channel is free again, and an undelivered batch
     * goes back where it came from.
     */
    private fun finish(batch: List<BufferedEvent>, outcome: BatchOutcome) {
        synchronized(lock) {
            inFlight = false
            if (outcome == BatchOutcome.UNDELIVERED) {
                // In front: these events are older than anything buffered while
                // the request was out. The cap then applies as it always does,
                // and it may well drop these — under pressure the oldest still
                // go.
                for (event in batch.asReversed()) buffer.addFirst(event)
                while (buffer.size > maxBatch) buffer.removeFirst()
            }
        }
    }

    /**
     * The envelope from data/relay-events.json: session, platform, the app's
     * version string, and the events — each `{ name, atMs, ...fields }` with
     * the fields flattened to the top level, exactly as the Worker validates
     * them.
     */
    private fun encode(batch: List<BufferedEvent>): String {
        val payload = buildJsonObject {
            put("session", sessionId)
            put("platform", PLATFORM)
            put("appVersion", appVersion)
            put("events", buildJsonArray {
                for (b in batch) {
                    add(buildJsonObject {
                        put("name", b.event.name)
                        put("atMs", b.atMs)
                        b.event.fields.forEach { (key, value) -> put(key, value) }
                    })
                }
            })
        }
        return payload.toString()
    }

    /**
     * Posts the body and reports what became of it. Still fire-and-forget as
     * far as the caller is concerned: nobody is shown an error and nothing
     * waits (data/relay-events.json, endpoint.notes). The answer is read only
     * to decide whether the events are worth keeping.
     */
    private fun httpSend(body: String, completion: (BatchOutcome) -> Unit) {
        scope.launch {
            var outcome = BatchOutcome.UNDELIVERED
            try {
                val url = URL("$baseUrl$ENDPOINT_PATH")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 10_000
                    readTimeout = 10_000
                    setRequestProperty("Content-Type", "application/json")
                    // #128: never send the platform default, which names the handset.
                    setRequestProperty("User-Agent", RelayClient.USER_AGENT)
                }
                try {
                    conn.outputStream.use { out -> out.write(body.toByteArray(Charsets.UTF_8)) }
                    outcome = outcomeForStatus(conn.responseCode)
                } finally {
                    conn.disconnect()
                }
            } catch (_: Exception) {
                // Swallowed on purpose: telemetry must never be noticed. The
                // events stay buffered rather than being shown to anyone.
            }
            completion(outcome)
        }
    }

    /**
     * A day in milliseconds; an offset beyond that is a broken clock, not a
     * session (the Worker's own bound).
     *
     * Takes a Long and clamps before narrowing. Truncating first would wrap a
     * session past about 24.8 days to a negative Int and clamp it to 0, which
     * defeats the bound instead of enforcing it. Unreachable for a camera app,
     * and free to get right.
     */
    private fun clampAtMs(ms: Long): Int = ms.coerceIn(0L, MAX_AT_MS.toLong()).toInt()
}

/**
 * One event this client can emit. The cases, the names and the fields are
 * exactly data/relay-events.json: TelemetryTest pins the full set against the
 * file so the client and the contract cannot drift. The constrained value
 * enums below are the contract's fixed enums, spelled once.
 */
sealed class TelemetryEvent(val name: String) {
    abstract val fields: JsonObject

    object AppOpened : TelemetryEvent("app-opened") {
        override val fields: JsonObject = JsonObject(emptyMap())
    }

    data class CameraPermission(val granted: Boolean) : TelemetryEvent("camera-permission") {
        override val fields: JsonObject = buildJsonObject { put("granted", granted) }
    }

    /**
     * The dialog was put up. Pairs with [LocationPermission], which is the
     * answer: the gap between them is how long somebody took to read it.
     *
     * Android has never needed this to avoid the #134 defect -- its launcher
     * callback fires only when the dialog is actually answered, so an
     * unanswered dialog has always produced no event rather than a false one.
     * It is emitted here anyway so both platforms write the same stream, and
     * so the reading time is measurable on the platform that has the testers.
     */
    object LocationPermissionAsked : TelemetryEvent("location-permission-asked") {
        override val fields: JsonObject = JsonObject(emptyMap())
    }

    data class LocationPermission(val granted: Boolean) : TelemetryEvent("location-permission") {
        override val fields: JsonObject = buildJsonObject { put("granted", granted) }
    }

    data class PhotoCaptured(
        val elapsedMs: Int,
        val bytes: Int,
        val mime: String,
    ) : TelemetryEvent("photo-captured") {
        override val fields: JsonObject = buildJsonObject {
            put("elapsedMs", elapsedMs)
            put("bytes", bytes)
            put("mime", mime)
        }
    }

    data class LocationResolved(
        val elapsedMs: Int,
        val source: LocationSource,
        val accuracyM: Int,
    ) : TelemetryEvent("location-resolved") {
        override val fields: JsonObject = buildJsonObject {
            put("elapsedMs", elapsedMs)
            put("source", source.value)
            put("accuracyM", accuracyM)
        }
    }

    data class LocationFailed(
        val elapsedMs: Int,
        val reason: LocationFailure,
    ) : TelemetryEvent("location-failed") {
        override val fields: JsonObject = buildJsonObject {
            put("elapsedMs", elapsedMs)
            put("reason", reason.value)
        }
    }

    data class CategoryChosen(val elapsedMs: Int, val slug: String) : TelemetryEvent("category-chosen") {
        override val fields: JsonObject = buildJsonObject {
            put("elapsedMs", elapsedMs)
            put("slug", slug)
        }
    }

    data class DescriptionLength(val length: Int) : TelemetryEvent("description-length") {
        override val fields: JsonObject = buildJsonObject { put("length", length) }
    }

    object SendStarted : TelemetryEvent("send-started") {
        override val fields: JsonObject = JsonObject(emptyMap())
    }

    data class SendResult(
        val elapsedMs: Int,
        val status: Int,
        val ok: Boolean,
    ) : TelemetryEvent("send-result") {
        override val fields: JsonObject = buildJsonObject {
            put("elapsedMs", elapsedMs)
            put("status", status)
            put("ok", ok)
        }
    }

    data class SendFailed(val elapsedMs: Int, val reason: SendFailure) : TelemetryEvent("send-failed") {
        override val fields: JsonObject = buildJsonObject {
            put("elapsedMs", elapsedMs)
            put("reason", reason.value)
        }
    }

    data class ScreenLeft(val screen: Screen, val completed: Boolean) : TelemetryEvent("screen-left") {
        override val fields: JsonObject = buildJsonObject {
            put("screen", screen.value)
            put("completed", completed)
        }
    }

    enum class LocationSource(val value: String) {
        DEVICE("device"),
        EXIF("exif"),
    }

    enum class LocationFailure(val value: String) {
        PERMISSION("permission"),
        TIMEOUT("timeout"),
        UNAVAILABLE("unavailable"),
        NO_EXIF("no-exif"),
    }

    enum class SendFailure(val value: String) {
        CONNECTION("connection"),
        TIMEOUT("timeout"),
        ENCODING("encoding"),
        OTHER("other"),
    }

    enum class Screen(val value: String) {
        CAMERA("camera"),
        DETAILS("details"),

        // `confirm`, not `summary`: the city has a payload field by that
        // name and the no-city-endpoint guards forbid spelling one here. The
        // screen is still SummaryScreen; only the wire word moved.
        SUMMARY("confirm"),
    }

    companion object {
        /** The full set of event names this client can emit, in the contract
         * file's order. TelemetryTest asserts this equals the `events` keys
         * of data/relay-events.json, so a drift in either direction is a red
         * build. */
        val allNames: Set<String> = setOf(
            "app-opened", "camera-permission", "location-permission-asked",
            "location-permission", "photo-captured",
            "location-resolved", "location-failed", "category-chosen", "description-length",
            "send-started", "send-result", "send-failed", "screen-left",
        )
    }
}
