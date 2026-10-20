import UIKit

enum OnboardingPhotoPreparation {
    static let maximumDimension: CGFloat = 768

    /// Bakes camera orientation into the pixels before sending the identity reference.
    static func jpeg(from image: UIImage) -> Data? {
        let longestEdge = max(image.size.width, image.size.height) * image.scale
        guard longestEdge.isFinite, longestEdge > 0 else { return nil }
        let ratio = min(1, maximumDimension / longestEdge)
        let size = CGSize(width: max(1, floor(image.size.width * image.scale * ratio)),
                          height: max(1, floor(image.size.height * image.scale * ratio)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return normalized.jpegData(compressionQuality: 0.82)
    }
}
