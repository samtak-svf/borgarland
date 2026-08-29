package `is`.borgarland.data

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * The address the city will answer to, kept on the phone so it is typed once
 * rather than on every walk (#163).
 *
 * It belongs to the DEVICE, not to a report. That is the whole reason it lives
 * here beside `follow-ups.json` rather than inside the payload the person is
 * about to send: a report the phone is holding picks up whatever address the
 * phone holds when it finally goes out, not the one it held when it was
 * written down. Somebody who changes their address gets the confirmation at
 * the new one.
 *
 * This file never leaves the device. What leaves is the address itself, as the
 * `email` part of the report, and only there: the event stream's allowlist
 * (data/relay-events.json) names no free-text field at all, so it cannot ride
 * that channel even by mistake, and the relay does not log it
 * (worker/src/app.ts).
 */
object ContactDetails {
    private const val FILE = "contact-details.json"

    private fun file(dir: File) = File(dir, FILE)

    /**
     * What an address has to look like before the app will send with it, and
     * the only place the rule lives on this platform. iOS carries the same
     * rule in `ContactDetails.isValid`, and both test suites pin the identical
     * table of cases, because two spellings of one rule is two rules.
     *
     * Deliberately loose. A strict RFC 5322 pattern rejects addresses that
     * work, and the cost of that is a person who cannot file at all; the cost
     * of letting an odd-looking address through is a bounce we never see. What
     * it does catch is the typo that loses the confirmation silently —
     * `nafn@`, `nafn`, a stray space, a domain with no dot.
     */
    fun isValid(raw: String): Boolean {
        val value = raw.trim()
        if (value.isEmpty() || value.any { it.isWhitespace() }) return false
        val at = value.indexOf('@')
        if (at <= 0 || at != value.lastIndexOf('@')) return false
        val domain = value.substring(at + 1)
        if (domain.isEmpty() || !domain.contains('.')) return false
        // No empty label: `a@.is`, `a@b..is` and `a@b.` are all typos.
        return domain.split('.').none { it.isEmpty() }
    }

    /** Stored and sent with the surrounding whitespace gone, never otherwise altered. */
    fun normalise(raw: String): String = raw.trim()

    /**
     * The stored address, or null when there is none or the file cannot be
     * read. Null is a prompt to type one, never a reason to send without one:
     * the send path refuses that separately.
     */
    fun read(dir: File): String? {
        val f = file(dir)
        if (!f.exists()) return null
        val text = runCatching { f.readText() }.getOrNull() ?: return null
        val o = runCatching { JSONObject(text) }.getOrNull() ?: return null
        val email = o.optString("email").trim()
        return email.ifEmpty { null }
    }

    /**
     * Write to a sibling and rename over the target, so a process death
     * mid-write cannot leave truncated JSON that reads back as "no address"
     * — the same failure `FollowUps` was fixed for in #129, and the same fix.
     *
     * Returns whether the write landed. A failure costs the person one
     * retyping and nothing else, so no caller has to treat it as fatal.
     */
    fun write(dir: File, email: String?): Boolean = runCatching {
        val target = file(dir)
        val tmp = File(dir, "$FILE.tmp")
        tmp.writeText(JSONObject().put("email", email?.trim().orEmpty()).toString())
        if (!tmp.renameTo(target)) {
            tmp.delete()
            return@runCatching false
        }
        true
    }.getOrDefault(false)

    fun read(context: Context): String? = read(context.filesDir)

    fun write(context: Context, email: String?): Boolean = write(context.filesDir, email)
}
