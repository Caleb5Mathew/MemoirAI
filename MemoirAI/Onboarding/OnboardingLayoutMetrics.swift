import CoreGraphics

/// Use the available safe-area viewport, before subtracting the onboarding header.
/// Font values are base sizes; SwiftUI still applies the user's Dynamic Type scale.
struct OnboardingLayoutMetrics: Equatable {
    var contentWidth: CGFloat { setupWidth }
    var bookContentWidth: CGFloat { tourWidth }
    var headingSize: CGFloat { recordHeadingSize }
    var editorHeight: CGFloat { textEditorHeight }
    let compactLandscape: Bool
    let setupWidth: CGFloat
    let tourWidth: CGFloat
    let pageWidth: CGFloat
    let horizontalPadding: CGFloat
    let recordHeadingSize: CGFloat
    let revealHeadingSize: CGFloat
    let tourHeadingSize: CGFloat
    let bookStageHeight: CGFloat
    let photoHeight: CGFloat
    let textEditorHeight: CGFloat
    let minimumHitTarget: CGFloat = 44
    let primaryButtonHeight: CGFloat = 56
    let compactHeight: Bool

    init(size: CGSize, accessibility: Bool = false) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        compactLandscape = width > height
        compactHeight = height < 740
        horizontalPadding = width < 390 ? 20 : 25
        setupWidth = min(width, 520)
        tourWidth = min(width, 720)
        pageWidth = max(0, min(640, tourWidth - 2 * horizontalPadding))
        recordHeadingSize = width < 390 ? 28 : 30
        revealHeadingSize = width < 390 ? 26 : 28
        tourHeadingSize = compactHeight ? 28 : 30

        // Reserve the header, caption/player and fixed CTA. Short/keyboard layouts
        // must keep scrollable content; reducing type is not a substitute for it.
        let maximumStage: CGFloat = width >= 700 ? 360 : 310
        let reservedHeight: CGFloat = accessibility ? 460 : 390
        let preferredStage = min(maximumStage, height * 0.40, height - reservedHeight)
        bookStageHeight = max(120, preferredStage)
        photoHeight = min(300, max(220, height * 0.36))
        textEditorHeight = compactHeight ? 132 : 160
    }
}
