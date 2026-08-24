package `is`.borgarland.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * The list of reports this phone filed, so it can ask later whether they got
 * fixed (#57, decision 0013), and so an answer is not lost when the post fails
 * (#129).
 *
 * The design rests on one fact: the report id is generated HERE, before the
 * report is sent (decision 0010). Asking about a report later needs nothing the
 * app does not already have, and in particular needs no way to contact anybody.
 *
 * This file never leaves the device.
 */
object FollowUps {
    /**
     * Picked rather than measured, and the decision record says so. The city
     * publishes no response-time data, which is the reason this measurement
     * exists, so there is no figure to derive an interval from.
     */
    const val ASK_AFTER_DAYS = 14
    private const val ASK_AFTER_MS = ASK_AFTER_DAYS * 24L * 60L * 60L * 1000L
    private const val FILE = "follow-ups.json"

    /**
     * Rows are dropped once the answer is safely delivered AND they are older
     * than this. Without it the file grows for the life of the install (#129).
     * Generous, because the only cost of keeping a delivered row is bytes and
     * the cost of dropping one too early is asking twice.
     */
    private const val KEEP_AFTER_POST_MS = 90L * 24L * 60L * 60L * 1000L

    data class Pending(
        val id: String,
        val sentAtMs: Long,
        val categorySlug: String,
    )

    /** An answer given but not yet accepted by the relay. */
    data class Unposted(
        val id: String,
        val fixed: Boolean,
    )

    /**
     * `asked` is set whether or not the person answers: somebody who dismisses
     * the question has answered it, and asking again is a nag.
     *
     * `answer` is null for a dismissal and non-null for a real answer. A
     * non-null answer with `posted` false is the retry queue: the person told
     * us something and the relay has not heard it yet.
     */
    private data class Row(
        val id: String,
        val sentAtMs: Long,
        val categorySlug: String,
        val asked: Boolean,
        val answer: Boolean?,
        val posted: Boolean,
    )

    private fun file(dir: File) = File(dir, FILE)

    /**
     * Every public entry point delegates to a `File`-based twin so the round
     * trip can be tested without a device (#129). The biggest gap the audit
     * found was that nothing tested record -> due -> answer -> unposted ->
     * markPosted, because reaching `filesDir` needs a Context and mocking one
     * would have tested the mock.
     */

    private fun read(dir: File): MutableList<Row> {
        val f = file(dir)
        if (!f.exists()) return mutableListOf()
        val text = runCatching { f.readText() }.getOrNull() ?: return mutableListOf()
        val arr = runCatching { JSONArray(text) }.getOrNull() ?: return mutableListOf()
        val out = mutableListOf<Row>()
        val seen = mutableSetOf<String>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = o.optString("id")
            // A duplicate id would be asked about twice, because markAnswered
            // only ever touches the first match. Dropping it on read makes that
            // unreachable regardless of how the file came to hold one (#129).
            if (id.isEmpty() || !seen.add(id)) continue
            out.add(
                Row(
                    id = id,
                    sentAtMs = o.optLong("sentAtMs"),
                    categorySlug = o.optString("categorySlug"),
                    asked = o.optBoolean("asked", false),
                    answer = if (o.has("answer") && !o.isNull("answer")) o.optBoolean("answer") else null,
                    posted = o.optBoolean("posted", false),
                ),
            )
        }
        return out
    }

    /**
     * Write to a sibling file and rename over the target, so a process death
     * mid-write cannot leave truncated JSON (#129).
     *
     * That mattered more than it looks: `read` treats unparseable content as an
     * empty list, and the next write then persists the empty list. A crash at
     * the wrong microsecond silently erased every remembered report, and the
     * comment above `read` called that resilience.
     *
     * Returns whether the write landed, so a caller can tell.
     */
    private fun write(dir: File, rows: List<Row>): Boolean {
        val arr = JSONArray()
        rows.forEach { r ->
            val o = JSONObject()
                .put("id", r.id)
                .put("sentAtMs", r.sentAtMs)
                .put("categorySlug", r.categorySlug)
                .put("asked", r.asked)
                .put("posted", r.posted)
            if (r.answer != null) o.put("answer", r.answer) else o.put("answer", JSONObject.NULL)
            arr.put(o)
        }
        return runCatching {
            val target = file(dir)
            val tmp = File(dir, "$FILE.tmp")
            tmp.writeText(arr.toString())
            if (!tmp.renameTo(target)) {
                // Rename is atomic on the same filesystem; if it somehow fails,
                // leave the previous file intact rather than half-writing over it.
                tmp.delete()
                return@runCatching false
            }
            true
        }.getOrDefault(false)
    }

    /** Called when the relay accepted a report. A repeat id is not added twice. */
    fun record(ctx: Context, id: String, categorySlug: String, nowMs: Long): Boolean =
        record(ctx.filesDir, id, categorySlug, nowMs)

    internal fun record(dir: File, id: String, categorySlug: String, nowMs: Long): Boolean {
        val rows = read(dir)
        if (rows.any { it.id == id }) return true
        rows.add(
            Row(
                id = id,
                sentAtMs = nowMs,
                categorySlug = categorySlug,
                asked = false,
                answer = null,
                posted = false,
            ),
        )
        return write(dir, prune(rows, nowMs))
    }

    /**
     * Whether a report sent at [sentAtMs] is old enough to ask about. Pure and
     * separate from the file so the interval is testable without a device.
     */
    fun isDue(sentAtMs: Long, nowMs: Long): Boolean = nowMs - sentAtMs >= ASK_AFTER_MS

    /**
     * The oldest report that is due and has not been asked about, or null.
     * One question at a time: a queue of them is a nag.
     */
    fun due(ctx: Context, nowMs: Long): Pending? = due(ctx.filesDir, nowMs)

    internal fun due(dir: File, nowMs: Long): Pending? =
        read(dir)
            .filter { !it.asked && isDue(it.sentAtMs, nowMs) }
            .minByOrNull { it.sentAtMs }
            ?.let { Pending(it.id, it.sentAtMs, it.categorySlug) }

    /**
     * The person answered. Recorded BEFORE the post is attempted and kept until
     * the relay confirms, so a failed send is retried rather than lost (#129).
     */
    fun markAnswered(ctx: Context, id: String, fixed: Boolean): Boolean =
        markAnswered(ctx.filesDir, id, fixed)

    internal fun markAnswered(dir: File, id: String, fixed: Boolean): Boolean =
        update(dir, id) { it.copy(asked = true, answer = fixed, posted = false) }

    /** Dismissed without answering. Asked, but there is nothing to deliver. */
    fun markDismissed(ctx: Context, id: String): Boolean = markDismissed(ctx.filesDir, id)

    internal fun markDismissed(dir: File, id: String): Boolean =
        update(dir, id) { it.copy(asked = true, answer = null, posted = true) }

    /** The relay accepted the answer; stop retrying it. */
    fun markPosted(ctx: Context, id: String): Boolean = markPosted(ctx.filesDir, id)

    internal fun markPosted(dir: File, id: String): Boolean =
        update(dir, id) { it.copy(posted = true) }

    /** Answers the relay has not accepted yet, oldest first. */
    fun unposted(ctx: Context): List<Unposted> = unposted(ctx.filesDir)

    internal fun unposted(dir: File): List<Unposted> =
        read(dir)
            .filter { it.answer != null && !it.posted }
            .sortedBy { it.sentAtMs }
            .map { Unposted(it.id, it.answer == true) }

    private fun update(dir: File, id: String, f: (Row) -> Row): Boolean {
        val rows = read(dir)
        val i = rows.indexOfFirst { it.id == id }
        if (i < 0) return false
        rows[i] = f(rows[i])
        return write(dir, rows)
    }

    /** Delivered rows older than the keep window are dropped. */
    private fun prune(rows: List<Row>, nowMs: Long): List<Row> =
        rows.filterNot { it.posted && nowMs - it.sentAtMs > KEEP_AFTER_POST_MS }

    /** Test seam: total rows, unasked rows, and answers awaiting delivery. */
    fun counts(ctx: Context): Triple<Int, Int, Int> = counts(ctx.filesDir)

    internal fun counts(dir: File): Triple<Int, Int, Int> {
        val rows = read(dir)
        return Triple(
            rows.size,
            rows.count { !it.asked },
            rows.count { it.answer != null && !it.posted },
        )
    }
}
