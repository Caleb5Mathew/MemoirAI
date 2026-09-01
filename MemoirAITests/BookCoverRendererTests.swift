import CoreGraphics
import Testing
@testable import MemoirAI

struct BookCoverRendererTests {
    @Test func hardcoverSpineWidthsMatchLuluBoundaries() {
        let expected: [(Int, CGFloat)] = [
            (24, 0.25), (84, 0.25), (85, 0.5), (140, 0.5),
            (141, 0.625), (168, 0.625), (169, 0.6875),
            (194, 0.6875), (195, 0.75), (222, 0.75),
            (223, 0.8125), (778, 2.0), (779, 2.0625), (800, 2.125)
        ]

        for (pageCount, width) in expected {
            #expect(spineWidthInches(forPageCount: pageCount) == width)
        }
    }

    @Test func casewrapDimensionsUseTheLuluSpineWidth() {
        let spine = spineWidthInches(forPageCount: 85)

        #expect(LuluCoverTemplate.totalWidthInches(spineWidth: spine) == 24.25)
        #expect(LuluCoverTemplate.totalHeightInches == 10.25)
        #expect(PortraitLuluCoverTemplate.totalWidthInches(spineWidth: spine) == 19.25)
        #expect(PortraitLuluCoverTemplate.totalHeightInches == 12.75)
    }

    @Test func flatPanelRectsAreContiguousAndFillTheCover() {
        let rects = BookCoverRenderer.flatPanelRects(for: .kidsBook(pageCount: 85))

        #expect(rects.back.minX == 0)
        #expect(abs(rects.back.maxX - rects.spine.minX) < 0.000_001)
        #expect(abs(rects.spine.maxX - rects.front.minX) < 0.000_001)
        #expect(abs(rects.front.maxX - 1) < 0.000_001)
    }

    @Test func aspectFillPreservesRatioAndCoversTarget() {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 500)
        let result = BookCoverRenderer.aspectFillRect(
            imageSize: CGSize(width: 1_250, height: 1_000),
            in: bounds
        )

        #expect(abs(result.width / result.height - 1.25) < 0.000_001)
        #expect(result.width >= bounds.width)
        #expect(result.height >= bounds.height)
        #expect(abs(result.midX - bounds.midX) < 0.000_001)
        #expect(abs(result.midY - bounds.midY) < 0.000_001)
    }
}
