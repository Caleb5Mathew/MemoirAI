import SwiftUI

enum AdaptiveLayoutPolicy {
    static let formMaxWidth: CGFloat = 620
    static let readableMaxWidth: CGFloat = 760
    static let workflowMaxWidth: CGFloat = 680
    static let bannerMaxWidth: CGFloat = 620
    static let galleryMaxWidth: CGFloat = 1_200

    static func usesCompactVerticalChrome(
        width: CGFloat,
        height: CGFloat,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        verticalSizeClass == .compact || height < 500 || width > height * 1.35
    }

    static func validatedAspectRatio(
        width: Double,
        height: Double,
        fallback: CGFloat
    ) -> CGFloat {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            return fallback
        }
        return CGFloat(width / height)
    }

    static func aspectFitSize(aspectRatio: CGFloat, inside bounds: CGSize) -> CGSize {
        guard aspectRatio.isFinite, aspectRatio > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let boundsAspect = bounds.width / bounds.height
        if aspectRatio > boundsAspect {
            return CGSize(width: bounds.width, height: bounds.width / aspectRatio)
        }
        return CGSize(width: bounds.height * aspectRatio, height: bounds.height)
    }
}

private struct AdaptiveContentWidthModifier: ViewModifier {
    let maxWidth: CGFloat
    let alignment: Alignment

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth, alignment: alignment)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct AdaptiveSheetDetentsModifier: ViewModifier {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let preferredHeight: CGFloat

    func body(content: Content) -> some View {
        if verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize {
            content.presentationDetents([.large])
        } else {
            content.presentationDetents([.height(preferredHeight), .medium, .large])
        }
    }
}

extension View {
    func adaptiveContentWidth(
        _ maxWidth: CGFloat = AdaptiveLayoutPolicy.readableMaxWidth,
        alignment: Alignment = .center
    ) -> some View {
        modifier(AdaptiveContentWidthModifier(maxWidth: maxWidth, alignment: alignment))
    }

    func adaptiveSheetDetents(preferredHeight: CGFloat) -> some View {
        modifier(AdaptiveSheetDetentsModifier(preferredHeight: preferredHeight))
    }
}
