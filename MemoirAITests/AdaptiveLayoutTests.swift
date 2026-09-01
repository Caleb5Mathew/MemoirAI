import Testing
import CoreGraphics
@testable import MemoirAI

struct AdaptiveLayoutTests {
    @Test func compactVerticalChromeHandlesLandscapeAndShortWindows() {
        #expect(AdaptiveLayoutPolicy.usesCompactVerticalChrome(
            width: 844,
            height: 390,
            verticalSizeClass: .compact
        ))
        #expect(AdaptiveLayoutPolicy.usesCompactVerticalChrome(
            width: 700,
            height: 480,
            verticalSizeClass: .regular
        ))
        #expect(!AdaptiveLayoutPolicy.usesCompactVerticalChrome(
            width: 390,
            height: 844,
            verticalSizeClass: .regular
        ))
    }

    @Test func coverAspectRatioRejectsInvalidCloudDimensions() {
        let fallback: CGFloat = 8.5 / 11
        #expect(AdaptiveLayoutPolicy.validatedAspectRatio(width: 8.5, height: 11, fallback: fallback) == fallback)
        #expect(AdaptiveLayoutPolicy.validatedAspectRatio(width: 11, height: 0, fallback: fallback) == fallback)
    }

    @Test func aspectFitSizePreservesPortraitAndLandscapeCovers() {
        let portrait = AdaptiveLayoutPolicy.aspectFitSize(aspectRatio: 8.5 / 11, inside: CGSize(width: 80, height: 64))
        #expect(portrait.width < portrait.height)
        #expect(portrait.height == 64)

        let landscape = AdaptiveLayoutPolicy.aspectFitSize(aspectRatio: 11 / 8.5, inside: CGSize(width: 80, height: 64))
        #expect(landscape.width > landscape.height)
        #expect(landscape.width == 80)
    }
}
