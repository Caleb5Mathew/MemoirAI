import XCTest
import UIKit
@testable import MemoirAI

@MainActor
final class OnboardingPhotoPreparationTests: XCTestCase {
    private func source(size: CGSize, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        }
    }

    func testBoundsPhysicalPixelsRegardlessOfSourceScale() throws {
        let original = source(size: CGSize(width: 600, height: 900), scale: 2)
        let data = try XCTUnwrap(OnboardingPhotoPreparation.jpeg(from: original))
        let decoded = try XCTUnwrap(UIImage(data: data))
        let pixels = try XCTUnwrap(decoded.cgImage)
        XCTAssertEqual(pixels.width, 512)
        XCTAssertEqual(pixels.height, 768)
        XCTAssertEqual(original.size.height, 900)
    }

    func testSmallImageIsNotUpscaled() throws {
        let image = source(size: CGSize(width: 120, height: 180))
        let data = try XCTUnwrap(OnboardingPhotoPreparation.jpeg(from: image))
        let pixels = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(pixels.width, 120)
        XCTAssertEqual(pixels.height, 180)
    }

    func testOrientationIsBakedIntoUprightJPEG() throws {
        let original = source(size: CGSize(width: 120, height: 180))
        let pixels = try XCTUnwrap(original.cgImage)
        let rotated = UIImage(cgImage: pixels, scale: 1, orientation: .right)
        let data = try XCTUnwrap(OnboardingPhotoPreparation.jpeg(from: rotated))
        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(decoded.imageOrientation, .up)
        XCTAssertEqual(decoded.size.width, rotated.size.width)
        XCTAssertEqual(decoded.size.height, rotated.size.height)
        // Compare to UIKit's orientation-aware drawing, not the unrotated CGImage.
        let expected = UIGraphicsImageRenderer(size: rotated.size).image { _ in
            rotated.draw(in: CGRect(origin: .zero, size: rotated.size))
        }
        XCTAssertEqual(decoded.size.width / decoded.size.height, expected.size.width / expected.size.height, accuracy: 0.01)
        let actualColors = try sampledPixels(decoded)
        let expectedColors = try sampledPixels(expected)
        for (actual, expected) in zip(actualColors, expectedColors) {
            XCTAssertLessThanOrEqual(abs(Int(actual) - Int(expected)), 20)
        }
    }
    private func sampledPixels(_ image: UIImage) throws -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let cg = try XCTUnwrap(small.cgImage)
        var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 8, height: 8,
                bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return bytes
    }

}
