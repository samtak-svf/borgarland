import Foundation

/// Model for the subset of data/reykjavik-form.json this package reads. The
/// file is the source of truth (decision 0001): the category list, the
/// per-category kind and the description limit come from the facts file,
/// never from a second copy. The city's own key names are mirrored here as
/// property names, exactly as the Kotlin reference does; the wire never
/// carries them, and the body tests pin that.
public struct FactsFile: Decodable, Equatable {
    public let fields: Fields
    public let categories: [Category]
    public let map: MapInfo
}

public struct Fields: Decodable, Equatable {
    public let description: Description
}

public struct Description: Decodable, Equatable {
    public let maxLength: Int
}

public struct Category: Decodable, Equatable {
    public let slug: String
    /// The city's general/specific kind; a picker label only, never sent.
    public let type: String
    /// The city's display name; a picker label only, never sent.
    public let category: String
}

public struct MapInfo: Decodable, Equatable {
    public let bounds: Bounds
}

public struct Bounds: Decodable, Equatable {
    public let south: Double
    public let west: Double
    public let north: Double
    public let east: Double
}

public enum Facts {
    public static func parse(_ data: Data) throws -> FactsFile {
        try JSONDecoder().decode(FactsFile.self, from: data)
    }
}
