package `is`.borgarland.data

import android.content.Context
import java.io.File

/**
 * Whether this install has ever asked for WRITE_EXTERNAL_STORAGE (API 26–28,
 * the gallery save's permission cliff — #179). The same fact and the same
 * shape as [LocationAsks]: Android's shouldShowRequestPermissionRationale
 * reads false both before the first ask and after the last one, so a fresh
 * install and a permanently refused one are indistinguishable without a
 * memory of our own — and the save toggle must tell refused from not-yet-asked
 * rather than sitting on "saving" while nothing is saved.
 *
 * A file rather than SharedPreferences, and an empty one, exactly like
 * LocationAsks: existence is the whole answer. It lives as long as the
 * install, which is correct — clearing app data resets the permission too.
 */
object StorageAsks {
    private const val FILE = "storage-asked"

    /** True once [remember] has run at any point in this install's life. */
    fun asked(ctx: Context): Boolean = asked(ctx.filesDir)

    internal fun asked(dir: File): Boolean = File(dir, FILE).exists()

    /** Called when the launcher is fired, not when a dialog is confirmed. */
    fun remember(ctx: Context) {
        remember(ctx.filesDir)
    }

    internal fun remember(dir: File) {
        runCatching { File(dir, FILE).createNewFile() }
    }
}
