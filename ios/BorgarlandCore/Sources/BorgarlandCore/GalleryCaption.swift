import Foundation

/// Which of the three things the gallery-save row can honestly say (#201).
///
/// Lives in the core package rather than beside the view because the same
/// decision is made in `android/app/src/main/kotlin/is/borgarland/ui/GalleryCaption.kt`
/// and the two must not drift, and because this is the only iOS target with
/// tests. The Icelandic sentences stay in `DetailsScreen`, where every other
/// UI string in this app already lives.
public enum GalleryCaption: Sendable, Equatable {
    /// The permission is refused for good, so the switch cannot be honoured.
    case blocked
    /// The switch is on and the photograph is being written to the album.
    case saving
    /// The switch is off. Nothing is written, and the row must not claim it is.
    case notSaving
}

/// The switch is read FIRST, and that ordering is deliberate. `galleryBlocked`
/// is computed as `save && isDeniedForGood`, so the two can only disagree if
/// some future caller sets the flag without the switch — and in that state the
/// honest sentence is that nothing is being saved, not a red warning about a
/// permission the person has already opted out of needing.
///
/// This is the second facet of #201: the caption was a function of
/// `galleryBlocked` alone, so with the switch OFF it went on claiming the
/// photograph was saved. The first facet is freshness, and no pure function
/// can fix it — on iOS `PHPhotoLibrary` never re-prompts once denied, so
/// `ReportModel.refreshGalleryBlocked()` after the save attempt is what makes
/// these inputs true at the moment they are read.
public func galleryCaption(saveToGallery: Bool, galleryBlocked: Bool) -> GalleryCaption {
    if !saveToGallery { return .notSaving }
    if galleryBlocked { return .blocked }
    return .saving
}
