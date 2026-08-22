package `is`.borgarland.poc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Decision 0002 as a test rather than a promise.
 *
 * The app gained INTERNET so it can talk to our relay. The guarantee that
 * replaced "it has no network at all" is this: no city hostname, slug or path
 * exists anywhere in the app's source, so there is nothing for a wrong turn to
 * reach. The rule in AGENTS.md says the adapter is the only place allowed to
 * know those names, and in this architecture the adapter lives in the relay.
 */
class NoCityEndpointTest {

    private val forbidden = listOf(
        "reykjavik.is",
        "senda-abendingu",
        "abendingar/addressInfo",
        "location/addresses",
    )

    /**
     * Comments are stripped before scanning, deliberately. A guard that
     * matches a substring rather than a structure fails the very comment that
     * explains it, and then the rule cannot be documented in the file it
     * governs. This test is about what the code can reach, not about which
     * words appear near it.
     */
    private fun stripComments(text: String): String = text
        .replace(Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL), "")
        .lines()
        .joinToString("\n") { it.substringBefore("//") }

    @Test
    fun `no city endpoint appears anywhere in the app source`() {
        val src = File("src/main/kotlin")
        assertTrue("expected ${src.absolutePath} to exist", src.isDirectory)

        val offenders = src.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .flatMap { file ->
                val code = stripComments(file.readText())
                forbidden.filter { code.contains(it) }.map { "${file.name}: $it" }
            }
            .toList()

        assertTrue(
            "the app must not know any city endpoint; found: $offenders",
            offenders.isEmpty(),
        )
    }
}
