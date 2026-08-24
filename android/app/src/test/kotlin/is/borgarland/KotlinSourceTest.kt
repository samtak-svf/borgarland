package `is`.borgarland

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [KotlinSource] is load-bearing: two guards decide whether a rule is being
 * enforced by asking it what the code says. A stripper that removes too much
 * makes a guard pass on a violation, which is the failure mode that matters
 * and the one the old `substringBefore("//")` had.
 *
 * The first test is the case that motivated extracting this at all.
 */
class KotlinSourceTest {

    @Test
    fun `a URL in a string literal survives, because that is where a city endpoint would hide`() {
        val source = "val url = \"https://reykjavik.is/abendingar/senda-abendingu\""

        val stripped = KotlinSource.stripComments(source)

        assertTrue(
            "the old substringBefore(\"//\") cut this line at the URL's slashes " +
                "and NoCityEndpointTest then found nothing to complain about; got: $stripped",
            stripped.contains("reykjavik.is"),
        )
    }

    @Test
    fun `a line comment goes, and the code before it stays`() {
        val stripped = KotlinSource.stripComments("val a = 1 // reykjavik.is\nval b = 2")

        assertTrue(stripped.contains("val a = 1"))
        assertTrue(stripped.contains("val b = 2"))
        assertFalse(stripped.contains("reykjavik.is"))
    }

    @Test
    fun `a block comment goes, nested ones included, and the line count holds`() {
        val source = "val a = 1\n/* one /* two reykjavik.is */ still inside */\nval b = 2"

        val stripped = KotlinSource.stripComments(source)

        assertFalse("nesting must not end the comment early", stripped.contains("still inside"))
        assertFalse(stripped.contains("reykjavik.is"))
        assertTrue(stripped.contains("val b = 2"))
        assertEquals(
            "newlines inside a comment are kept so line numbers do not move",
            source.count { it == '\n' },
            stripped.count { it == '\n' },
        )
    }

    @Test
    fun `an escaped quote does not end the string one character early`() {
        val source = """val a = "he said \"// not a comment\" and reykjavik.is""""

        val stripped = KotlinSource.stripComments(source)

        assertTrue(stripped.contains("// not a comment"))
        assertTrue(stripped.contains("reykjavik.is"))
    }

    @Test
    fun `a raw string keeps everything inside it`() {
        val source = "val a = \"\"\"a // b /* c */ reykjavik.is\"\"\"\nval d = 1 // gone"

        val stripped = KotlinSource.stripComments(source)

        assertTrue(stripped.contains("// b"))
        assertTrue(stripped.contains("/* c */"))
        assertTrue(stripped.contains("reykjavik.is"))
        assertFalse(stripped.contains("gone"))
    }

    @Test
    fun `a comment marker inside a string does not start a comment that eats the file`() {
        val source = "val a = \"/*\"\nval b = 2\nval c = \"reykjavik.is\""

        val stripped = KotlinSource.stripComments(source)

        assertTrue("the rest of the file must not vanish", stripped.contains("val b = 2"))
        assertTrue(stripped.contains("reykjavik.is"))
    }
}
