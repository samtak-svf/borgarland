package `is`.borgarland.poc.net

import `is`.borgarland.poc.Payload
import java.io.DataOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Posts a report to OUR relay. Never to the city.
 *
 * Decision 0002: the apps post to our relay, never to reykjavik.is directly.
 * That is why there is exactly one URL in this file and no city hostname
 * anywhere in the app. The relay decides whether anything is forwarded, and it
 * does so in dry run by default, on infrastructure we can fix with a deploy
 * rather than an App Store review.
 *
 * The base URL is 127.0.0.1 because `adb reverse tcp:8787 tcp:8787` maps it to
 * the development machine. network_security_config.xml permits cleartext to
 * localhost alone, so a mistyped host does not silently reach the internet.
 */
object RelayClient {

    const val BASE_URL: String = "http://127.0.0.1:8787"

    data class Result(val ok: Boolean, val status: Int, val body: String)

    fun send(payload: Payload): Result {
        val boundary = "----borgarland${System.currentTimeMillis()}"
        val url = URL("$BASE_URL/api/reports")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 10_000
            readTimeout = 30_000
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        }

        return try {
            DataOutputStream(conn.outputStream).use { out ->
                fun field(name: String, value: String) {
                    out.writeBytes("--$boundary\r\n")
                    out.writeBytes("Content-Disposition: form-data; name=\"$name\"\r\n\r\n")
                    out.write(value.toByteArray(Charsets.UTF_8))
                    out.writeBytes("\r\n")
                }
                // Our own vocabulary. The relay's adapter maps it to whatever
                // the city calls these today.
                field("type", payload.type)
                field("category", payload.category)
                field("summary", payload.summary)
                field("lat", payload.latText)
                field("lng", payload.lngText)
                field("description", payload.description)
                for (photo in payload.files) {
                    out.writeBytes("--$boundary\r\n")
                    out.writeBytes(
                        "Content-Disposition: form-data; name=\"files\"; filename=\"${photo.name}\"\r\n")
                    out.writeBytes("Content-Type: ${photo.mime}\r\n\r\n")
                    out.write(photo.bytes)
                    out.writeBytes("\r\n")
                }
                out.writeBytes("--$boundary--\r\n")
            }
            val status = conn.responseCode
            val stream = if (status in 200..299) conn.inputStream else conn.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() } ?: ""
            Result(status in 200..299, status, body)
        } catch (e: Exception) {
            Result(false, 0, e.message ?: e.javaClass.simpleName)
        } finally {
            conn.disconnect()
        }
    }
}
