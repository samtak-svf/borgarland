import Foundation

/// The one rule this project enforces that the city does not. The city
/// accepts a report with no coordinate and nobody could act on it, so this
/// package refuses to build one without a usable pair. Rejects anything
/// non-finite and anything outside WGS84 decimal degrees, mirroring the relay
/// script. A non-finite value can reach the guard via EXIF rationals with a
/// zero denominator, so it is rejected rather than assumed impossible.
public enum Coordinates {
    public static func isUsable(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite
            && (-90.0...90.0).contains(latitude)
            && (-180.0...180.0).contains(longitude)
    }

    /// The single gate for coordinate text — a form field, a pasted value.
    /// Swift's Double parser accepts only a dot separator, so empty input and
    /// comma decimals read as nil and never reach the wire mis-formatted.
    /// The value is then formatted for the wire with String(_:), which is
    /// locale-free.
    public static func decimal(from text: String) -> Double? {
        Double(text)
    }
}
