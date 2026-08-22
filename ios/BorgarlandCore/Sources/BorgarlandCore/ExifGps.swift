import Foundation
import ImageIO
import CoreGraphics

public struct GpsCoordinate: Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A coordinate out of a photo's EXIF GPS block, and nothing else out of
/// EXIF. This is the gallery path reader: a photo the app captured itself
/// asks the device for a fix instead, because the capture path writes no GPS
/// into the JPEG unless asked (AGENTS.md,
/// docs/research/photos-exif-and-formats.md). Any malformed or absent input
/// reads as no coordinate, never as a crash. The caller applies the
/// coordinate guard.
public enum ExifGps {
    public static func read(from data: Data) -> GpsCoordinate? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            let latitude = decimalDegrees(gps[kCGImagePropertyGPSLatitude]),
            let longitude = decimalDegrees(gps[kCGImagePropertyGPSLongitude])
        else { return nil }

        // The hemisphere reference is applied defensively. Some encoders sign
        // the decimal value, some leave it unsigned and rely on the
        // reference; normalising through abs() makes both readings land on
        // the same sign for the same reference. No reference at all means the
        // value arrived signed and is trusted as-is.
        var latitude = latitude
        var longitude = longitude
        if let ref = gps[kCGImagePropertyGPSLatitudeRef] as? String {
            latitude = ref == "S" ? -abs(latitude) : abs(latitude)
        }
        if let ref = gps[kCGImagePropertyGPSLongitudeRef] as? String {
            longitude = ref == "W" ? -abs(longitude) : abs(longitude)
        }

        return GpsCoordinate(latitude: latitude, longitude: longitude)
    }

    /// ImageIO returns the coordinate either as signed decimal degrees or, in
    /// the legacy encoding, as a degrees/minutes/seconds triple. Both are
    /// accepted; anything else reads as no coordinate.
    private static func decimalDegrees(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let parts = value as? [Any], parts.count == 3 {
            let dms = parts.compactMap { ($0 as? NSNumber)?.doubleValue }
            guard dms.count == 3 else { return nil }
            return dms[0] + dms[1] / 60.0 + dms[2] / 3600.0
        }
        return nil
    }
}
