//
//  BookCoverRenderer.swift
//  MemoirAI
//
//  Renders a print-ready flat cover for the Kids Book at printer template dimensions.
//  Template: 24" x 10.25" (7200 x 3075 px at 300 DPI)
//  Layout: back cover (11.25") | spine (0.25") | front cover (11.25") with 0.625" wrap on edges.
//
//  LuluCoverTemplate: Lulu casewrap specs (0.75" wrap, 0.125" bleed, spine varies by page count).
//

import UIKit

// MARK: - Cover typography (maps `CoverFontPreset` → iOS fonts)

extension CoverFontPreset {
    func titleFont(size: CGFloat) -> UIFont {
        switch self {
        case .kidsSerif:
            return UIFont(name: "TimesNewRomanPS-BoldMT", size: size) ?? .systemFont(ofSize: size, weight: .bold)
        case .realisticSerif:
            return UIFont(name: "Georgia-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
        case .comicBold:
            return .systemFont(ofSize: size, weight: .heavy)
        case .customClean:
            return .systemFont(ofSize: size, weight: .semibold)
        }
    }

    func bodyFont(size: CGFloat) -> UIFont {
        switch self {
        case .kidsSerif:
            return UIFont(name: "TimesNewRomanPSMT", size: size) ?? .systemFont(ofSize: size, weight: .regular)
        case .realisticSerif:
            return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size, weight: .regular)
        case .comicBold:
            return .systemFont(ofSize: size, weight: .semibold)
        case .customClean:
            return .systemFont(ofSize: size, weight: .regular)
        }
    }
}

/// Lulu spine width (inches) by page count. Approximates Lulu's casewrap spine table.
func spineWidthInches(forPageCount count: Int) -> CGFloat {
    switch count {
    case 0..<24: return 0.25
    case 24..<84: return 0.25
    case 84..<100: return 0.28
    case 100..<116: return 0.32
    case 116..<132: return 0.36
    case 132..<148: return 0.40
    case 148..<164: return 0.45
    case 164..<180: return 0.49
    case 180..<196: return 0.53
    case 196..<212: return 0.57
    case 212..<228: return 0.61
    case 228..<244: return 0.65
    default: return min(2.125, 0.25 + CGFloat(count - 24) * 0.004)
    }
}

/// Printer template dimensions for Kids Book cover (from 65wp7rd-cover-template.pdf)
enum BookCoverTemplate {
    static let dpi: CGFloat = 300
    static let totalWidthInches: CGFloat = 24
    static let totalHeightInches: CGFloat = 10.25
    static let backCoverWidthInches: CGFloat = 11.25
    static let spineWidthInches: CGFloat = 0.25
    static let frontCoverWidthInches: CGFloat = 11.25
    static let wrapInches: CGFloat = 0.625
    static let trimHeightInches: CGFloat = 9

    static var totalWidthPx: Int { Int(totalWidthInches * dpi) }
    static var totalHeightPx: Int { Int(totalHeightInches * dpi) }
    static var wrapPx: Int { Int(wrapInches * dpi) }
    static var backCoverWidthPx: Int { Int(backCoverWidthInches * dpi) }
    static var spineWidthPx: Int { Int(spineWidthInches * dpi) }
    static var frontCoverWidthPx: Int { Int(frontCoverWidthInches * dpi) }
}

/// Lulu casewrap template for portrait 8.5x11" books.
struct PortraitLuluCoverTemplate {
    static let dpi: CGFloat = 300
    static let wrapInches: CGFloat = 0.75
    static let bleedInches: CGFloat = 0.125
    static let trimWidthInches: CGFloat = 8.5
    static let trimHeightInches: CGFloat = 11

    static let faceWidthInches: CGFloat = trimWidthInches + bleedInches
    static let faceHeightInches: CGFloat = trimHeightInches + bleedInches * 2
    static let totalHeightInches: CGFloat = faceHeightInches + wrapInches * 2

    static func totalWidthInches(spineWidth: CGFloat) -> CGFloat {
        wrapInches + faceWidthInches + spineWidth + faceWidthInches + wrapInches
    }

    static func totalWidthPx(spineWidth: CGFloat) -> Int {
        Int(totalWidthInches(spineWidth: spineWidth) * dpi)
    }

