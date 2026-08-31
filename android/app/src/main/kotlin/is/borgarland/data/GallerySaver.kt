package `is`.borgarland.data

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Writes a captured photograph into the device gallery, into a named album
 * (`Borgarland`), so a person keeps the picture they took after the report is
 * filed (#179). The bytes are the app's own JPEG, unaltered — no re-encode,
 * and no EXIF GPS written (decision 0018).
 *
 * The permission cliff is API-level, not a choice: on API 29+ an app
 * inserting its OWN images into MediaStore needs no permission at all; on
 * 26–28 it needs WRITE_EXTERNAL_STORAGE, which the manifest declares with
 * `maxSdkVersion=28` so it cannot appear on newer devices. The caller decides
 * whether the permission is granted; this file only writes.
 *
 * A failure to save is never a failure of the report. The capture already
 * happened and the bytes are in the report; the gallery copy is a courtesy.
 * So every failure path here returns false rather than throwing, and no
 * caller treats a false as anything but the copy not existing.
 */
object GallerySaver {

    /** The album folder name, both here and in the iOS save path (#179). */
    const val ALBUM = "Borgarland"

    private fun fileName(nowMs: Long): String = "borgarland-${nowMs}.jpg"

    /**
     * Save on the current API level's own terms. Returns whether the bytes
     * reached the gallery.
     */
    fun save(context: Context, bytes: ByteArray, nowMs: Long): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveScoped(context, bytes, nowMs)
        } else {
            saveLegacy(context, bytes, nowMs)
        }

    /**
     * API 29+: MediaStore owns the file. RELATIVE_PATH puts it under
     * Pictures/Borgarland, which the gallery shows as an album; IS_PENDING
     * keeps it invisible until the bytes are written, so a half-written photo
     * never appears as a broken thumbnail.
     */
    private fun saveScoped(context: Context, bytes: ByteArray, nowMs: Long): Boolean = runCatching {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName(nowMs))
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/$ALBUM")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri: Uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return@runCatching false
        resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: return@runCatching false
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        true
    }.getOrDefault(false)

    /**
     * API 26–28: no RELATIVE_PATH, so the album is a real directory and the
     * DATA column names the file inside it. WRITE_EXTERNAL_STORAGE is what
     * makes the write legal; the manifest limits it to these API levels.
     */
    private fun saveLegacy(context: Context, bytes: ByteArray, nowMs: Long): Boolean = runCatching {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            ALBUM,
        )
        if (!dir.exists() && !dir.mkdirs()) return@runCatching false
        val target = File(dir, fileName(nowMs))
        target.writeBytes(bytes)
        // The gallery only sees a file once MediaScanner has indexed it.
        MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), arrayOf("image/jpeg"), null)
        true
    }.getOrDefault(false)
}
