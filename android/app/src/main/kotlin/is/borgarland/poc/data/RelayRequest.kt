package `is`.borgarland.poc.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Model for data/relay-request.json, the one file that names the multipart
 * parts the app may send to our relay. Copied into assets at build time
 * (android/app/build.gradle.kts), the same pattern as the facts file. The wire
 * names ARE the keys of [RelayRequestFile.fields]; RelayClient writes parts
 * under exactly those names, in the file's order, and nothing else.
 */
@Serializable
data class RelayRequestFile(
    val endpoint: Endpoint,
    val fields: Map<String, FieldSpec>,
)

@Serializable
data class Endpoint(
    val path: String,
    val method: String,
    val contentType: String,
)

@Serializable
data class FieldSpec(
    val required: Boolean,
    val maxLength: Int? = null,
    val accept: List<String>? = null,
)

object RelayRequest {
    private val json = Json { ignoreUnknownKeys = true }

    fun parse(text: String): RelayRequestFile = json.decodeFromString(text)
}
