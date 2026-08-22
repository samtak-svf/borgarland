package `is`.borgarland.poc

import `is`.borgarland.poc.data.Facts
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Proves the app's category list really comes from the facts file: the asset
 * is the verbatim data/reykjavik-form.json and must parse into all twelve
 * categories with the documented type split (almenn-abending general, the
 * other eleven specific) and the documented description limit.
 */
class FactsFileTest {

    @Test
    fun assetParsesWithAllTwelveCategories() {
        val text = File("src/main/assets/reykjavik-form.json").readText()
        val facts = Facts.parse(text)

        assertEquals(12, facts.categories.size)
        assertEquals(2500, facts.fields.description.maxLength)

        val general = facts.categories.firstOrNull { it.slug == "almenn-abending" }
        assertEquals("general", general?.type)

        val specific = facts.categories.filter { it.slug != "almenn-abending" }
        assertEquals(11, specific.size)
        assertTrue(specific.all { it.type == "specific" })

        assertTrue(facts.categories.all { it.slug.isNotBlank() && it.category.isNotBlank() && it.summary.isNotBlank() })
    }
}
