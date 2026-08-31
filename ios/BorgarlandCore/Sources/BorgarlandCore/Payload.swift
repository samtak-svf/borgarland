import Foundation

/// What would be posted, field for field, to OUR relay. The city's type and
/// display names are derived by the relay's adapter from the slug; this
/// package never sees or sends them (AGENTS.md: the adapter is the only place
/// allowed to know the city's vocabulary). The wire names of the parts are
/// the contract's field keys (data/relay-request.json), applied in
/// MultipartBodyBuilder.
public struct Photo {
    public let bytes: Data
    public let name: String
    public let mime: String
    public let rotationDegrees: Int

    public init(bytes: Data, name: String, mime: String, rotationDegrees: Int) {
        self.bytes = bytes
        self.name = name
        self.mime = mime
        self.rotationDegrees = rotationDegrees
    }

    public var sizeBytes: Int { bytes.count }
}

public struct Payload {
    /// Which report this IS, so sending it twice cannot file it twice (#88).
    /// The relay stores it as the row's own id and answers a repeat with the
    /// row it already has. Optional because the relay generates one when the
    /// app sends none, which is what an older build does.
    public let reportId: String?
    /// Which launch of the app filed this report (#186) — the same per-launch
    /// session id the telemetry envelope carries, so the relay can join the
    /// report row to the events of the walk that produced it. Optional
    /// because the contract says so: a build that predates the field sends
    /// none.
    public let session: String?
    /// Category slug, one of the twelve in the facts file.
    public let categorySlug: String
    public let latitude: Double
    public let longitude: Double
    public let description: String
    public let photos: [Photo]
    /// Where the city sends its confirmation, and the only channel it has back
    /// to the person who filed this (#163). Held on the device rather than
    /// asked for each time (`ContactDetails`), and required by us though the
    /// city treats it as optional — the same override the coordinate gets.
    ///
    /// Optional because the type has to be able to express a report without
    /// one; the contract's `required` flag is what refuses to send it, in
    /// `MultipartBodyBuilder`, so there is exactly one gate rather than two
    /// that can disagree.
    public let email: String?

    public init(
        categorySlug: String,
        latitude: Double,
        longitude: Double,
        description: String,
        photos: [Photo],
        email: String? = nil,
        reportId: String? = nil,
        session: String? = nil
    ) {
        self.reportId = reportId
        self.session = session
        self.categorySlug = categorySlug
        self.latitude = latitude
        self.longitude = longitude
        self.description = description
        self.photos = photos
        self.email = email
    }

    /// Formatted the way the relay script formats them: shortest round-trip
    /// decimal with a dot separator. Not fixed-point — a fixed width would
    /// pad and round differently than the Kotlin's toString().
    public var latitudeText: String { String(latitude) }
    public var longitudeText: String { String(longitude) }
}
