import XCTest
@testable import BorgarlandCore

/// #201. Both facets of the lying caption, pinned as a truth table rather than
/// as a screenshot. The mirror is `GalleryCaptionTest.kt` in the Android unit
/// tests, and the two must agree row for row.
final class GalleryCaptionTest: XCTestCase {

    func testTheSwitchOffNeverClaimsThePhotographIsSaved() {
        // The whole of the second facet. The caption used to read from
        // galleryBlocked alone, so this case rendered "einnig vistuð" while
        // nothing was being written.
        XCTAssertEqual(galleryCaption(saveToGallery: false, galleryBlocked: false), .notSaving)
    }

    func testTheSwitchOnAndNothingBlockingSaysThePhotographIsSaved() {
        XCTAssertEqual(galleryCaption(saveToGallery: true, galleryBlocked: false), .saving)
    }

    func testARefusedPermissionOutranksTheSwitchBeingOn() {
        XCTAssertEqual(galleryCaption(saveToGallery: true, galleryBlocked: true), .blocked)
    }

    func testASwitchThatIsOffOutranksABlock() {
        // Unreachable today: galleryBlocked is computed as `save && refused`.
        // Pinned because it is the row that decides the ordering inside
        // galleryCaption.
        XCTAssertEqual(galleryCaption(saveToGallery: false, galleryBlocked: true), .notSaving)
    }
}
