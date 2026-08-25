package `is`.borgarland.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** One thing to say to a person about what the relay answered. */
@Serializable
data class RelayOutcome(
    /** What happened, in one sentence. */
    val says: String,
    /**
     * What they can do about it, when there is anything. Often there is not,
     * and a made-up suggestion is worse than none.
     */
    val advice: String? = null,
    /**
     * One more sentence, built from a field the relay sent with the answer.
     * Carries a `{name}` placeholder in the file; by the time a screen sees it,
     * [RelayOutcomes.sentence] has either filled it in or removed the sentence.
     */
    val detail: String? = null,
    /**
     * Whether sending the SAME request again could answer differently.
     *
     * Absent means yes, which is the safe default: wrongly retryable costs a
     * wasted request, wrongly terminal takes the only control on the screen
     * away from somebody who could have succeeded (#148).
     */
    val retryable: Boolean = true,
)

/**
 * Our words for what the relay answered, from data/relay-outcomes.json (shipped
 * as an app asset by build.gradle.kts, same pattern as the facts file).
 *
 * A sibling of [CategoryLabelsFile] and separate from [FactsFile] for the same
 * reason: the facts file records what the city says, this one is what WE say to
 * a person. The relay's own answer is not replaced by any of this — it stays on
 * the screen, behind a control the person opens on purpose (#77).
 *
 * No Icelandic sentence appears in this file. That is deliberate and it is why
 * [RelayOutcomes.sentence] returns null rather than falling back to something
 * written here: a second place for our words to live is a second place for them
 * to drift, and a screen with no sentence still has the relay's own answer on
 * it.
 */
@Serializable
data class RelayOutcomesFile(
    /** The relay sent it to the city and the city took it. */
    val sent: RelayOutcome,
    /**
     * The relay took it and forwarded nothing, which is the state it is in
     * today and will be in for every test build.
     */
    val dryRun: RelayOutcome,
    /** Nobody answered at all. */
    val noAnswer: RelayOutcome,
    /**
     * The relay answered with a code this file does not name. Should be
     * unreachable — worker/tests/outcomes.test.ts fails the build when the relay
     * can return a code with no sentence — and exists because "should be
     * unreachable" is not a thing to show somebody raw JSON over.
     */
    val unknown: RelayOutcome,
    /** One entry per error code the relay can answer with. */
    val outcomes: Map<String, RelayOutcome> = emptyMap(),
)

object RelayOutcomes {

    private val json = Json { ignoreUnknownKeys = true }

    fun parse(text: String): RelayOutcomesFile = json.decodeFromString(text)

    /**
     * The two things an app needs out of a relay answer, without modelling the
     * rest of it. The rest is the relay's internal state machine — the stored
     * row, the follow-through fields, the whole city payload — and an app that
     * parsed it would be coupled to every one of them.
     */
    data class Answer(val errorCode: String?, val dryRun: Boolean?)

    /**
     * Reads a relay answer. A body that is not JSON, or is JSON of some other
     * shape, answers null to both questions rather than throwing: this runs on
     * the failure path, where the thing least worth doing is failing again.
     */
    fun read(body: String): Answer {
        val root = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull()
            ?: return Answer(null, null)
        // isString, because contentOrNull hands back the raw text of a number
        // or a boolean too: {"error": 123} would read as the code "123" here
        // while the Swift side's `as? String` reads nil. Same answer either way
        // today, since neither is a key in the file, but the two clients must
        // not disagree about what the relay said.
        val errorCode = runCatching {
            root["error"]?.jsonPrimitive?.takeIf { it.isString }?.contentOrNull
        }.getOrNull()
        val dryRun = runCatching {
            (root["report"] as? JsonObject)?.get("dryRun")?.jsonPrimitive?.boolean
        }.getOrNull()
        return Answer(errorCode, dryRun)
    }

    /**
     * What to tell the person, or null when the file is not there to say it.
     *
     * [status] is 0 when nothing answered, matching the transport's own
     * convention on both platforms.
     */
    fun sentence(status: Int, body: String, file: RelayOutcomesFile?): RelayOutcome? {
        if (file == null) return null
        if (status == 0) return file.noAnswer
        val answer = read(body)
        if (status in 200..299) {
            return if (answer.dryRun == true) file.dryRun else file.sent
        }
        val known = answer.errorCode?.let { file.outcomes[it] }
        return known?.let { filled(it, body) } ?: file.unknown
    }

    /**
     * Fills [RelayOutcome.detail]'s `{name}` placeholders from the relay's own
     * answer.
     *
     * A placeholder with no field behind it removes the whole sentence rather
     * than leaving a hole in it: half a sentence in front of somebody is worse
     * than the silence the screen had before (#148). Only strings are
     * substituted, so a number or a null cannot become the word "null".
     */
    internal fun filled(outcome: RelayOutcome, body: String): RelayOutcome {
        val detail = outcome.detail ?: return outcome
        val root = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull()
            ?: return outcome.copy(detail = null)
        val out = StringBuilder()
        var i = 0
        while (i < detail.length) {
            val open = detail.indexOf('{', i)
            if (open < 0) {
                out.append(detail, i, detail.length)
                break
            }
            val close = detail.indexOf('}', open)
            if (close < 0) {
                out.append(detail, i, detail.length)
                break
            }
            out.append(detail, i, open)
            val key = detail.substring(open + 1, close)
            val value = runCatching {
                root[key]?.jsonPrimitive?.takeIf { it.isString }?.contentOrNull
            }.getOrNull() ?: return outcome.copy(detail = null)
            out.append(value)
            i = close + 1
        }
        return outcome.copy(detail = out.toString())
    }
}
