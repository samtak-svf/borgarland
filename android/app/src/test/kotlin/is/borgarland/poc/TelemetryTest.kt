package `is`.borgarland.poc

import `is`.borgarland.poc.net.Telemetry
import `is`.borgarland.poc.net.TelemetryEvent
import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The client half of the telemetry channel, pinned to data/relay-events.json.
 * The contract is the privacy boundary, so these tests are about what can and
 * cannot reach the wire: the envelope shape, the session format, the batch
 * cap, and above all that a description string handed anywhere near the
 * channel never appears in an encoded body.
 */
class TelemetryTest {

    private fun telemetryWith(send: (String) -> Unit): Telemetry =
        Telemetry().apply { this.send = send }

    @Test
    fun `envelope carries the contract shape`() {
        val bodies = mutableListOf<String>()
        val telemetry = telemetryWith { bodies += it }

        telemetry.track(TelemetryEvent.AppOpened)
        telemetry.track(TelemetryEvent.SendStarted)
        telemetry.flush()

        val json = Json.parseToJsonElement(bodies.single()).jsonObject
        assertTrue("session must be 32 lowercase hex", json.getValue("session").jsonPrimitive.content.matches(Regex("[0-9a-f]{32}")))
        assertEquals("android", json.getValue("platform").jsonPrimitive.content)
        assertEquals(
            "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
            json.getValue("appVersion").jsonPrimitive.content,
        )

        val events = json.getValue("events").jsonArray
        assertEquals(2, events.size)
        assertEquals("app-opened", events[0].jsonObject.getValue("name").jsonPrimitive.content)
        assertEquals("send-started", events[1].jsonObject.getValue("name").jsonPrimitive.content)
        // atMs is the offset from session start, within a day.
        assertTrue(
            events[0].jsonObject.getValue("atMs").jsonPrimitive.content.toInt() in 0..86_400_000,
        )
        // app-opened carries no fields at all — exactly name + atMs.
        assertEquals(2, events[0].jsonObject.size)
    }

    @Test
    fun `field carrying event encodes its fields`() {
        val bodies = mutableListOf<String>()
        val telemetry = telemetryWith { bodies += it }

        telemetry.track(TelemetryEvent.LocationResolved(5, TelemetryEvent.LocationSource.DEVICE, 7))
        telemetry.flush()

        val event = Json.parseToJsonElement(bodies.single()).jsonObject
            .getValue("events").jsonArray[0].jsonObject
        assertEquals("location-resolved", event.getValue("name").jsonPrimitive.content)
        assertEquals(5, event.getValue("elapsedMs").jsonPrimitive.content.toInt())
        assertEquals("device", event.getValue("source").jsonPrimitive.content)
        assertEquals(7, event.getValue("accuracyM").jsonPrimitive.content.toInt())
    }

    @Test
    fun `session is fresh per instance`() {
        // One instance per app LAUNCH, so two instances must never share a
        // session: the id is what makes the stream a timeline rather than a
        // tracker.
        assertNotEquals(Telemetry().sessionId, Telemetry().sessionId)
    }

    @Test
    fun `flushes when the buffer reaches the threshold`() {
        val bodies = mutableListOf<String>()
        val telemetry = telemetryWith { bodies += it }

        repeat(19) { telemetry.track(TelemetryEvent.AppOpened) }
        assertTrue("the buffer must hold until the threshold", bodies.isEmpty())
        telemetry.track(TelemetryEvent.AppOpened)
        assertEquals("the 20th event must trigger a flush", 1, bodies.size)
    }

    @Test
    fun `batch never exceeds one hundred and drops the oldest`() {
        val bodies = mutableListOf<String>()
        val telemetry = telemetryWith { bodies += it }
        telemetry.flushThreshold = Int.MAX_VALUE

        // Distinct byte counts identify the order of the buffered events.
        for (i in 0 until 150) {
            telemetry.track(TelemetryEvent.PhotoCaptured(i, i, "image/jpeg"))
        }
        telemetry.flush()

        val events = Json.parseToJsonElement(bodies.single()).jsonObject.getValue("events").jsonArray
        assertEquals("the relay refuses a batch longer than 100", 100, events.size)
        assertEquals("the oldest 50 must have been dropped", 50, events.first().jsonObject.getValue("bytes").jsonPrimitive.content.toInt())
        assertEquals(149, events.last().jsonObject.getValue("bytes").jsonPrimitive.content.toInt())
    }

