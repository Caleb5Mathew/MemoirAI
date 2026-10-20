import SwiftUI

struct MemoirBlankPage: View {
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    var body: some View {
        Color(red: 0.985, green: 0.975, blue: 0.95)
            .frame(width: frameWidth, height: frameHeight)
    }
}

/// Shared front/back cover page styling used in preview + rendered page images.
enum BookInteriorStyle {
    static let paper = Color(red: 250 / 255, green: 242 / 255, blue: 227 / 255)
    static let ink = Color(red: 59 / 255, green: 70 / 255, blue: 59 / 255)
    static let accent = Color(red: 155 / 255, green: 85 / 255, blue: 47 / 255)
    static let rule = Color(red: 196 / 255, green: 203 / 255, blue: 186 / 255)
    static let appURL = MemoryLinks.appStoreURL.absoluteString
    static func openingTitle(_ title: String) -> String {
        guard title.hasSuffix(" Memoir") else { return title }
        return String(title.dropLast(7)) + "\nMemoir"
    }

    static let bodySize: CGFloat = 0.023
    static let lineSpacing: CGFloat = 0.0025
    static let memoryHorizontalInset: CGFloat = 0.09
    static let memoryContentWidth: CGFloat = 0.82
    static let memoryKickerY: CGFloat = 0.075
    static let memoryTitleY: CGFloat = 0.115
    static let memoryTitleHeight: CGFloat = 0.075
    static let memoryRuleY: CGFloat = 0.225
    static let memoryBodyY: CGFloat = 0.265
    static let memoryBodyHeight: CGFloat = 0.66
    static let memoryPageNumberY: CGFloat = 0.965
}

enum BookInteriorTextLayout {
    static func height(of text: String, width: CGFloat, fontSize: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * BookInteriorStyle.lineSpacing / BookInteriorStyle.bodySize
        paragraph.lineBreakMode = .byWordWrapping
        let font = UIFont(name: "Georgia", size: fontSize) ?? .systemFont(ofSize: fontSize)
        return ceil((text as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph], context: nil
        ).height)
    }

}

struct MemoirCoverFrontPage: View {
    let title: String
    let subtitle: String
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let isKidsBook: Bool

    var body: some View {
        let layout = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: Double(frameWidth / max(frameHeight, 1)), isKidsBook: isKidsBook
        )
        ZStack(alignment: .topLeading) {
            BookInteriorStyle.paper
            Text(BookInteriorStyle.openingTitle(title))
                .font(.custom("GillSans", size: frameHeight * layout.titleFontSize))
                .foregroundStyle(BookInteriorStyle.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.55)
                .frame(width: frameWidth * layout.titleFrame.width,
                       height: frameHeight * layout.titleFrame.height, alignment: .leading)
                .offset(x: frameWidth * layout.titleFrame.x, y: frameHeight * layout.titleFrame.y)
            Text(subtitle)
                .font(.custom("Georgia", size: frameHeight * layout.titleBodyFontSize))
                .foregroundStyle(BookInteriorStyle.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .frame(width: frameWidth * layout.titleBodyFrame.width,
                       height: frameHeight * layout.titleBodyFrame.height, alignment: .topLeading)
                .offset(x: frameWidth * layout.titleBodyFrame.x, y: frameHeight * layout.titleBodyFrame.y)
            HStack(alignment: .bottom, spacing: frameWidth * 0.02) {
                VStack(spacing: frameWidth * 0.006) {
                    MemoirAppIcon(side: frameWidth * 0.058)
                    Text("memoir")
                        .font(.custom("Georgia", size: frameWidth * 0.026))
                        .foregroundStyle(BookInteriorStyle.ink)
                }
                Image(uiImage: StoryPageViewModel.qrCode(from: BookInteriorStyle.appURL, size: 256))
                    .interpolation(.none)
                    .resizable()
                    .padding(frameWidth * 0.007)
                    .background(.white)
                    .frame(width: frameWidth * 0.105, height: frameWidth * 0.105)
            }
            .position(x: frameWidth * 0.82, y: frameHeight * 0.86)
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipped()
    }
}

struct MemoirCoverBackPage: View {
    /// Subject's display name from the closing page's `subtitle`; nil for books
    /// persisted before the credit line existed.
    let subtitle: String?
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    var body: some View {
        let layout = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: Double(frameWidth / max(frameHeight, 1)),
            isKidsBook: false
        )
        ZStack {
            MemoirCoverBackBackgroundPage(frameWidth: frameWidth, frameHeight: frameHeight)

            Text("Made with Memoir")
                .font(.custom("GillSans", size: frameHeight * layout.closingHeadingFontSize))
                .foregroundStyle(BookInteriorStyle.ink)
                .multilineTextAlignment(.leading)
                .frame(
                    width: frameWidth * layout.closingHeadingFrame.width,
                    height: frameHeight * layout.closingHeadingFrame.height,
                    alignment: .leading
                )
                .position(
                    x: frameWidth * (layout.closingHeadingFrame.x + layout.closingHeadingFrame.width / 2),
                    y: frameHeight * (layout.closingHeadingFrame.y + layout.closingHeadingFrame.height / 2)
                )

            Text("Download on the App Store")
                .font(.custom("GillSans", size: frameHeight * layout.closingStoreFontSize))
                .foregroundStyle(BookInteriorStyle.ink)
                .multilineTextAlignment(.leading)
                .frame(
                    width: frameWidth * layout.closingStoreTextFrame.width,
                    height: frameHeight * layout.closingStoreTextFrame.height,
                    alignment: .leading
                )
                .position(
                    x: frameWidth * (layout.closingStoreTextFrame.x + layout.closingStoreTextFrame.width / 2),
                    y: frameHeight * (layout.closingStoreTextFrame.y + layout.closingStoreTextFrame.height / 2)
                )
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Decorative closing-page layer. Keeping copy out of this view lets the page editor
/// seed the same artwork while exposing every visible word as an editable element.
struct MemoirCoverBackBackgroundPage: View {
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    var body: some View {
        let layout = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: Double(frameWidth / max(frameHeight, 1)),
            isKidsBook: false
        )
        let iconWidth = frameWidth * layout.closingIconFrame.width
        let iconHeight = frameHeight * layout.closingIconFrame.height
        ZStack {
            BookInteriorStyle.paper

            MemoirAppIcon(side: min(iconWidth, iconHeight))
                .position(
                    x: frameWidth * (layout.closingIconFrame.x + layout.closingIconFrame.width / 2),
                    y: frameHeight * (layout.closingIconFrame.y + layout.closingIconFrame.height / 2)
                )

            Rectangle()
                .fill(BookInteriorStyle.rule)
                .frame(width: frameWidth * 0.78, height: max(0.5, frameHeight * 0.001))
                .position(x: frameWidth * 0.50, y: frameHeight * 0.37)
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MemoirAppIcon: View {
    let side: CGFloat

    var body: some View {
        Group {
            if let image = Self.installedAppIcon {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("AppIcon")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
    }

    private static var installedAppIcon: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else {
            return nil
        }
        return UIImage(named: name)
    }
}
