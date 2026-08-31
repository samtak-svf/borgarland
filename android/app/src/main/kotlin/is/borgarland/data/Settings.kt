package `is`.borgarland.data

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * The device's preferences for the app, kept in `filesDir` like the other
 * device state (#179). One value today: whether a captured photograph is also
 * saved to the device gallery.
 *
 * Default ON, deliberately: the surprising behaviour is the one that keeps
 * nothing (#179's decision), and a person who does not want the picture kept
 * can turn the toggle off — while a person who wanted it and did not know to
 * ask has already lost it.
 *
 * This file never leaves the device and is not part of a report: the relay
 * learns nothing about it, and nothing here may enter
 * `data/relay-request.json`.
 */
object Settings {
    private const val FILE = "settings.json"
    private const val KEY_SAVE_TO_GALLERY = "saveToGallery"

    /** The default is the decision: save, unless the person says otherwise. */
    const val DEFAULT_SAVE_TO_GALLERY = true

    private fun file(dir: File) = File(dir, FILE)

    /**
     * Whether a captured photograph should also land in the gallery. A
     * missing file or an unreadable one is the default, never a reason to
     * stop saving: the app was installed moments ago, and the person has not
     * said otherwise.
     */
    fun saveToGallery(dir: File): Boolean {
        val f = file(dir)
        if (!f.exists()) return DEFAULT_SAVE_TO_GALLERY
        val text = runCatching { f.readText() }.getOrNull() ?: return DEFAULT_SAVE_TO_GALLERY
        val o = runCatching { JSONObject(text) }.getOrNull() ?: return DEFAULT_SAVE_TO_GALLERY
        return o.optBoolean(KEY_SAVE_TO_GALLERY, DEFAULT_SAVE_TO_GALLERY)
    }

    /**
     * Write to a sibling file and rename over the target, so a process death
     * mid-write cannot leave truncated JSON that reads back as the default —
     * the same failure `FollowUps` was fixed for in #129, and the same fix.
     *
     * Returns whether the write landed. A failure costs the person a
     * preference they have to re-state; the save path keeps its own default.
     */
    fun setSaveToGallery(dir: File, save: Boolean): Boolean = runCatching {
        val target = file(dir)
        val tmp = File(dir, "$FILE.tmp")
        tmp.writeText(JSONObject().put(KEY_SAVE_TO_GALLERY, save).toString())
        if (!tmp.renameTo(target)) {
            tmp.delete()
            return@runCatching false
        }
        true
    }.getOrDefault(false)

    fun saveToGallery(context: Context): Boolean = saveToGallery(context.filesDir)

    fun setSaveToGallery(context: Context, save: Boolean): Boolean = setSaveToGallery(context.filesDir, save)
}
