package `is`.borgarland.exif

/**
 * Kotlin port of the exifGps reader in scripts/send-report.mjs (borgarland
 * repo), kept deliberately small and dependency-free: a coordinate out of a
 * photo and nothing else out of EXIF.
 *
 * It walks the JPEG segments to APP1, reads the TIFF header for endianness,
 * finds the GPS IFD via tag 0x8825 in IFD0, and pulls the four tags that
 * matter: 0x0001/0x0002 (latitude reference and value) and 0x0003/0x0004
 * (longitude reference and value). Rationals are stored out of line as
 * numerator/denominator pairs; the reference ASCII values are read inline.
 *
 * Any malformed input reads as no GPS, mirroring the script's nulls. The
 * caller is responsible for the finiteness and WGS84 range guard.
 */
data class GpsCoordinate(val lat: Double, val lng: Double)

object ExifGps {

    fun read(bytes: ByteArray): GpsCoordinate? = try {
        readOrNull(bytes)
    } catch (_: Exception) {
        null // malformed EXIF reads as no GPS, never as a crash
    }

    private fun readOrNull(bytes: ByteArray): GpsCoordinate? {
        if (bytes.size < 4) return null
        if ((bytes[0].toInt() and 0xFF) != 0xFF || (bytes[1].toInt() and 0xFF) != 0xD8) return null // not a JPEG

        var off = 2
        var tiff = -1
        while (off < bytes.size - 4) {
            if ((bytes[off].toInt() and 0xFF) != 0xFF) break
            val marker = u16be(bytes, off)
            val size = u16be(bytes, off + 2)
            if (marker == 0xFFE1 && ascii(bytes, off + 4, off + 10) == "Exif\u0000\u0000") {
                tiff = off + 10
                break
            }
            if (marker == 0xFFDA) break // start of scan: no EXIF before the image data
            off += 2 + size
        }
        if (tiff < 0) return null
        if (tiff + 8 > bytes.size) return null

        val le = ascii(bytes, tiff, tiff + 2) == "II"
        val u16: (Int) -> Int = { p -> if (le) u16le(bytes, p) else u16be(bytes, p) }
        val u32: (Int) -> Long = { p -> if (le) u32le(bytes, p) else u32be(bytes, p) }

        data class IfdEntry(val tag: Int, val type: Int, val count: Int, val valuePos: Int)

        fun readIfd(start: Int): Map<Int, IfdEntry> {
            val n = u16(start)
            val entries = HashMap<Int, IfdEntry>()
            for (i in 0 until n) {
                val e = start + 2 + i * 12
                if (e + 12 > bytes.size) break
                entries[u16(e)] = IfdEntry(u16(e), u16(e + 2), u32(e + 4).toInt(), e + 8)
            }
            return entries
        }

        val ifd0 = readIfd((tiff + u32(tiff + 4)).toInt())
        val gpsPtr = ifd0[0x8825] ?: return null
        val gps = readIfd((tiff + u32(gpsPtr.valuePos)).toInt())

        fun rationals(entry: IfdEntry): DoubleArray {
            val at = tiff + u32(entry.valuePos).toInt()
            return DoubleArray(entry.count) { i ->
                val numerator = u32(at + i * 8)
                val denominator = u32(at + i * 8 + 4)
                if (denominator == 0L) Double.NaN else numerator.toDouble() / denominator.toDouble()
            }
        }
        val ref: (IfdEntry) -> Char = { entry -> (bytes[entry.valuePos].toInt() and 0xFF).toChar() }

        val lat = gps[0x0002] ?: return null
        val latRef = gps[0x0001] ?: return null
        val lng = gps[0x0004] ?: return null
        val lngRef = gps[0x0003] ?: return null

        val dms: (DoubleArray) -> Double = { v -> v[0] + v[1] / 60 + v[2] / 3600 }
        return GpsCoordinate(
            lat = dms(rationals(lat)) * if (ref(latRef) == 'S') -1 else 1,
            lng = dms(rationals(lng)) * if (ref(lngRef) == 'W') -1 else 1,
        )
    }

    private fun u16be(b: ByteArray, p: Int): Int =
        (b[p].toInt() and 0xFF) shl 8 or (b[p + 1].toInt() and 0xFF)

    private fun u16le(b: ByteArray, p: Int): Int =
        (b[p].toInt() and 0xFF) or ((b[p + 1].toInt() and 0xFF) shl 8)

    private fun u32be(b: ByteArray, p: Int): Long =
        (b[p].toLong() and 0xFF) shl 24 or
            ((b[p + 1].toLong() and 0xFF) shl 16) or
            ((b[p + 2].toLong() and 0xFF) shl 8) or
            (b[p + 3].toLong() and 0xFF)

    private fun u32le(b: ByteArray, p: Int): Long =
        (b[p].toLong() and 0xFF) or
            ((b[p + 1].toLong() and 0xFF) shl 8) or
            ((b[p + 2].toLong() and 0xFF) shl 16) or
            ((b[p + 3].toLong() and 0xFF) shl 24)

    private fun ascii(b: ByteArray, from: Int, to: Int): String {
        val sb = StringBuilder(to - from)
        for (i in from until to) sb.append((b[i].toInt() and 0xFF).toChar())
        return sb.toString()
    }
}
