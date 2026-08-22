package `is`.borgarland.poc.net

import `is`.borgarland.poc.BuildConfig
import `is`.borgarland.poc.Photo
import `is`.borgarland.poc.Payload
import `is`.borgarland.poc.data.RelayRequestFile
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException

/**
 * Posts a report to OUR relay. Never to the city.
 *
 * Decision 0002: the apps post to our relay, never to reykjavik.is directly.
 * That is why there is exactly one URL in this file and no city hostname
 * anywhere in the app. The relay decides whether anything is forwarded, and it
 * does so in dry run by default, on infrastructure we can fix with a deploy
 * rather than an App Store review.
 *
 * The request shape comes from data/relay-request.json (copied into assets at
 * build time): the multipart parts are written under exactly the field names
 * that file carries, in its order. Nothing else is sent — in particular no
 * city vocabulary (type, summary, display name, lat/lng, files), which belongs
 * to the relay's adapter alone.
 *
 * The base URL comes from BuildConfig, per build type (#29): the loopback for
 * debug, where `adb reverse tcp:8787 tcp:8787` maps it to the development
 * machine, and the deployed https host for release. build.gradle.kts refuses to
 * configure a release with a loopback value at all.
 *
 * network_security_config.xml permits cleartext to localhost alone, so a
 * mistyped host does not silently reach the internet, and the deployed relay is
 * https so the policy does not need widening.
 */
object RelayClient {

    val BASE_URL: String = BuildConfig.RELAY_BASE_URL

    /**
     * Why a non-HTTP failure happened, when it did. Feeds the telemetry
     * channel's send-failed reason (data/relay-events.json); null means the
     * relay answered, whatever the status.
     */
    enum class Failure { CONNECTION, TIMEOUT, ENCODING, OTHER }

    data class Result(
        val ok: Boolean,
        val status: Int,
        val body: String,
        val failure: Failure? = null,
    )

    fun send(payload: Payload, contract: RelayRequestFile): Result {
        val boundary = "----borgarland${System.currentTimeMillis()}"
        val url = URL("$BASE_URL${contract.endpoint.path}")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = contract.endpoint.method
            doOutput = true
            connectTimeout = 10_000
            readTimeout = 30_000
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        }

        return try {
            DataOutputStream(conn.outputStream).use { out ->
                out.write(buildBody(payload, contract, boundary))
            }
            val status = conn.responseCode
            val stream = if (status in 200..299) conn.inputStream else conn.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() } ?: ""
            Result(status in 200..299, status, body)
        } catch (e: Exception) {
            // The Kotlin maps any exception to status 0; the model renders
            // that as "could not reach the relay". The failure class is for
            // the telemetry channel only and never changes the report path.
            val failure = when (e) {
                is SocketTimeoutException -> Failure.TIMEOUT
                is ConnectException, is UnknownHostException -> Failure.CONNECTION
                is IOException -> Failure.CONNECTION
                else -> Failure.OTHER
            }
            Result(false, 0, e.message ?: e.javaClass.simpleName, failure)
        } finally {
            conn.disconnect()
        }
    }

    /**
     * The exact multipart body the app posts, built from the contract. Parts
     * are written under the contract's field names in the contract's order.
     * The literal in the role binding is which role a contract field plays;
     * the wire name written is the contract's own key. A required field the
     * app has no value for fails loudly instead of sending a request the
     * relay would reject, and a part the contract does not name is never
     * written (RelayRequestTest pins the parts to the contract).
     */
    internal fun buildBody(payload: Payload, contract: RelayRequestFile, boundary: String): ByteArray {
        val out = ByteArrayOutputStream()

        fun writeTextPart(name: String, value: String) {
            out.write("--$boundary\r\n".toByteArray(Charsets.UTF_8))
            out.write("Content-Disposition: form-data; name=\"$name\"\r\n\r\n".toByteArray(Charsets.UTF_8))
            out.write(value.toByteArray(Charsets.UTF_8))
            out.write("\r\n".toByteArray(Charsets.UTF_8))
        }

        fun writePhotoPart(name: String, photo: Photo) {
            out.write("--$boundary\r\n".toByteArray(Charsets.UTF_8))
            out.write(
                "Content-Disposition: form-data; name=\"$name\"; filename=\"${photo.name}\"\r\n"
                    .toByteArray(Charsets.UTF_8),
            )
            out.write("Content-Type: ${photo.mime}\r\n\r\n".toByteArray(Charsets.UTF_8))
            out.write(photo.bytes)
            out.write("\r\n".toByteArray(Charsets.UTF_8))
        }

        val fields = contract.fields

        fun valueFor(name: String): String? = when (name) {
            "category" -> payload.categorySlug
            "latitude" -> payload.latitudeText
            "longitude" -> payload.longitudeText
            "description" -> payload.description
            // Optional roles the POC never fills; written only when the
            // contract names them and a value exists.
            "email" -> null
            "photo" -> null
            else -> null
        }

        for ((name, spec) in fields) {
            if (name == "photo") {
                for (photo in payload.photos) writePhotoPart(name, photo)
                continue
            }
            val value = valueFor(name)
            if (spec.required && value == null) {
                throw IllegalStateException(
                    "relay contract field '$name' is required but the app has nothing to send",
                )
            }
            if (value != null) writeTextPart(name, value)
        }
        out.write("--$boundary--\r\n".toByteArray(Charsets.UTF_8))
        return out.toByteArray()
    }
}
