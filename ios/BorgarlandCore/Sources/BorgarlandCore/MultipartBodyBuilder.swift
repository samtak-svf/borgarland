import Foundation

public enum RelayContractError: Error, Equatable {
    /// A role the contract marks required and the app has no value for. This
    /// must fail before a byte of the body exists: sending a request the
    /// relay would reject is exactly how the app and the relay drift apart.
    case requiredFieldMissing(wireName: String)
}

extension RelayContractError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .requiredFieldMissing(let wireName):
            return "relay contract field '\(wireName)' is required but the app has nothing to send"
        }
    }
}

/// Builds the exact multipart body the app posts, from the contract. Parts
/// are written under the contract's field names in the contract's order, byte
/// for byte the way the Kotlin reference builds them: same CRLF placement,
/// same Content-Disposition and Content-Type lines, photo bytes raw, a
/// trailing closing boundary. A required field the app has no value for
/// fails loudly instead of sending a request the relay would reject, and a
/// part the contract does not name is never written.
public enum MultipartBodyBuilder {
    public static func buildBody(payload: Payload, contract: RelayRequestFile, boundary: String) throws -> Data {
        var out = Data()

        func append(_ string: String) {
            out.append(contentsOf: string.utf8)
        }

        func writeTextPart(name: String, value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append(value)
            append("\r\n")
        }

        func writePhotoPart(name: String, photo: Photo) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(photo.name)\"\r\n")
            append("Content-Type: \(photo.mime)\r\n\r\n")
            out.append(photo.bytes)
            append("\r\n")
        }

        // The contract's roles, in the contract's order. The literal in
        // the binding is which role a contract field plays; the wire name
        // written is the contract's own key.
        for (name, spec) in contract.fieldsInContractOrder {
            if name == "photo" {
                for photo in payload.photos { writePhotoPart(name: name, photo: photo) }
                continue
            }
            let value = value(for: name, payload: payload)
            if spec.required && value == nil {
                throw RelayContractError.requiredFieldMissing(wireName: name)
            }
            if let value { writeTextPart(name: name, value: value) }
        }
        append("--\(boundary)--\r\n")
        return out
    }

    /// Which role a contract field plays. Optional roles the app never fills
    /// are written only when the contract names them and a value exists; the
    /// photo role is written as parts below, never as text, and the
    /// required-check never applies to it — exactly as in the Kotlin
    /// reference.
    private static func value(for name: String, payload: Payload) -> String? {
        switch name {
        case "reportId": return payload.reportId
        case "category": return payload.categorySlug
        case "latitude": return payload.latitudeText
        case "longitude": return payload.longitudeText
        case "description": return payload.description
        // Where the city sends its confirmation (#163). Required by the
        // contract, so a nil here is refused by the loop above rather than
        // quietly dropping the one channel the reporter has back.
        case "email": return payload.email
        case "photo": return nil // handled as parts above
        default: return nil // a role we do not know cannot be filled
        }
    }
}
