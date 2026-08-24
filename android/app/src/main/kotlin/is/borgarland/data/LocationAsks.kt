package `is`.borgarland.data

import android.content.Context
import java.io.File

/**
 * Whether this install has ever put the location dialog up.
 *
 * The one fact Android will not tell us, and the one
 * [LocationPermission.willPrompt] needs: shouldShowRequestPermissionRationale
 * reads false both before the first ask and after the last one, so a fresh
 * install and a permanently refused one are indistinguishable without a memory
 * of our own (#139).
 *
 * A file rather than SharedPreferences, and an empty one: the question is
 * whether we have asked, so its existence is the whole answer and there is
 * nothing to parse, migrate or corrupt. It follows the shape FollowUps settled
 * on in #129 -- a Context entry point delegating to a File-based twin -- so the
 * round trip can be tested without a device, which is the gap that let a revert
 * of #76 leave every test green (#89).
 *
 * It lives as long as the install. Clearing app data resets it, which is
 * correct: clearing app data resets the permission too.
 */
object LocationAsks {
    private const val FILE = "location-asked"

    /** True once [remember] has run at any point in this install's life. */
    fun asked(ctx: Context): Boolean = asked(ctx.filesDir)

    internal fun asked(dir: File): Boolean = File(dir, FILE).exists()

    /**
     * Called when the launcher is fired, not when a dialog is confirmed to have
     * appeared. Firing it is what makes the platform's answer meaningful from
     * then on, and that is the question this file exists to answer.
     */
    fun remember(ctx: Context) {
        remember(ctx.filesDir)
    }

    internal fun remember(dir: File) {
        // A failure here costs an over-count on one phone, never a crash on a
        // walk. The same judgement FollowUps makes about its own writes.
        runCatching { File(dir, FILE).createNewFile() }
    }
}