    @Test
    fun `consecutive description lengths coalesce`() {
        val bodies = mutableListOf<String>()
        val telemetry = telemetryWith { bodies += it }

        // One event per keystroke would spam the relay; the buffer keeps the
        // latest length only.
        telemetry.track(TelemetryEvent.DescriptionLength(1))
        telemetry.track(TelemetryEvent.DescriptionLength(5))
        telemetry.track(TelemetryEvent.DescriptionLength(9))
        telemetry.flush()

        val events = Json.parseToJsonElement(bodies.single()).jsonObject.getValue("events").jsonArray
        assertEquals(1, events.size)
        assertEquals(9, events.single().jsonObject.getValue("length").jsonPrimitive.content.toInt())
    }

    @Test
    fun `description text never appears in the encoded body`() {
        val secret = "FULL RUSLAFATA VIÐ STÍGINN 83721"
        val bodies = mutableListOf<String>()
        val telemetry = telemetryWith { bodies += it }

        // The closest the app ever brings a description to this channel:
        // only its length is passed, never the text.
        telemetry.track(TelemetryEvent.DescriptionLength(secret.length))
        telemetry.track(TelemetryEvent.CategoryChosen(1, "ruslafotur"))
        telemetry.flush()

        val body = bodies.single()
        assertFalse("the description text must never reach the wire", body.contains(secret))
        // No description field exists anywhere in the contract; a stray one
        // would be rejected by the relay and is a privacy violation here.
        assertFalse(body.contains("\"description\""))
        // The length is the whole signal, and it is present.
        assertTrue(body.contains("\"length\":${secret.length}"))
    }

    @Test
    fun `event names match the contract exactly`() {
        // The unit tests run with the module directory as the working
        // directory, so the repo root is two levels up (FactsFileTest reads
        // src/main/assets the same way).
        val text = File("../../data/relay-events.json").readText()
        val contractEvents = Json.parseToJsonElement(text).jsonObject.getValue("events").jsonObject
        assertEquals(TelemetryEvent.allNames, contractEvents.keys)
    }

    @Test
    fun `event fields match the contract exactly`() {
        val text = File("../../data/relay-events.json").readText()
        val contractEvents = Json.parseToJsonElement(text).jsonObject.getValue("events").jsonObject

        for (name in TelemetryEvent.allNames) {
            val contractFields = contractEvents.getValue(name).jsonObject
                .getValue("fields").jsonObject.keys
            assertEquals(
                "field set for $name drifted from the contract",
                contractFields,
                sampleEvent(name).fields.keys,
            )
        }
    }

    /** One representative event per name, used to pin the field sets. A new
     * field on a case is a compile error here, which is the point: the drift
     * is caught at build time, not by the relay's 400. */
    private fun sampleEvent(name: String): TelemetryEvent = when (name) {
        "app-opened" -> TelemetryEvent.AppOpened
        "camera-permission" -> TelemetryEvent.CameraPermission(true)
        "location-permission" -> TelemetryEvent.LocationPermission(true)
        "photo-captured" -> TelemetryEvent.PhotoCaptured(0, 0, "image/jpeg")
        "location-resolved" -> TelemetryEvent.LocationResolved(0, TelemetryEvent.LocationSource.DEVICE, 0)
        "location-failed" -> TelemetryEvent.LocationFailed(0, TelemetryEvent.LocationFailure.TIMEOUT)
        "category-chosen" -> TelemetryEvent.CategoryChosen(0, "ruslafotur")
        "description-length" -> TelemetryEvent.DescriptionLength(0)
        "send-started" -> TelemetryEvent.SendStarted
        "send-result" -> TelemetryEvent.SendResult(0, 200, true)
        "send-failed" -> TelemetryEvent.SendFailed(0, TelemetryEvent.SendFailure.CONNECTION)
        "screen-left" -> TelemetryEvent.ScreenLeft(TelemetryEvent.Screen.CAMERA, true)
        else -> error("unknown event name $name")
    }
}
