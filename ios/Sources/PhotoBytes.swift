import SwiftUI
import UIKit
import BorgarlandCore

/// The two conversions the screens need from captured JPEG bytes, in one
/// place: the wire Photo and the on-screen Image. The fallible decoding
/// lives here rather than repeated in CameraScreen and SummaryScreen.
enum PhotoBytes {
    /// The captured JPEG as the wire Photo. The iPhone shoots HEIC by
    /// default and the city accepts only image/jpeg, image/png and
    /// image/gif, so the capture path asks AVCapturePhotoSettings for JPEG
    /// explicitly (AGENTS.md, docs/research/photos-exif-and-formats.md) and
    /// no transcoding happens here. rotationDegrees is 0 because AVFoundation
    /// bakes the orientation into the JPEG's EXIF and UIImage applies it;
    /// the Kotlin needs a separate rotation value because CameraX does not.
    static func photo(from jpeg: Data, rotationDegrees: Int = 0) -> Photo {
        Photo(bytes: jpeg, name: "mynd.jpg", mime: "image/jpeg", rotationDegrees: rotationDegrees)
    }

    /// Decode for display. Returns nil on undecodable data instead of
    /// crashing; the screens fall back to showing nothing, the same way the
    /// Kotlin renders a 1x1 placeholder.
    static func image(from data: Data) -> Image? {
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }
}
