package `is`.borgarland.ui

/**
 * Which of the three things the gallery-save row can honestly say (#201).
 *
 * Pure and platform-shaped rather than Compose-shaped, because the same
 * decision is made in `ios/BorgarlandCore/Sources/BorgarlandCore/GalleryCaption.swift`
 * and the two must not drift. The Icelandic sentences stay at the view layer
 * on each platform, where every other UI string in this app already lives.
 */
enum class GalleryCaption {
    /** The permission is refused for good, so the switch cannot be honoured. */
    BLOCKED,

    /** The switch is on and the photograph is being written to the album. */
    SAVING,

    /** The switch is off. Nothing is written, and the row must not claim it is. */
    NOT_SAVING,
}

/**
 * The switch is read FIRST, and that ordering is deliberate. `galleryBlocked`
 * is computed as `save && refused`, so the two can only disagree if some
 * future caller sets the flag without the switch — and in that state the
 * honest sentence is that nothing is being saved, not a red warning about a
 * permission the person has already opted out of needing. Reading the block
 * first would answer a question nobody asked.
 *
 * This is the second facet of #201: the caption was a function of
 * `galleryBlocked` alone, so with the switch OFF it went on claiming the
 * photograph was saved, on every API level rather than just the 26-28 cliff.
 * The first facet is freshness, and no pure function can fix it —
 * `PocViewModel.onStoragePermissionResult` is what makes these inputs true at
 * the moment they are read.
 */
fun galleryCaption(saveToGallery: Boolean, galleryBlocked: Boolean): GalleryCaption = when {
    !saveToGallery -> GalleryCaption.NOT_SAVING
    galleryBlocked -> GalleryCaption.BLOCKED
    else -> GalleryCaption.SAVING
}
