import Foundation

/// Model for data/relay-request.json, the one file that names the multipart
/// parts the app may send to our relay. The wire names ARE the keys of that
/// file; the body builder writes parts under exactly those names, in the
/// file's order, and nothing else (decision 0002, AGENTS.md).
///
/// The fields are a fixed struct rather than a decoded dictionary on purpose:
/// Swift's Dictionary is unordered, and the order of the parts on the wire is
/// load-bearing — both the relay's Worker and the contract check pin it. Making
/// the order structural means it cannot drift the way a decoded map's order
/// can. JSONDecoder ignores keys this struct does not name, so a contract that
/// grows a part is a deliberate, reviewed change here rather than a silently
/// reordered request.
///
/// It grew one: `reportId` (#88), first in the order, so a report carries its
/// own identity ahead of everything that describes it.
public struct RelayRequestFile: Decodable, Equatable {
    public let endpoint: Endpoint
    public let reportId: FieldSpec
    public let session: FieldSpec
    public let category: FieldSpec
    public let latitude: FieldSpec
    public let longitude: FieldSpec
    public let description: FieldSpec
    public let email: FieldSpec
    public let photo: FieldSpec

    public init(
        endpoint: Endpoint,
        session: FieldSpec,
        category: FieldSpec,
        latitude: FieldSpec,
        longitude: FieldSpec,
        description: FieldSpec,
        email: FieldSpec,
        photo: FieldSpec,
        reportId: FieldSpec
    ) {
        self.endpoint = endpoint
        self.reportId = reportId
        self.session = session
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.description = description
        self.email = email
        self.photo = photo
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint, fields
    }

    /// The wire names, and the only place they are spelled in Swift. They sit
    /// under `fields` in the file, so the decoder is explicit rather than
    /// synthesized: a synthesized one would look for them at the top level and
    /// fail on the canonical contract.
    private enum FieldKeys: String, CodingKey {
        case reportId, session, category, latitude, longitude, description, email, photo
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try root.decode(Endpoint.self, forKey: .endpoint)
        let fields = try root.nestedContainer(keyedBy: FieldKeys.self, forKey: .fields)
        reportId = try fields.decode(FieldSpec.self, forKey: .reportId)
        session = try fields.decode(FieldSpec.self, forKey: .session)
        category = try fields.decode(FieldSpec.self, forKey: .category)
        latitude = try fields.decode(FieldSpec.self, forKey: .latitude)
        longitude = try fields.decode(FieldSpec.self, forKey: .longitude)
        description = try fields.decode(FieldSpec.self, forKey: .description)
        email = try fields.decode(FieldSpec.self, forKey: .email)
        photo = try fields.decode(FieldSpec.self, forKey: .photo)
    }

    /// The roles in the contract's order — the order the parts are written in.
    public var fieldsInContractOrder: [(name: String, spec: FieldSpec)] {
        [
            ("reportId", reportId),
            ("session", session),
            ("category", category),
            ("latitude", latitude),
            ("longitude", longitude),
            ("description", description),
            ("email", email),
            ("photo", photo),
        ]
    }
}

public struct Endpoint: Decodable, Equatable {
    public let path: String
    public let method: String
    public let contentType: String

    public init(path: String, method: String, contentType: String) {
        self.path = path
        self.method = method
        self.contentType = contentType
    }
}

public struct FieldSpec: Decodable, Equatable {
    public let required: Bool
    public let maxLength: Int?
    public let accept: [String]?

    public init(required: Bool, maxLength: Int? = nil, accept: [String]? = nil) {
        self.required = required
        self.maxLength = maxLength
        self.accept = accept
    }
}

public enum RelayRequest {
    /// Decodes the contract with the standard lenient rules: unknown keys are
    /// ignored, a missing non-optional property fails loudly.
    public static func parse(_ data: Data) throws -> RelayRequestFile {
        try JSONDecoder().decode(RelayRequestFile.self, from: data)
    }
}
