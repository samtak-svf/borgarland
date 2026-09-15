package `is`.borgarland.photo

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * What actually goes to the relay: a photograph the city can take, and nothing
 * else about it (#2, #61).
 *
 * Two things happen here, and they are separate reasons for the same step.
 *
 * **The size.** `data/reykjavik-form.json` records that the city's maximum
 * upload size is *unknown* — its client sets no `maxSize`, so finding the limit
 * means uploading until something breaks, and the uplink is the only place a
 * report can fail with nothing to show for it. What is measured is how close a
 * real capture gets: 1.1 MB from a Galaxy A71 and 2.66 MB from a Galaxy S23
 * Ultra, so *"three photos from a recent phone approach 8 MB and the unknown
 * limit is not academic"*. Two constants below bound what any one report can
 * weigh, whatever the camera produced.
 *
 * **The EXIF.** A photograph carries the device, the software, the timestamp,
 * and — on the gallery path — a position. This app submits its coordinate in
 * the relay's own field, so the rest of that block is metadata the city did not
 * ask for and the reporter never chose to send. Re-encoding through
 * [Bitmap.compress] is what removes it: the platform's JPEG encoder writes an
 * image, not a container of somebody else's metadata.
 *
 * What this deliberately does NOT touch: the copy in the reporter's own
 * gallery. Decision 0018 is that the saved photograph is byte-faithful to what
 * the camera produced, so the gallery keeps the original bytes and only the
 * upload is rewritten. Two copies of one photograph is the price of that, and
 * it is a few megabytes for as long as the report takes to build.
 */
object PhotoUpload {

    /**
     * The longest edge kept, in pixels.
     *
     * 2048 is twice a phone's width, which keeps what a crew is being sent to
     * look at legible — a number plate, a burst bag, a street sign — while
     * bounding the file. Chosen rather than measured, and the measurement is
     * what it produces: see the sizes in the PR and in the field-test record
     * for the walk this landed on.
     */
    const val MAX_EDGE = 2048

    /**
     * JPEG quality after the rescale.
     *
     * 85 is the usual knee of the curve and the facts file has the shape of it
     * from the other direction: a 4.14 MB HEIC became 4.78 MB as JPEG at 90 and
     * 3.30 MB at 80. Rescaling does most of the work here; this is the setting
     * that does not undo it.
     */
    const val QUALITY = 85

    /**
     * The size (width, height) to scale to: the aspect ratio is preserved, the
     * longest edge is [maxEdge], and a photograph already inside the bound is
     * returned unchanged rather than enlarged.
     *
     * Pure arithmetic, and the only part of this file a JVM unit test can
     * reach — which is why it is a separate function rather than three lines
     * inside [prepare]: the rounding at the edges is where a rescale goes
     * wrong, and it is checkable here.
     */
    fun targetSize(width: Int, height: Int, maxEdge: Int = MAX_EDGE): Pair<Int, Int> {
        val longest = max(width, height)
        if (longest <= 0 || longest <= maxEdge) return width to height
        val scale = maxEdge.toDouble() / longest
        // Never zero: a 10000x1 panorama scaled by height would round to 0 and
        // `createScaledBitmap` throws on a zero dimension.
        return max(1, (width * scale).roundToInt()) to max(1, (height * scale).roundToInt())
    }

    /**
     * The bytes to upload: rotated upright, rescaled, re-encoded, EXIF gone.
     *
     * Null when the capture cannot be decoded, and the caller then sends what
     * the camera produced rather than nothing. A photograph the city may refuse
     * for its size is a far better outcome than a report with no photograph,
     * and the telemetry records which happened.
     *
     * [rotationDegrees] is applied here rather than carried as a field, because
     * the re-encode is the only chance to get it right: EXIF orientation is not
     * written by [Bitmap.compress], so a rotated capture that skipped this step
     * would arrive sideways.
     */
    fun prepare(bytes: ByteArray, rotationDegrees: Int): ByteArray? {
        val decoded = runCatching {
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }.getOrNull() ?: return null

        val oriented = if (rotationDegrees % 360 == 0) {
            decoded
        } else {
            runCatching {
                Bitmap.createBitmap(
                    decoded, 0, 0, decoded.width, decoded.height,
                    Matrix().apply { postRotate(rotationDegrees.toFloat()) }, true,
                )
            }.getOrNull() ?: decoded
        }

        val (width, height) = targetSize(oriented.width, oriented.height)
        val scaled = if (width == oriented.width && height == oriented.height) {
            oriented
        } else {
            runCatching { Bitmap.createScaledBitmap(oriented, width, height, true) }.getOrNull() ?: oriented
        }

        val out = ByteArrayOutputStream()
        val ok = runCatching {
            scaled.compress(Bitmap.CompressFormat.JPEG, QUALITY, out)
        }.getOrDefault(false)

        // Wrapped as a whole: a bitmap that cannot be recycled must not be able
        // to take the caller down with it. The bytes are already in `out` by
        // this point.
        runCatching {
            if (scaled !== oriented) scaled.recycle()
            if (oriented !== decoded) oriented.recycle()
            decoded.recycle()
        }

        return if (ok) out.toByteArray() else null
    }
}
