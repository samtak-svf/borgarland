package `is`.borgarland

import `is`.borgarland.photo.PhotoUpload
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * #2: the photograph that goes to the relay is bounded in size.
 *
 * What is testable here is the arithmetic, and that is why [PhotoUpload.targetSize]
 * is a function rather than three lines inside the rescale. The rescale itself
 * needs `BitmapFactory` and `Bitmap.compress`, which a JVM unit test cannot
 * reach at all, so the sizes it actually produces are measured on a device and
 * recorded in the field-test entry for the walk that landed this — the same
 * split as the EXIF reader, whose parser is pure Kotlin and whose capture path
 * is not.
 */
class PhotoUploadTest {

    @Test
    fun `a photograph already inside the bound is not enlarged`() {
        assertEquals(640 to 480, PhotoUpload.targetSize(640, 480, maxEdge = 2048))
        assertEquals(2048 to 1000, PhotoUpload.targetSize(2048, 1000, maxEdge = 2048))
    }

    @Test
    fun `a large photograph is scaled so its longest edge is the bound`() {
        // A Galaxy S23 Ultra capture, which the facts file measures at 2.66 MB.
        assertEquals(2048 to 1536, PhotoUpload.targetSize(4000, 3000, maxEdge = 2048))
        // Portrait, because the bound applies to the longest edge and not to width.
        assertEquals(1536 to 2048, PhotoUpload.targetSize(3000, 4000, maxEdge = 2048))
    }

    @Test
    fun `a panorama does not collapse a dimension to zero`() {
        // 10000x1 scaled by height alone rounds to 0, and createScaledBitmap
        // throws on a zero dimension — a crash on a photograph nobody would
        // call unusual.
        val (width, height) = PhotoUpload.targetSize(10000, 1, maxEdge = 2048)

        assertEquals(2048, width)
        assertEquals(1, height)
    }

    @Test
    fun `the bound in the code is the bound the city's unknown limit needs`() {
        // Not a tautology: the two constants are the whole policy, and this is
        // the assertion that a later session raising MAX_EDGE to 8000 has to
        // argue with. 2048x2048 at quality 85 lands in the hundreds of
        // kilobytes, against a ceiling `data/reykjavik-form.json` records as
        // unknown and a measured 4.9 MB that the city accepted.
        assertEquals(2048, PhotoUpload.MAX_EDGE)
        assertEquals(85, PhotoUpload.QUALITY)
    }
}
