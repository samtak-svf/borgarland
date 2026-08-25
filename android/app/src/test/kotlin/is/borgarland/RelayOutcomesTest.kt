package `is`.borgarland

import `is`.borgarland.data.RelayOutcomes
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #77: a tester read `{"error":"outside-reykjavik",...}` on his phone and asked
 * what it meant; the other read the whole stored row and asked whether the app
 * was connected to anything. These tests are about the mapping from a relay
 * answer to a sentence, and about the file being the only place those sentences
 * live. The Swift counterpart is RelayOutcomesTest.swift.
 */
class RelayOutcomesTest {

    // The unit tests run with the module directory as the working directory,
    // and the asset is the build-time copy of data/relay-outcomes.json.
    private val file = RelayOutcomes.parse(File("src/main/assets/relay-outcomes.json").readText())

    @Test
    fun `every entry in the file says something`() {
        for ((code, outcome) in file.outcomes) {
            assertTrue("$code says nothing", outcome.says.isNotBlank())
        }
        assertTrue(file.sent.says.isNotBlank())
        assertTrue(file.dryRun.says.isNotBlank())
        assertTrue(file.noAnswer.says.isNotBlank())
        assertTrue(file.unknown.says.isNotBlank())
    }

    /**
     * The two the issue names. `live-send-already-used` is the one to forget:
     * dry run never produces it, so it cannot be met until the day the relay is
     * armed, which is the day it matters.
     */
    @Test
    fun `the codes the field test and the armed relay produce`() {
        assertNotNull(file.outcomes["outside-reykjavik"])
        assertNotNull(file.outcomes["live-send-already-used"])
    }

    @Test
    fun `reads the error code out of a refusal`() {
        val body = """{"error":"outside-reykjavik","svfnr":4200}"""
        assertEquals("outside-reykjavik", RelayOutcomes.read(body).errorCode)
        assertNull(RelayOutcomes.read(body).dryRun)
    }

    @Test
    fun `reads the dry run flag out of a stored row`() {
        val body = """{"report":{"id":"abc","dryRun":true,"sentAt":null},"cityPayload":{}}"""
        assertEquals(true, RelayOutcomes.read(body).dryRun)
        assertNull(RelayOutcomes.read(body).errorCode)
    }

    /**
     * The failure path is the last place to fail again: anything unparseable
     * answers null rather than throwing.
     */
    @Test
    fun `a body that is not json answers nothing rather than throwing`() {
        val answer = RelayOutcomes.read("<html>502 Bad Gateway</html>")
        assertNull(answer.errorCode)
        assertNull(answer.dryRun)
    }

    @Test
    fun `an empty body answers nothing`() {
        assertEquals(RelayOutcomes.Answer(null, null), RelayOutcomes.read(""))
    }

    /**
     * The sentence is the RENDERED outcome, not the file's entry verbatim.
     * They differ exactly where the entry carries a `{name}` placeholder: this
     * body names no place, so the detail line is dropped and everything else is
     * the file's own words (#148).
     */
    @Test
    fun `a refusal gets its own sentence`() {
        assertEquals(
            file.outcomes["outside-reykjavik"]?.copy(detail = null),
            RelayOutcomes.sentence(400, """{"error":"outside-reykjavik","svfnr":4200}""", file),
        )
    }

    @Test
    fun `a dry run success does not claim the report reached the city`() {
        val outcome = RelayOutcomes.sentence(201, """{"report":{"dryRun":true},"cityPayload":{}}""", file)
        assertEquals(file.dryRun, outcome)
        assertTrue("the relay forwarded nothing, and the sentence must not say otherwise", outcome != file.sent)
    }

    @Test
    fun `a real success says it arrived`() {
        assertEquals(file.sent, RelayOutcomes.sentence(201, """{"report":{"dryRun":false}}""", file))
    }

    @Test
    fun `no answer at all has its own sentence`() {
        assertEquals(file.noAnswer, RelayOutcomes.sentence(0, "timed out", file))
    }

    /**
     * Should be unreachable: worker/tests/outcomes.test.ts fails the build when
     * the relay can answer with a code this file does not name. "Should be
     * unreachable" is not a reason to show somebody raw JSON.
     */
    @Test
    fun `a code the file does not name still gets a sentence`() {
        assertEquals(file.unknown, RelayOutcomes.sentence(400, """{"error":"something-new"}""", file))
    }

    @Test
    fun `a refusal with no code at all still gets a sentence`() {
        assertEquals(file.unknown, RelayOutcomes.sentence(500, "", file))
    }

    /**
     * Null rather than a sentence written in Kotlin. A second place for our
     * words is a second place for them to drift, and a screen with no sentence
     * still has the relay's own answer on it.
     */
    @Test
    fun `a missing file produces no sentence rather than an invented one`() {
        assertNull(RelayOutcomes.sentence(400, """{"error":"internal"}""", null))
    }

    /**
     * #148: a refusal a person retries is a refusal that does not read as
     * final. A tester pressed send three times against the same jurisdiction
     * 400 because the button was the only live control on the screen.
     */
    @Test
    fun `a jurisdiction refusal is not retryable and the screens can see it`() {
        val file = RelayOutcomes.parse(File("../../data/relay-outcomes.json").readText())
        assertEquals(false, file.outcomes["outside-reykjavik"]?.retryable)
        assertEquals(false, file.outcomes["jurisdiction-unknown"]?.retryable)
        assertEquals(false, file.outcomes["live-send-already-used"]?.retryable)
        assertEquals(false, file.outcomes["invalid-report-id"]?.retryable)
    }

    /**
     * Absent means retryable. Wrongly retryable costs a wasted request;
     * wrongly terminal takes the only control on the screen away from somebody
     * who could have succeeded.
     */
    @Test
    fun `an outcome that says nothing about retrying is retryable`() {
        val file = RelayOutcomes.parse(File("../../data/relay-outcomes.json").readText())
        assertEquals(true, file.outcomes["city-unreachable"]?.retryable)
        assertEquals(true, file.sent.retryable)
    }

    /** The placeholder is filled from the relay's own answer, never invented. */
    @Test
    fun `the detail sentence names the place the relay reported`() {
        val file = RelayOutcomes.parse(File("../../data/relay-outcomes.json").readText())
        val body = """{"error":"outside-reykjavik","svfnr":8716,"placeDative":"Hveragerði"}"""
        assertEquals(
            "Næsta skráða heimilisfang er í Hveragerði.",
            RelayOutcomes.sentence(400, body, file)?.detail,
        )
    }

    /**
     * Half a sentence in front of somebody is worse than the silence the
     * screen had before it, so a placeholder with nothing behind it drops the
     * whole line.
     */
    @Test
    fun `a detail with no field behind it is dropped rather than shown with a hole`() {
        val file = RelayOutcomes.parse(File("../../data/relay-outcomes.json").readText())
        assertNull(RelayOutcomes.sentence(400, """{"error":"outside-reykjavik"}""", file)?.detail)
        // A number is not a string: it must not become the word it prints as.
        assertNull(
            RelayOutcomes.sentence(400, """{"error":"outside-reykjavik","placeDative":8716}""", file)?.detail,
        )
    }

    /**
     * The asset is a build-time copy of the one home in data/ (decision 0001).
     * A copy in git is a copy that drifts; this proves the copy the app reads
     * is the file the Worker's own coverage test holds to the relay's source.
     */
    @Test
    fun `the asset is byte for byte the file in data`() {
        assertEquals(
            File("../../data/relay-outcomes.json").readText(),
            File("src/main/assets/relay-outcomes.json").readText(),
        )
    }
}
