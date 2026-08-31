import Foundation
import Photos

/// Writes a captured photograph into the Photos library, into a named album,
/// so a person keeps the picture they took after the report is filed (#179).
/// The bytes are the app's own JPEG, unaltered — no re-encode, and no EXIF
/// GPS written (decision 0018).
///
/// The permission is the ADD-ONLY grant, not full library access: saving is
/// a materially lighter ask than reading, iOS presents it differently, and
/// the project.yml declares `NSPhotoLibraryAddUsageDescription` — the read
/// permission that was already declared exists ahead of a feature that was
/// never built (`gallery-pick`) and is not enough to save.
///
/// A failure to save is never a failure of the report. The capture already
/// happened and the bytes are in the report; the gallery copy is a courtesy.
/// So every failure path here is silent, and the caller never treats a false
/// as anything but the copy not existing.
enum PhotoLibrarySaver {

    /// The album name, both here and in the Android save path (#179).
    static let albumName = "Borgarland"
    /// Whether the add-only permission has been refused for good — the state
    /// only the system Settings app can change. Distinguishes refused from
    /// not-yet-asked, the #76 distinction applied to #179: a toggle in front
    /// of a permission that can never say yes must say so.
    static var isDeniedForGood: Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .denied, .restricted: return true
        default: return false
        }
    }

    /// Save, asking for the add-only permission if this is the first time.
    /// Runs on its own task so the capture path is never blocked by the
    /// permission dialog or the library write.
    static func save(data: Data) async {
        guard !data.isEmpty else { return }
        let authorized: Bool
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
        case .denied, .restricted, .limited:
            authorized = false
        @unknown default:
            authorized = false
        }
        guard authorized else { return }

        // The album read happens before the change block; the canonical
        // pattern keeps the fetch and the mutation in separate phases.
        let album = findAlbum(albumName)
        try? await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
            guard let assetPlaceholder = request.placeholderForCreatedAsset else { return }
            if let album {
                PHAssetCollectionChangeRequest(for: album)?
                    .addAssets([assetPlaceholder] as NSArray)
            } else {
                // First save: create the album and add the photo to it in the
                // same transaction, so the placeholder resolves. The creation
                // request IS a change request — a newly created album has no
                // PHAssetCollection until the block commits, so there is
                // nothing to look up; the request itself carries the add.
                let albumChange = PHAssetCollectionChangeRequest
                    .creationRequestForAssetCollection(withTitle: albumName)
                albumChange.addAssets([assetPlaceholder] as NSArray)
            }
        }
    }

    private static func findAlbum(_ name: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", name)
        return PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: options
        ).firstObject
    }
}
