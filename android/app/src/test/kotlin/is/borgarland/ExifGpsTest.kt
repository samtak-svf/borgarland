package `is`.borgarland

import `is`.borgarland.exif.ExifGps
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Exercises the Kotlin port of exifGps from scripts/send-report.mjs against
 * hand-built JPEG/EXIF buffers in both TIFF endiannesses and both reference
 * hemispheres, plus the malformed-input cases that must read as "no GPS".
 */
class ExifGpsTest {

    @Test
    fun readsLittleEndianNorthEast() {
        val bytes = jpegWithGps(
            le = true, latRef = 'N', lngRef = 'E',
            latNum = intArrayOf(64, 8, 48), latDen = intArrayOf(1, 1, 1),
            lngNum = intArrayOf(21, 56, 3456), lngDen = intArrayOf(1, 1, 100),
        )
        val gps = ExifGps.read(bytes)
        assertNotNull(gps)
        assertEquals(64 + 8.0 / 60 + 48.0 / 3600, gps!!.lat, 1e-12)
        assertEquals(21 + 56.0 / 60 + 34.56 / 3600, gps.lng, 1e-12)
    }

    @Test
    fun readsBigEndianSouthWest() {
        val bytes = jpegWithGps(
            le = false, latRef = 'S', lngRef = 'W',
            latNum = intArrayOf(64, 8, 48), latDen = intArrayOf(1, 1, 1),
            lngNum = intArrayOf(21, 56, 3456), lngDen = intArrayOf(1, 1, 100),
        )
        val gps = ExifGps.read(bytes)
        assertNotNull(gps)
        assertEquals(-(64 + 8.0 / 60 + 48.0 / 3600), gps!!.lat, 1e-12)
        assertEquals(-(21 + 56.0 / 60 + 34.56 / 3600), gps.lng, 1e-12)
    }

    @Test
    fun notAJpegIsNoGps() {
        assertNull(ExifGps.read("not a jpeg".toByteArray()))
        assertNull(ExifGps.read(byteArrayOf(0, 1, 2, 3)))
    }

    @Test
    fun jpegWithoutExifIsNoGps() {
        val bare = byteArrayOf(
            0xFF.toByte(), 0xD8.toByte(), // SOI
            0xFF.toByte(), 0xD9.toByte(), // EOI
        )
        assertNull(ExifGps.read(bare))
    }

    @Test
    fun exifWithoutGpsIfdIsNoGps() {
        // APP1 + TIFF whose IFD0 holds no 0x8825 pointer.
        val tiff = ByteArray(18)
        tiff[0] = 'I'.code.toByte(); tiff[1] = 'I'.code.toByte()
        tiff[2] = 42; tiff[3] = 0
        tiff[4] = 8; tiff[5] = 0; tiff[6] = 0; tiff[7] = 0 // IFD0 at offset 8
        tiff[8] = 0; tiff[9] = 0 // zero entries
        val jpeg = jpegWithSegment(0xFFE1, "Exif\u0000\u0000".toByteArray() + tiff)
        assertNull(ExifGps.read(jpeg))
    }

    @Test
    fun truncatedExifIsNoGpsNotACrash() {
        val tiff = ByteArray(10)
        tiff[0] = 'I'.code.toByte(); tiff[1] = 'I'.code.toByte()
        val jpeg = jpegWithSegment(0xFFE1, "Exif\u0000\u0000".toByteArray() + tiff)
        assertNull(ExifGps.read(jpeg))
    }

    // ------------------------------------------------------------ fixtures

    private fun jpegWithGps(
        le: Boolean,
        latRef: Char,
        lngRef: Char,
        latNum: IntArray,
        latDen: IntArray,
        lngNum: IntArray,
        lngDen: IntArray,
    ): ByteArray {
        val ifd0Offset = 8
        val gpsIfdOffset = 26
        val rationalsOffset = 80
        val tiff = ByteArray(rationalsOffset + 48)

        fun putU16(pos: Int, v: Int) {
            if (le) {
                tiff[pos] = (v and 0xFF).toByte()
                tiff[pos + 1] = ((v ushr 8) and 0xFF).toByte()
            } else {
                tiff[pos] = ((v ushr 8) and 0xFF).toByte()
                tiff[pos + 1] = (v and 0xFF).toByte()
            }
        }

        fun putU32(pos: Int, v: Int) {
            for (i in 0 until 4) {
                val shift = if (le) i * 8 else (3 - i) * 8
                tiff[pos + i] = ((v ushr shift) and 0xFF).toByte()
            }
        }

        fun putRationals(pos: Int, nums: IntArray, dens: IntArray) {
            for (i in nums.indices) {
                putU32(pos + i * 8, nums[i])
                putU32(pos + i * 8 + 4, dens[i])
            }
        }

        // TIFF header
        tiff[0] = if (le) 'I'.code.toByte() else 'M'.code.toByte()
        tiff[1] = if (le) 'I'.code.toByte() else 'M'.code.toByte()
        putU16(2, 42)
        putU32(4, ifd0Offset)

        // IFD0: one entry, the GPS IFD pointer (tag 0x8825, LONG, count 1)
        putU16(ifd0Offset, 1)
        val e0 = ifd0Offset + 2
        putU16(e0, 0x8825)
        putU16(e0 + 2, 4) // LONG
        putU32(e0 + 4, 1)
        putU32(e0 + 8, gpsIfdOffset)
        putU32(e0 + 12, 0) // next IFD pointer

        // GPS IFD: lat ref (0x0001), lat (0x0002), lng ref (0x0003), lng (0x0004)
        putU16(gpsIfdOffset, 4)
        var e = gpsIfdOffset + 2
        // 0x0001 ASCII, count 2, inline value "N\0"
        putU16(e, 0x0001); putU16(e + 2, 2); putU32(e + 4, 2)
        tiff[e + 8] = latRef.code.toByte()
        e += 12
        // 0x0002 RATIONAL, count 3, out-of-line
        putU16(e, 0x0002); putU16(e + 2, 5); putU32(e + 4, 3); putU32(e + 8, rationalsOffset)
        e += 12
        // 0x0003 ASCII, count 2, inline value "E\0"
        putU16(e, 0x0003); putU16(e + 2, 2); putU32(e + 4, 2)
        tiff[e + 8] = lngRef.code.toByte()
        e += 12
        // 0x0004 RATIONAL, count 3, out-of-line
        putU16(e, 0x0004); putU16(e + 2, 5); putU32(e + 4, 3); putU32(e + 8, rationalsOffset + 24)
        putU32(e + 12, 0) // next IFD pointer

        putRationals(rationalsOffset, latNum, latDen)
        putRationals(rationalsOffset + 24, lngNum, lngDen)

        return jpegWithSegment(0xFFE1, "Exif\u0000\u0000".toByteArray() + tiff)
    }

    private fun jpegWithSegment(marker: Int, payload: ByteArray): ByteArray {
        val size = payload.size + 2 // the size field covers the payload plus itself
        val jpeg = ByteArray(2 + 2 + size + 2)
        jpeg[0] = 0xFF.toByte()
        jpeg[1] = 0xD8.toByte()
        jpeg[2] = 0xFF.toByte()
        jpeg[3] = marker.toByte()
        jpeg[4] = ((size ushr 8) and 0xFF).toByte()
        jpeg[5] = (size and 0xFF).toByte()
        payload.copyInto(jpeg, 6)
        jpeg[jpeg.size - 2] = 0xFF.toByte()
        jpeg[jpeg.size - 1] = 0xD9.toByte()
        return jpeg
    }
}
