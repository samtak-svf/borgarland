package `is`.borgarland.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Our words for the city's categories, from data/category-labels.json (shipped
 * as an app asset by build.gradle.kts, same pattern as the facts file).
 *
 * The counterpart of [FactsFile], and deliberately a different file for a
 * different reason: the facts file is a faithful record of what the city says,
 * and this is where we disagree with it. Decision 0001 keeps those two jobs
 * apart, so an editorial choice can never be mistaken for a fact about the
 * endpoint.
 *
 * Only one category is overridden today. The default is the city's own name,
 * and that should stay the common case: a picker that renames everything is a
 * picker nobody can match against the city's own form.
 */
@Serializable
data class CategoryLabelsFile(
    val labels: Map<String, CategoryLabel> = emptyMap(),
)

@Serializable
data class CategoryLabel(
    /** What the picker shows instead of the city's name. */
    val label: String,
    /** One line under it, for a category whose scope is not obvious. */
    val help: String? = null,
)

object CategoryLabels {

    private val json = Json { ignoreUnknownKeys = true }

    fun parse(text: String): CategoryLabelsFile = json.decodeFromString(text)

    /**
     * The name to show for a category: ours when we have one, the city's
     * otherwise. Never the slug — a slug on screen is a bug.
     */
    fun display(category: Category, file: CategoryLabelsFile?): String =
        file?.labels?.get(category.slug)?.label ?: category.category

    /**
     * The line under the name, or null when there is nothing useful to add.
     *
     * This replaced the city's general/specific `type`, which both pickers used
     * to render. That subtitle was the city's internal taxonomy: it said
     * "Almenn ábending" beneath a category also called "Almenn ábending" (#40),
     * and it told a walker nothing they could act on.
     */
    fun help(category: Category, file: CategoryLabelsFile?): String? =
        file?.labels?.get(category.slug)?.help
}
