package `is`.borgarland.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Model for the subset of data/reykjavik-form.json this POC reads. The file is
 * shipped verbatim as an app asset (src/main/assets/reykjavik-form.json) so the
 * category list, the per-category type/summary and the description limit come
 * from the facts file, never from a second copy. The endpoint fields of the
 * file are never read: this app has no capability to send anything.
 */
@Serializable
data class FactsFile(
    val fields: Fields,
    val categories: List<Category>,
    val map: MapInfo,
)

@Serializable
data class Fields(
    val description: Description,
    /** The city's accepted photo MIME list; read only to cross-check the relay contract. */
    val files: Files? = null,
)

@Serializable
data class Description(val maxLength: Int)

@Serializable
data class Files(val accept: List<String>)

@Serializable
data class Category(
    val slug: String,
    /** The city's type (general/specific); used only as a picker label, never sent. */
    val type: String,
    /** The city's display name; used only as the picker label, never sent. */
    val category: String,
)

@Serializable
data class MapInfo(val bounds: Bounds)

@Serializable
data class Bounds(
    val south: Double,
    val west: Double,
    val north: Double,
    val east: Double,
)

object Facts {
    private val json = Json { ignoreUnknownKeys = true }

    fun parse(text: String): FactsFile = json.decodeFromString(text)
}
