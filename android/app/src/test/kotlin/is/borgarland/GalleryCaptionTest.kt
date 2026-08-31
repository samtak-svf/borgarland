package `is`.borgarland

import `is`.borgarland.ui.GalleryCaption
import `is`.borgarland.ui.galleryCaption
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * #201. Both facets of the lying caption, pinned as a truth table rather than
 * as a screenshot, because the state that produced it is only reachable on
 * API 26-28 and no device in the building runs one.
 *
 * The mirror is `GalleryCaptionTest.swift` in BorgarlandCore, and the two must
 * agree row for row.
 */
class GalleryCaptionTest {

    @Test
    fun `the switch off never claims the photograph is saved`() {
        // The whole of the second facet. The caption used to read from
        // galleryBlocked alone, so this case rendered "einnig vistuð" while
        // nothing was being written — on every API level, not just the cliff.
        assertEquals(GalleryCaption.NOT_SAVING, galleryCaption(saveToGallery = false, galleryBlocked = false))
    }

    @Test
    fun `the switch on and nothing blocking says the photograph is saved`() {
        assertEquals(GalleryCaption.SAVING, galleryCaption(saveToGallery = true, galleryBlocked = false))
    }

    @Test
    fun `a refused permission outranks the switch`() {
        assertEquals(GalleryCaption.BLOCKED, galleryCaption(saveToGallery = true, galleryBlocked = true))
    }

    @Test
    fun `a switch that is off outranks a block`() {
        // Unreachable today: galleryBlocked is computed as `save && refused`,
        // so it cannot be true with the switch off. Pinned because it is the
        // row that decides the ordering inside galleryCaption — if a future
        // caller ever sets the flag without the switch, the honest sentence is
        // that nothing is saved, not a red warning about a permission the
        // person has opted out of needing.
        assertEquals(GalleryCaption.NOT_SAVING, galleryCaption(saveToGallery = false, galleryBlocked = true))
    }
}