    static var totalHeightPx: Int { Int(totalHeightInches * dpi) }
    static var wrapPx: Int { Int(wrapInches * dpi) }
    static var faceWidthPx: Int { Int(faceWidthInches * dpi) }
    static var faceHeightPx: Int { Int(faceHeightInches * dpi) }
}

/// Lulu casewrap template: 0.75" wrap, 0.125" bleed, trim 11x8.5 (landscape).
struct LuluCoverTemplate {
    static let dpi: CGFloat = 300
    static let wrapInches: CGFloat = 0.75
    static let bleedInches: CGFloat = 0.125
    static let trimWidthInches: CGFloat = 11
    static let trimHeightInches: CGFloat = 8.5

    static let faceWidthInches: CGFloat = trimWidthInches + bleedInches
    static let faceHeightInches: CGFloat = trimHeightInches + bleedInches * 2
    static let totalHeightInches: CGFloat = faceHeightInches + wrapInches * 2

    static func totalWidthInches(spineWidth: CGFloat) -> CGFloat {
        wrapInches + faceWidthInches + spineWidth + faceWidthInches + wrapInches
    }

    static func totalWidthPx(spineWidth: CGFloat) -> Int {
        Int(totalWidthInches(spineWidth: spineWidth) * dpi)
    }

    static var totalHeightPx: Int { Int(totalHeightInches * dpi) }
    static var wrapPx: Int { Int(wrapInches * dpi) }
    static var faceWidthPx: Int { Int(faceWidthInches * dpi) }
    static var faceHeightPx: Int { Int(faceHeightInches * dpi) }
}

/// Renders the full flat cover image for print.
struct BookCoverRenderer {

