import XCTest
import ImageIO
import CoreGraphics
import BorgarlandCore

/// Exercises the ImageIO-backed GPS reader against JPEGs built in-memory in
/// both hemisphere references, plus the malformed-input cases that must read
/// as "no coordinate". The Kotlin reference hand-builds JPEG segments to test
/// its own TIFF walker; this reader delegates the segment walk to ImageIO, so
/// the fixtures test the sign handling and the nil contract instead.
final class ExifGpsTest: XCTestCase {

    func testReadsNorthEast() throws {
        // EXIF stores GPS as an UNSIGNED magnitude plus a hemisphere
        // reference, and ImageIO enforces that on write: handed a negative
        // magnitude it writes 0, which is how this fixture first failed. So
        // the fixture carries the magnitude the way a camera would and the
        // reader is what applies the sign — which is the behaviour worth
        // testing anyway.
        let data = try XCTUnwrap(
            jpegWithGps(latitude: 64.14658919, latitudeRef: "N", longitude: 21.93279823, longitudeRef: "W")
        )
        let coordinate = try XCTUnwrap(ExifGps.read(from: data))
        XCTAssertEqual(coordinate.latitude, 64.14658919, accuracy: 0.000_01)
        XCTAssertEqual(coordinate.longitude, -21.93279823, accuracy: 0.000_01)
    }

    func testReadsSouthWest() throws {
        // Signed values with the matching reference: the hemisphere sign must
        // land on the wire coordinate.
        let data = try XCTUnwrap(
            jpegWithGps(latitude: 63.5, latitudeRef: "S", longitude: 150.25, longitudeRef: "E")
        )
        let coordinate = try XCTUnwrap(ExifGps.read(from: data))
        XCTAssertEqual(coordinate.latitude, -63.5, accuracy: 0.000_01)
        XCTAssertEqual(coordinate.longitude, 150.25, accuracy: 0.000_01)
    }

    func testJpegWithoutGpsIsNoCoordinate() throws {
        let data = try XCTUnwrap(jpegWithoutGps())
        XCTAssertNil(ExifGps.read(from: data))
    }

    func testNotAnImageIsNoCoordinate() {
        XCTAssertNil(ExifGps.read(from: Data("not an image".utf8)))
    }

    func testEmptyDataIsNoCoordinate() {
        XCTAssertNil(ExifGps.read(from: Data()))
    }

    // MARK: - fixtures

    private func jpegWithGps(
        latitude: Double,
        latitudeRef: String,
        longitude: Double,
        longitudeRef: String
    ) -> Data? {
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: latitude,
            kCGImagePropertyGPSLatitudeRef: latitudeRef,
            kCGImagePropertyGPSLongitude: longitude,
            kCGImagePropertyGPSLongitudeRef: longitudeRef,
        ]
        return jpeg(properties: [kCGImagePropertyGPSDictionary: gps])
    }

    private func jpegWithoutGps() -> Data? {
        jpeg(properties: nil)
    }

    private func jpeg(properties: [CFString: Any]?) -> Data? {
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
