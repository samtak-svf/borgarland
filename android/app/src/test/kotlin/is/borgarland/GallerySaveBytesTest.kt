package `is`.borgarland

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The gallery keeps what the camera produced, and the upload copy is not it
 * (#2, decision 0018).
 *
 * Since #2 `state.photo.bytes` is the rescaled, re-encoded copy: the one that
 * goes on the wire, with its metadata re-encoded away. `PhotoUpload` says so,
 * [PhotoUploadTest] holds the arithmetic, and on API 29+ the gallery save
 * happens at capture time from the capture itself, so nothing is at risk.
 *
 * The path this guards is the other one. On API 26–28 the save needs
 * WRITE_EXTERNAL_STORAGE, and when it is missing the capture-time save is
 * skipped and the camera screen calls `saveCurrentPhotoToGallery()` after the
 * grant — a different moment, and the only save those devices ever get. Read
 * from the wrong field there and the gallery receives a 2048 px re-encode,
 * which is exactly the claim decision 0018 makes and would now be false.
 *
 * A source guard, in the shape [NoCityEndpointTest] and [WalkCaptureTest]
 * already use, because no test in this module can enter that path: it needs a
 * Context, a MediaStore and an API level below 29, and a JVM unit test has
 * none of them. The guard is narrow on purpose — it asks where the bytes come
 * from, not how the function is written.
 */
class GallerySaveBytesTest {

    private val viewModel = File("src/main/kotlin/is/borgarland/PocViewModel.kt")

    private fun source(): String {
        assertTrue("expected ${viewModel.absolutePath} to exist", viewModel.isFile)
        return KotlinSource.stripComments(viewModel.readText())
    }

    private fun bodyOf(signature: String): String {
        val source = source()
        val start = source.indexOf(signature)
        assertTrue("$signature is gone from PocViewModel", start >= 0)
        val end = source.indexOf("\n    }", start)
        assertTrue("could not find the end of $signature", end > start)
        return source.substring(start, end)
    }

    @Test
    fun `the deferred gallery save writes the capture, not the upload copy`() {
        val body = bodyOf("fun saveCurrentPhotoToGallery()")

        assertTrue(
            "the deferred save must read the captured bytes; it reads:\n$body",
            body.contains("capturedBytes"),
        )
        assertFalse(
            "the deferred save must not reach for state.photo.bytes — since #2 that is the " +
                "rescaled upload copy, and decision 0018 is that the gallery keeps the capture; " +
                "it reads:\n$body",
            Regex("""photo\s*\??\s*\.\s*bytes""").containsMatchIn(body),
        )
    }

    @Test
    fun `the capture stores the bytes the camera produced`() {
        val body = bodyOf("fun onPhotoCaptured(")

        assertTrue(
            "nothing sets capturedBytes, so the deferred save has nothing to write; " +
                "onPhotoCaptured reads:\n$body",
            body.contains("capturedBytes = bytes"),
        )
    }
}
