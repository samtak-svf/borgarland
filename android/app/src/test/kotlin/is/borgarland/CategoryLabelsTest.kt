package `is`.borgarland

import `is`.borgarland.data.CategoryLabels
import `is`.borgarland.data.Facts
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #40, and the requirement underneath it. The Kotlin twin of
 * BorgarlandCoreTests/CategoryLabelsTest.swift; both read the same two files
 * from data/, so the two apps cannot disagree about what a category is called.
 *
 * The reported defect was cosmetic: the picker showed "Almenn ábending" as a
 * category and "Almenn ábending" as its kind. The real defect was that
 * AGENTS.md has required this category to be reworded since the project
 * started, and both apps rendered the city's own string verbatim.
 */
class CategoryLabelsTest {

    // The ASSET, not the repo file. Gradle runs unit tests with android/app as
    // the working directory, and reading it here also proves the build-time copy
    // in build.gradle.kts actually ran — the same thing FactsFileTest relies on.
    private fun dataFile(name: String) = File("src/main/assets/$name").readText()

    private val labels = CategoryLabels.parse(dataFile("category-labels.json"))
    private val facts = Facts.parse(dataFile("reykjavik-form.json"))

    @Test
    fun `the suggestion box is renamed`() {
        val general = facts.categories.first { it.slug == "almenn-abending" }
        val shown = CategoryLabels.display(general, labels)
        assertNotEquals(
            "almenn-abending must not render the city's own name",
            general.category,
            shown,
        )
        assertTrue(
            "the point is not to rename it to another kind of ábending",
            !shown.lowercase().contains("ábending"),
        )
    }

    @Test
    fun `every other category keeps the city's name`() {
        facts.categories.filter { it.slug != "almenn-abending" }.forEach {
            assertEquals(it.category, CategoryLabels.display(it, labels))
        }
    }

    @Test
    fun `an override never collides with its own help line`() {
        labels.labels.forEach { (slug, label) ->
            label.help?.let { assertNotEquals(slug, label.label, it) }
        }
    }

    @Test
    fun `every overridden slug is a real category`() {
        val slugs = facts.categories.map { it.slug }.toSet()
        labels.labels.keys.forEach { assertTrue("$it is not a category", slugs.contains(it)) }
    }

    @Test
    fun `a missing labels file falls back to the city`() {
        val general = facts.categories.first { it.slug == "almenn-abending" }
        assertEquals(general.category, CategoryLabels.display(general, null))
        assertNull(CategoryLabels.help(general, null))
    }
}
