package `is`.borgarland.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * The list of reports this phone filed, so it can ask later whether they got
 * fixed (#57, [decision 0013](../../../../../../../decisions/0013-the-follow-up-asks-the-phone-not-the-person.md)).
 *
 * The whole design rests on one fact: the report id is generated HERE, on the
 * phone, before the report is sent (decision 0010). So asking about a report
 * later needs nothing the app does not already have, and in particular it needs
 * no way to contact anybody. The relay is told one bit about a row it already
 * holds; it is told nothing about who filed it.
 *
 * This file never leaves the device. Losing it (reinstall, cleared data) loses
 * the ability to ask, which is the correct trade against a server-side record
 * of who filed what.
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

    data class Pending(
        val id: String,
        val sentAtMs: Long,
        val categorySlug: String,
    )

    /**
     * `asked` is set whether or not the person answers. Being nagged about a
     * bin is how an app gets uninstalled, and somebody who dismisses the
     * question has answered it.
     */
    private data class Row(
        val id: String,
        val sentAtMs: Long,
        val categorySlug: String,
        val asked: Boolean,
    )

    private fun file(ctx: Context) = File(ctx.filesDir, FILE)

    private fun read(ctx: Context): MutableList<Row> {
        val f = file(ctx)
        if (!f.exists()) return mutableListOf()
        // A corrupt or half-written file must not stop the app filing reports,
        // which is the thing it is actually for.
        val text = runCatching { f.readText() }.getOrNull() ?: return mutableListOf()
        val arr = runCatching { JSONArray(text) }.getOrNull() ?: return mutableListOf()
        val out = mutableListOf<Row>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = o.optString("id")
            if (id.isEmpty()) continue
            out.add(
                Row(
                    id = id,
                    sentAtMs = o.optLong("sentAtMs"),
                    categorySlug = o.optString("categorySlug"),
                    asked = o.optBoolean("asked", false),
                ),
            )
        }
        return out
    }

    private fun write(ctx: Context, rows: List<Row>) {
        val arr = JSONArray()
        rows.forEach { r ->
            arr.put(
                JSONObject()
                    .put("id", r.id)
                    .put("sentAtMs", r.sentAtMs)
                    .put("categorySlug", r.categorySlug)
                    .put("asked", r.asked),
            )
        }
        runCatching { file(ctx).writeText(arr.toString()) }
    }

    /** Called when the relay accepted a report. A repeat id is not added twice. */
    fun record(ctx: Context, id: String, categorySlug: String, nowMs: Long) {
        val rows = read(ctx)
        if (rows.any { it.id == id }) return
        rows.add(Row(id = id, sentAtMs = nowMs, categorySlug = categorySlug, asked = false))
        write(ctx, rows)
    }

    /**
     * Whether a report sent at [sentAtMs] is old enough to ask about. Pure and
     * separate from the file so the interval is testable without a device: the
     * boundary is the only interesting thing about it, and a JVM test can reach
     * this while it cannot reach `filesDir`.
     */
    fun isDue(sentAtMs: Long, nowMs: Long): Boolean = nowMs - sentAtMs >= ASK_AFTER_MS

    /**
     * The oldest report that is due and has not been asked about, or null.
     * One question at a time: a queue of them is a nag.
     */
    fun due(ctx: Context, nowMs: Long): Pending? =
        read(ctx)
            .filter { !it.asked && isDue(it.sentAtMs, nowMs) }
            .minByOrNull { it.sentAtMs }
            ?.let { Pending(it.id, it.sentAtMs, it.categorySlug) }

    /** Marks the question as put, whether or not it was answered. */
    fun markAsked(ctx: Context, id: String) {
        val rows = read(ctx)
        val i = rows.indexOfFirst { it.id == id }
        if (i < 0) return
        rows[i] = rows[i].copy(asked = true)
        write(ctx, rows)
    }

    /** Test seam: how many rows are held, and how many are still unasked. */
    fun counts(ctx: Context): Pair<Int, Int> {
        val rows = read(ctx)
        return rows.size to rows.count { !it.asked }
    }
}
