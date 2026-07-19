import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Memoized QR code renderer. QR generation runs CoreImage synchronously, so pages
/// that render a QR in `body` would otherwise re-rasterize (and re-create a CIContext)
/// on every SwiftUI render pass.
enum QRCodeCache {
    private static let context = CIContext()
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 64
        return c
    }()

    static func image(for text: String, size: CGFloat) -> UIImage {
        let key = "\(text)|\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let rendered = render(text: text, size: size)
        cache.setObject(rendered, forKey: key)
        return rendered
    }

    private static func render(text: String, size: CGFloat) -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        guard let messageData = text.data(using: .utf8) else { return UIImage() }
        filter.message = messageData
        guard let ci = filter.outputImage else { return UIImage() }
        let scaleX = size / ci.extent.size.width
        let scaleY = size / ci.extent.size.height
        let scaled = ci.transformed(by: .init(scaleX: scaleX, y: scaleY))
        if let cg = context.createCGImage(scaled, from: scaled.extent) {
            return UIImage(cgImage: cg)
        }
        return UIImage()
    }
}
