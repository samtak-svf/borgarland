import XCTest
import BorgarlandCore

/// The app builds its request from data/relay-request.json, and this test
/// pins the two together. It proves the body MultipartBodyBuilder builds
/// carries exactly the contract's parts, in the contract's order, with our
/// vocabulary and nothing else: the city's field names, display names and
/// summary strings never reach the wire (AGENTS.md puts them in the relay's
/// adapter alone).
final class RelayRequestTest: XCTestCase {

    func testAssetParsesToTheDocumentedContract() throws {
        let contract = try RelayRequest.parse(ContractSource.dataFile("relay-request.json"))

        // The six field keys, in the file's order — the order the parts are
        // written in. The check script asserts the same set on the relay
        // side. The fixed struct makes the order structural; this pins it to
        // the documented one so a reorder is a deliberate, reviewed change.
        XCTAssertEqual(
            contract.fieldsInContractOrder.map { $0.name },
            ["category", "latitude", "longitude", "description", "email", "photo"]
        )
        XCTAssertEqual(contract.endpoint.path, "/api/reports")
        XCTAssertEqual(contract.endpoint.method, "POST")
        XCTAssertEqual(contract.endpoint.contentType, "multipart/form-data")

        XCTAssertTrue(contract.category.required)
        XCTAssertTrue(contract.latitude.required)
        XCTAssertTrue(contract.longitude.required)
        XCTAssertTrue(contract.description.required)
        XCTAssertFalse(contract.email.required)
        XCTAssertFalse(contract.photo.required)
    }

    func testContractAgreesWithTheFactsFileWhereItClaimsTo() throws {
        let contract = try RelayRequest.parse(ContractSource.dataFile("relay-request.json"))
        let facts = try Facts.parse(ContractSource.dataFile("reykjavik-form.json"))

        // The description limit is the city's, stated by both files; the
        // Kotlin test also cross-checks the photo MIME list against the facts
        // file, which this port deliberately does not: that fact lives under
        // the city's own field name and decoding it would put the city's
        // vocabulary in the library. The relay contract carries its own copy
        // and the check script is the backstop for that pair.
        XCTAssertEqual(facts.fields.description.maxLength, contract.description.maxLength)
    }

    func testBuiltBodyWritesExactlyTheContractParts() throws {
        let contract = try RelayRequest.parse(ContractSource.dataFile("relay-request.json"))
        let payload = Payload(
            categorySlug: "ruslafotur",
            latitude: 64.14658919,
            longitude: -21.93279823,
            description: "Full ruslafata við stíginn",
            photos: [Photo(bytes: Data([1, 2, 3]), name: "mynd.jpg", mime: "image/jpeg", rotationDegrees: 0)]
        )

        let boundary = "----boundary"
        let body = try MultipartBodyBuilder.buildBody(payload: payload, contract: contract, boundary: boundary)

        // The exact bytes the Kotlin reference produces for the same input:
        // same CRLF placement, same header lines, closing boundary once.
        let expected = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"category\"\r\n\r\n"
            + "ruslafotur\r\n"
            + "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"latitude\"\r\n\r\n"
            + "64.14658919\r\n"
            + "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"longitude\"\r\n\r\n"
            + "-21.93279823\r\n"
            + "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"description\"\r\n\r\n"
            + "Full ruslafata við stíginn\r\n"
            + "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"photo\"; filename=\"mynd.jpg\"\r\n"
            + "Content-Type: image/jpeg\r\n\r\n"
            + "\u{01}\u{02}\u{03}\r\n"
            + "--\(boundary)--\r\n"
        XCTAssertEqual(String(decoding: body, as: UTF8.self), expected)

        // The city's vocabulary never reaches the wire: not as a part name,
        // not as a value.
        let bodyText = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(bodyText.contains("name=\"type\""))
        XCTAssertFalse(bodyText.contains("name=\"summary\""))
        XCTAssertFalse(bodyText.contains("name=\"lat\""))
        XCTAssertFalse(bodyText.contains("name=\"lng\""))
        XCTAssertFalse(bodyText.contains("name=\"files\""))
        XCTAssertFalse(bodyText.contains("Ruslafötur"))
        XCTAssertFalse(bodyText.contains("Ábending"))
    }

    func testOptionalAbsentFieldsAreOmitted() throws {
        let contract = try RelayRequest.parse(ContractSource.dataFile("relay-request.json"))
        let payload = Payload(
            categorySlug: "ruslafotur",
            latitude: 64.14658919,
            longitude: -21.93279823,
            description: "lýsing",
            photos: []
        )

        let body = try MultipartBodyBuilder.buildBody(payload: payload, contract: contract, boundary: "----b")

        // email is optional and the app never collects it; photo is optional
        // and this payload has none. Neither part may appear.
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(text.contains("name=\"email\""))
        XCTAssertFalse(text.contains("name=\"photo\""))
        XCTAssertTrue(text.contains("name=\"category\""))
    }

    func testRequiredRoleTheAppCannotFillFailsLoudly() throws {
        // A role the app has no binding for must not be silently omitted:
        // that is exactly how the app and the relay drift apart. The Kotlin
        // test injects a synthetic extra field into the contract map; this
        // model is structural, so the equivalent is a role the app can never
        // fill — email is never collected, and a contract that requires it
        // must fail before a byte of the body exists.
        let contract = try RelayRequest.parse(ContractSource.dataFile("relay-request.json"))
        let broken = RelayRequestFile(
            endpoint: contract.endpoint,
            category: contract.category,
            latitude: contract.latitude,
            longitude: contract.longitude,
            description: contract.description,
            email: FieldSpec(required: true, maxLength: nil, accept: nil),
            photo: contract.photo
        )
        let payload = Payload(
            categorySlug: "ruslafotur",
            latitude: 64.14658919,
            longitude: -21.93279823,
            description: "lýsing",
            photos: []
        )

        XCTAssertThrowsError(
            try MultipartBodyBuilder.buildBody(payload: payload, contract: broken, boundary: "----boundary")
        ) { error in
            XCTAssertEqual(error as? RelayContractError, .requiredFieldMissing(wireName: "email"))
        }
    }
}