    // Warm cream (matches interior bookPageBackground)
    static let creamColor = UIColor(red: 0.99, green: 0.97, blue: 0.94, alpha: 1)
    static let spineColor = UIColor(red: 0.6, green: 0.5, blue: 0.4, alpha: 1)
    static let backCoverTextColor = UIColor(red: 0.45, green: 0.38, blue: 0.3, alpha: 1)
    static let backCoverHeadingColor = UIColor(red: 0.22, green: 0.19, blue: 0.16, alpha: 1)
    /// Cream-tinted plate behind back-cover type so it reads over busy AI art.
    private static let backCoverTextPlateFill = UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 0.91)
    private static let backCoverTextPlateStroke = UIColor(red: 0.35, green: 0.30, blue: 0.24, alpha: 0.08)

    /// Typographic **points** → **pixels** at 300 DPI (`BookCoverTemplate.dpi`; same as Lulu portrait templates).
    /// Does not change template widths/heights — all flat-cover PDFs still use fixed `BookCoverTemplate` /
    /// `LuluCoverTemplate` / `PortraitLuluCoverTemplate` totals (e.g. Kids 7200×3075 px).
    private static func px(_ printPoints: CGFloat) -> CGFloat {
        printPoints * BookCoverTemplate.dpi / 72.0
    }

    private static let brandImprintLine = "Made with MemoirAI • memoirai.app"

    /// Render full flat cover at 300 DPI (Kids template: fixed 24×10.25").
    /// - Parameters:
    ///   - frontCoverArt: AI-generated illustration for front cover (will be scaled to fill front area)
    ///   - profileName: Legacy parameter (unused for layout); prefer `frontTitle`.
    ///   - pageCount: Reserved.
    ///   - frontTitle: When `useNativeFrontTitleOverlay` is true, typeset on the front panel (legacy interior-illustration covers). When false, title is expected in the bitmap (AI-rendered).
    ///   - useNativeFrontTitleOverlay: Set false for Gemini AI covers (title is painted in-image). Set true only for non-AI front art that needs readable native type.
    ///   - backCoverPitch: Back-cover marketing copy; MemoirAI imprint is drawn separately (bottom-right).
    ///   - fontPreset: Typography matching book art style.
    /// - Parameter backCoverArt: Optional AI art for the back panel; marketing copy is drawn on top.
    /// - Returns: UIImage at 7200x3075 px, or nil on failure
    static func render(
        frontCoverArt: UIImage,
        backCoverArt: UIImage? = nil,
        profileName: String,
        pageCount: Int = 0,
        frontTitle: String?,
        backCoverPitch: String,
        fontPreset: CoverFontPreset,
        useNativeFrontTitleOverlay: Bool = false
    ) -> UIImage? {
        // Spine scales with page count (Lulu-style table); total flat width grows beyond the legacy 0.25" spine for thick books.
        let spineInches = pageCount > 0
            ? spineWidthInches(forPageCount: pageCount)
            : BookCoverTemplate.spineWidthInches
        let totalWidthInches = BookCoverTemplate.totalWidthInches - BookCoverTemplate.spineWidthInches + spineInches
        let width = CGFloat(totalWidthInches * BookCoverTemplate.dpi)
        let height = CGFloat(BookCoverTemplate.totalHeightPx)
        let wrap = CGFloat(BookCoverTemplate.wrapPx)
        let backW = CGFloat(BookCoverTemplate.backCoverWidthPx)
        let spineW = CGFloat(spineInches * BookCoverTemplate.dpi)
        let frontW = CGFloat(BookCoverTemplate.frontCoverWidthPx)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)

        let image = renderer.image { ctx in
            let cgContext = ctx.cgContext

            // 1. Fill entire canvas with cream
            cgContext.setFillColor(creamColor.cgColor)
            cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let spineX = wrap + backW
            let safeH = height - 2 * wrap
            let backPanel = CGRect(x: wrap, y: wrap, width: backW - wrap, height: safeH)

            // 2. Back cover art (optional): full bleed on back face + left wrap, before spine/front.
            if let backCoverArt {
                let backArtRect = CGRect(x: 0, y: 0, width: wrap + backW, height: height)
                backCoverArt.draw(in: backArtRect)
                drawBackCoverLegibilityOverlay(in: backPanel, context: cgContext)
            }

            // 3. Spine: solid stripe
            cgContext.setFillColor(spineColor.cgColor)
            cgContext.fill(CGRect(x: spineX, y: 0, width: spineW, height: height))

            // 4. Front cover: AI art (full panel including wrap bleed).
            let frontX = spineX + spineW
            let frontRect = CGRect(x: frontX, y: 0, width: frontW + wrap, height: height)
            frontCoverArt.draw(in: frontRect)

            // 5. Back cover: headline + pitch + bottom-right MemoirAI imprint.
            drawBackCoverPanel(in: backPanel, pitch: backCoverPitch, fontPreset: fontPreset, context: cgContext)

            // 6. Optional native front title (AI covers embed title in the artwork instead).
            if useNativeFrontTitleOverlay,
               let t = frontTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                drawFrontCoverLegibilityGradient(in: frontRect, context: cgContext)
                let titleBandH = height * 0.34
                let insetX = frontX + wrap * 0.34
                let titleW = frontW - wrap * 1.08
                let titleRect = CGRect(
                    x: insetX,
                    y: height - wrap - titleBandH - px(16),
                    width: max(titleW, px(100)),
                    height: titleBandH
                )
                drawFrontCoverTitle(text: t, in: titleRect, fontPreset: fontPreset, context: cgContext)
            }
        }

        return image
    }

    /// Darkens the lower portion of the front panel so display type reads like a real jacket cover.
    private static func drawFrontCoverLegibilityGradient(in frontRect: CGRect, context: CGContext) {
        let colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.2).cgColor,
            UIColor.black.withAlphaComponent(0.66).cgColor
        ] as CFArray
        let locs: [CGFloat] = [0.0, 0.35, 1.0]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: locs
        ) else { return }

        context.saveGState()
        context.addRect(frontRect)
        context.clip()
        let start = CGPoint(x: frontRect.midX, y: frontRect.minY + frontRect.height * 0.26)
        let end = CGPoint(x: frontRect.midX, y: frontRect.maxY)
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }

    /// Lightens the upper-left back panel so marketing type stays readable over busy AI art.
    private static func drawBackCoverLegibilityOverlay(in panelRect: CGRect, context: CGContext) {
        let colors = [
            UIColor.white.withAlphaComponent(0.34).cgColor,
            UIColor.white.withAlphaComponent(0.08).cgColor,
            UIColor.clear.cgColor
        ] as CFArray
        let locs: [CGFloat] = [0.0, 0.45, 1.0]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: locs
        ) else { return }

        context.saveGState()
        context.addRect(panelRect)
        context.clip()
        let start = CGPoint(x: panelRect.minX + panelRect.width * 0.12, y: panelRect.minY + panelRect.height * 0.08)
        let end = CGPoint(x: panelRect.maxX - panelRect.width * 0.08, y: panelRect.minY + panelRect.height * 0.55)
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }

    /// Keeps the blurb in a short measure (~6 words per line on typical pitch copy) instead of one long horizontal line.
    private static func backCoverTextColumnWidth(contentWidth: CGFloat) -> CGFloat {
        let capInches: CGFloat = 2.65
        let capPx = capInches * BookCoverTemplate.dpi
        return max(px(76), min(contentWidth * 0.27, capPx))
    }

    private static func drawBackCoverTextPlate(around textBounds: CGRect, context: CGContext) {
        let padX = px(16)
        let padY = px(14)
        let corner = px(11)
        let plate = textBounds.insetBy(dx: -padX, dy: -padY)
        let path = UIBezierPath(roundedRect: plate, cornerRadius: corner)
        context.saveGState()
        context.setFillColor(backCoverTextPlateFill.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.setStrokeColor(backCoverTextPlateStroke.cgColor)
        context.setLineWidth(px(0.75))
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawFrontCoverTitle(text: String, in rect: CGRect, fontPreset: CoverFontPreset, context: CGContext) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = px(3)

        func attributed(for fontSize: CGFloat) -> NSAttributedString {
            let font = fontPreset.titleFont(size: fontSize)
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.68)
            shadow.shadowBlurRadius = px(8)
            shadow.shadowOffset = CGSize(width: 0, height: px(3))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(red: 0.995, green: 0.985, blue: 0.97, alpha: 1),
                .paragraphStyle: paragraphStyle,
                .shadow: shadow
            ]
            return NSAttributedString(string: text, attributes: attrs)
        }

        var fontSize = min(px(74), max(px(38), rect.height * 0.44, rect.width / max(CGFloat(text.count) * 0.19, 6)))
        var attr = attributed(for: fontSize)
        var box = attr.boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let floorSize = px(24)
        while box.height > rect.height && fontSize > floorSize {
            fontSize -= px(1.5)
            attr = attributed(for: fontSize)
            box = attr.boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }

        let usedH = min(box.height, rect.height)
        let drawRect = CGRect(
            x: rect.minX,
            y: rect.midY - usedH / 2,
            width: rect.width,
            height: usedH
        )
        attr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    /// Back cover: left-aligned blurb + reserved footer strip + **bottom-right** MemoirAI imprint only.
    private static func drawBackCoverPanel(in panelRect: CGRect, pitch: String, fontPreset: CoverFontPreset, context: CGContext) {
        let pitchTrim = pitch.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodySource = pitchTrim.isEmpty
            ? "A personal keepsake created from real memories, thoughtfully laid out and ready to print."
            : pitchTrim

        let imprintAreaH = px(20) + px(18)
        let insetH = px(22)
        let insetW = px(26)
        let inner = panelRect.insetBy(dx: insetW, dy: insetH)
        let contentRect = CGRect(
            x: inner.minX,
            y: inner.minY,
            width: inner.width,
            height: max(px(80), inner.height - imprintAreaH)
        )
        let textColumnWidth = backCoverTextColumnWidth(contentWidth: contentRect.width)

        let heading = "About this book"
        var headPt: CGFloat = 19
        var bodyPt: CGFloat = 13
        let minHeadPt: CGFloat = 15
        let minBodyPt: CGFloat = 10

        func makeAttributed() -> NSAttributedString {
            let hStyle = NSMutableParagraphStyle()
            hStyle.alignment = .left
            hStyle.lineBreakMode = .byWordWrapping
            let bStyle = NSMutableParagraphStyle()
            bStyle.alignment = .left
            bStyle.lineBreakMode = .byWordWrapping
            bStyle.lineSpacing = px(3.5)
            bStyle.paragraphSpacing = px(10)

            let full = "\(heading)\n\(bodySource)"
            let out = NSMutableAttributedString(string: full)
            let hFont = fontPreset.titleFont(size: px(headPt))
            let bFont = fontPreset.bodyFont(size: px(bodyPt))
            let headingLength = (heading as NSString).length
            out.addAttributes([
                .font: hFont,
                .foregroundColor: backCoverHeadingColor,
                .paragraphStyle: hStyle
            ], range: NSRange(location: 0, length: headingLength))

            let bodyStart = headingLength + 1
            out.addAttributes([
                .font: bFont,
                .foregroundColor: backCoverTextColor,
                .paragraphStyle: bStyle
            ], range: NSRange(location: bodyStart, length: max(0, out.length - bodyStart)))
            return out
        }

        var combined = makeAttributed()
        var box = combined.boundingRect(
            with: CGSize(width: textColumnWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        while box.height > contentRect.height && (bodyPt > minBodyPt || headPt > minHeadPt) {
            if bodyPt > minBodyPt {
                bodyPt -= 0.75
            } else {
                headPt -= 0.75
            }
            headPt = max(headPt, minHeadPt)
            bodyPt = max(bodyPt, minBodyPt)
            combined = makeAttributed()
            box = combined.boundingRect(
                with: CGSize(width: textColumnWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }

        let drawH = min(box.height, contentRect.height)
        let drawRect = CGRect(
            x: contentRect.minX,
            y: contentRect.minY,
            width: textColumnWidth,
            height: drawH
        )
        let plateRect = box.offsetBy(dx: drawRect.minX, dy: drawRect.minY)
        drawBackCoverTextPlate(around: plateRect, context: context)
        combined.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

        drawBackCoverBrandImprint(in: panelRect, context: context)
    }

    private static func drawBackCoverBrandImprint(in panelRect: CGRect, context: CGContext) {
        let font = UIFont.systemFont(ofSize: px(7), weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: backCoverTextColor.withAlphaComponent(0.78),
            .paragraphStyle: paragraphStyle
        ]
        let text = NSAttributedString(string: brandImprintLine, attributes: attrs)
        let box = text.boundingRect(
            with: CGSize(width: panelRect.width - px(20), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let padR = px(16)
        let padB = px(14)
        let origin = CGPoint(
            x: panelRect.maxX - box.width - padR,
            y: panelRect.maxY - box.height - padB
        )
        text.draw(with: CGRect(origin: origin, size: box.size), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    /// Generate PDF data at printer dimensions (24 x 10.25 inches in points).
    static func renderPDF(
        frontCoverArt: UIImage,
        backCoverArt: UIImage? = nil,
        profileName: String,
        pageCount: Int = 0,
        frontTitle: String?,
        backCoverPitch: String,
        fontPreset: CoverFontPreset,
        useNativeFrontTitleOverlay: Bool = false
    ) -> Data? {
        guard let coverImage = render(
            frontCoverArt: frontCoverArt,
            backCoverArt: backCoverArt,
            profileName: profileName,
            pageCount: pageCount,
            frontTitle: frontTitle,
            backCoverPitch: backCoverPitch,
            fontPreset: fontPreset,
            useNativeFrontTitleOverlay: useNativeFrontTitleOverlay
        ) else { return nil }

        let spineInches = pageCount > 0
            ? spineWidthInches(forPageCount: pageCount)
            : BookCoverTemplate.spineWidthInches
        let totalWidthInches = BookCoverTemplate.totalWidthInches - BookCoverTemplate.spineWidthInches + spineInches
        let widthPt = totalWidthInches * 72
        let heightPt = BookCoverTemplate.totalHeightInches * 72
        let bounds = CGRect(x: 0, y: 0, width: widthPt, height: heightPt)

        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            ctx.beginPage(withBounds: bounds, pageInfo: [:])
            coverImage.draw(in: bounds)
        }
    }

    /// Generate PDF for Lulu casewrap (0.75" wrap, 0.125" bleed, spine from page count).
    static func renderLuluPDF(
        frontCoverArt: UIImage,
        backCoverArt: UIImage? = nil,
        profileName: String,
        pageCount: Int,
        frontTitle: String?,
        backCoverPitch: String,
        fontPreset: CoverFontPreset,
        useNativeFrontTitleOverlay: Bool = false
    ) -> Data? {
        let spineW = spineWidthInches(forPageCount: pageCount)
        let totalW = LuluCoverTemplate.totalWidthInches(spineWidth: spineW)
        let totalH = LuluCoverTemplate.totalHeightInches
        let wrap = CGFloat(LuluCoverTemplate.wrapPx)
        let faceW = CGFloat(LuluCoverTemplate.faceWidthPx)
        let spinePx = spineW * LuluCoverTemplate.dpi
        let height = CGFloat(LuluCoverTemplate.totalHeightPx)
        let width = CGFloat(LuluCoverTemplate.totalWidthPx(spineWidth: spineW))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)

        let image = renderer.image { ctx in
            let cgContext = ctx.cgContext
            cgContext.setFillColor(creamColor.cgColor)
            cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let spineX = wrap + faceW
            let backPanel = CGRect(x: wrap, y: wrap, width: faceW - wrap, height: height - 2 * wrap)

            if let backCoverArt {
                let backArtRect = CGRect(x: 0, y: 0, width: wrap + faceW, height: height)
                backCoverArt.draw(in: backArtRect)
                drawBackCoverLegibilityOverlay(in: backPanel, context: cgContext)
            }

            cgContext.setFillColor(spineColor.cgColor)
            cgContext.fill(CGRect(x: spineX, y: 0, width: spinePx, height: height))

            let frontX = spineX + spinePx
            let frontRect = CGRect(x: frontX, y: 0, width: faceW + wrap, height: height)
            frontCoverArt.draw(in: frontRect)

            drawBackCoverPanel(in: backPanel, pitch: backCoverPitch, fontPreset: fontPreset, context: cgContext)

            if useNativeFrontTitleOverlay,
               let t = frontTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                drawFrontCoverLegibilityGradient(in: frontRect, context: cgContext)
                let inset = wrap * 0.34
                let titleW = (faceW + wrap) - inset * 2
                let titleH = height * 0.31
                let titleRect = CGRect(x: frontX + inset, y: height - wrap - titleH - px(16), width: max(titleW, px(100)), height: titleH)
                drawFrontCoverTitle(text: t, in: titleRect, fontPreset: fontPreset, context: cgContext)
            }
        }

        let widthPt = totalW * 72
        let heightPt = totalH * 72
        let bounds = CGRect(x: 0, y: 0, width: widthPt, height: heightPt)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: bounds)
        return pdfRenderer.pdfData { ctx in
            ctx.beginPage(withBounds: bounds, pageInfo: [:])
            image.draw(in: bounds)
        }
    }

    /// Generate PDF for Lulu casewrap portrait books (8.5x11"). Uses first illustration as front cover.
    static func renderPortraitPDF(
        frontCoverArt: UIImage,
        backCoverArt: UIImage? = nil,
        profileName: String,
        pageCount: Int,
        frontTitle: String?,
        backCoverPitch: String,
        fontPreset: CoverFontPreset,
        useNativeFrontTitleOverlay: Bool = false
    ) -> Data? {
        let spineW = spineWidthInches(forPageCount: pageCount)
        let totalW = PortraitLuluCoverTemplate.totalWidthInches(spineWidth: spineW)
        let totalH = PortraitLuluCoverTemplate.totalHeightInches
        let wrap = CGFloat(PortraitLuluCoverTemplate.wrapPx)
        let faceW = CGFloat(PortraitLuluCoverTemplate.faceWidthPx)
        let spinePx = spineW * PortraitLuluCoverTemplate.dpi
        let height = CGFloat(PortraitLuluCoverTemplate.totalHeightPx)
        let width = CGFloat(PortraitLuluCoverTemplate.totalWidthPx(spineWidth: spineW))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)

        let image = renderer.image { ctx in
            let cgContext = ctx.cgContext
            cgContext.setFillColor(creamColor.cgColor)
            cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let spineX = wrap + faceW
            let backPanel = CGRect(x: wrap, y: wrap, width: faceW - wrap, height: height - 2 * wrap)

            if let backCoverArt {
                let backArtRect = CGRect(x: 0, y: 0, width: wrap + faceW, height: height)
                backCoverArt.draw(in: backArtRect)
                drawBackCoverLegibilityOverlay(in: backPanel, context: cgContext)
            }

            cgContext.setFillColor(spineColor.cgColor)
            cgContext.fill(CGRect(x: spineX, y: 0, width: spinePx, height: height))

            let frontX = spineX + spinePx
            let frontRect = CGRect(x: frontX, y: 0, width: faceW + wrap, height: height)
            frontCoverArt.draw(in: frontRect)

            drawBackCoverPanel(in: backPanel, pitch: backCoverPitch, fontPreset: fontPreset, context: cgContext)

            if useNativeFrontTitleOverlay,
               let t = frontTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                drawFrontCoverLegibilityGradient(in: frontRect, context: cgContext)
                let inset = wrap * 0.34
                let titleW = (faceW + wrap) - inset * 2
                let titleH = height * 0.31
                let titleRect = CGRect(x: frontX + inset, y: height - wrap - titleH - px(16), width: max(titleW, px(100)), height: titleH)
                drawFrontCoverTitle(text: t, in: titleRect, fontPreset: fontPreset, context: cgContext)
            }
        }

        let widthPt = totalW * 72
        let heightPt = totalH * 72
        let bounds = CGRect(x: 0, y: 0, width: widthPt, height: heightPt)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: bounds)
        return pdfRenderer.pdfData { ctx in
            ctx.beginPage(withBounds: bounds, pageInfo: [:])
            image.draw(in: bounds)
        }
    }
}

// MARK: - Flat cover panel geometry (UI preview only)

/// Which print template produced the uploaded `cover.pdf` — must match `FirestoreSyncService.syncBook` paths.
enum BookCoverFlatLayoutKind: Equatable {
    /// Kids landscape: `BookCoverTemplate` total width (24" baseline) with spine width from page count.
    case kidsBook(pageCount: Int)
    /// Portrait casewrap: `PortraitLuluCoverTemplate` with spine from page count.
    case portraitCasewrap(pageCount: Int)
}

/// Normalized rectangles in PDF page space (media box), origin top-left, values 0…1.
struct BookCoverFlatPanelRects: Equatable {
    let back: CGRect
    let spine: CGRect
    let front: CGRect

    func normalizedRect(for panel: BookCoverFlatPanel) -> CGRect? {
        switch panel {
        case .full: return nil
        case .back: return back
        case .spine: return spine
        case .front: return front
        }
    }
}

/// Sub-rectangle of the flat casewrap for thumbnails (same file as full cover PDF).
enum BookCoverFlatPanel: Equatable {
    case full
    case back
    case spine
    case front
}

extension BookCoverRenderer {
    /// Horizontal thirds of the flat cover: back | spine | front (includes outer wrap regions).
    static func flatPanelRects(for layout: BookCoverFlatLayoutKind) -> BookCoverFlatPanelRects {
        switch layout {
        case .kidsBook(let pageCount):
            let spineWInches = pageCount > 0
                ? spineWidthInches(forPageCount: pageCount)
                : BookCoverTemplate.spineWidthInches
            let totalW = BookCoverTemplate.totalWidthInches - BookCoverTemplate.spineWidthInches + spineWInches
            let wrap = BookCoverTemplate.wrapInches
            let backW = BookCoverTemplate.backCoverWidthInches
            let spineW = spineWInches
            let xAfterBack = wrap + backW
            let xAfterSpine = xAfterBack + spineW
            let back = CGRect(x: 0, y: 0, width: xAfterBack / totalW, height: 1)
            let spine = CGRect(x: xAfterBack / totalW, y: 0, width: spineW / totalW, height: 1)
            let front = CGRect(x: xAfterSpine / totalW, y: 0, width: (totalW - xAfterSpine) / totalW, height: 1)
            return BookCoverFlatPanelRects(back: back, spine: spine, front: front)

        case .portraitCasewrap(let pageCount):
            let spineW = spineWidthInches(forPageCount: pageCount)
            let totalW = PortraitLuluCoverTemplate.totalWidthInches(spineWidth: spineW)
            let wrap = PortraitLuluCoverTemplate.wrapInches
            let faceW = PortraitLuluCoverTemplate.faceWidthInches
            let xAfterBack = wrap + faceW
            let xAfterSpine = xAfterBack + spineW
            let back = CGRect(x: 0, y: 0, width: xAfterBack / totalW, height: 1)
            let spine = CGRect(x: xAfterBack / totalW, y: 0, width: spineW / totalW, height: 1)
            let front = CGRect(x: xAfterSpine / totalW, y: 0, width: (totalW - xAfterSpine) / totalW, height: 1)
            return BookCoverFlatPanelRects(back: back, spine: spine, front: front)
        }
    }
}

