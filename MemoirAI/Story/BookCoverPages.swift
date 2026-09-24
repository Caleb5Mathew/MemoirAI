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
struct MemoirCoverFrontPage: View {
    let title: String
    let subtitle: String
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let isKidsBook: Bool

    private let background = Color(red: 0.965, green: 0.94, blue: 0.89)
    private let panel = Color(red: 0.985, green: 0.975, blue: 0.95)
    private let titleColor = Color(red: 0.18, green: 0.16, blue: 0.14)
    private let bodyColor = Color(red: 0.42, green: 0.38, blue: 0.33)

    var body: some View {
        let typographyPreset: BookPageTypographyPreset = isKidsBook ? .kidsBook : .realistic
        let layout = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: Double(frameWidth / max(frameHeight, 1)),
            isKidsBook: isKidsBook
        )
        ZStack {
            background

            RoundedRectangle(cornerRadius: frameHeight * 0.028, style: .continuous)
                .fill(panel)
                .overlay(
                    RoundedRectangle(cornerRadius: frameHeight * 0.028, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .padding(frameWidth * 0.055)

            HStack(spacing: frameWidth * 0.018) {
                Rectangle()
                    .fill(Color(red: 0.72, green: 0.48, blue: 0.31).opacity(0.55))
                    .frame(width: frameWidth * 0.12, height: max(1, frameHeight * 0.003))
                Circle()
                    .fill(Color(red: 0.72, green: 0.48, blue: 0.31).opacity(0.72))
                    .frame(width: frameHeight * 0.018, height: frameHeight * 0.018)
                Rectangle()
                    .fill(Color(red: 0.72, green: 0.48, blue: 0.31).opacity(0.55))
                    .frame(width: frameWidth * 0.12, height: max(1, frameHeight * 0.003))
            }
            .position(x: frameWidth * 0.5, y: frameHeight * 0.245)

            Text(title)
                .font(
                    typographyPreset.interiorTitleTypography == .rounded
                        ? .system(size: frameHeight * layout.titleFontSize, weight: .semibold, design: .rounded)
                        : .custom("Georgia-Bold", size: frameHeight * layout.titleFontSize)
                )
                .foregroundColor(titleColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
                .frame(
                    width: frameWidth * layout.titleFrame.width,
                    height: frameHeight * layout.titleFrame.height,
                    alignment: .center
                )
                .position(
                    x: frameWidth * (layout.titleFrame.x + layout.titleFrame.width / 2),
                    y: frameHeight * (layout.titleFrame.y + layout.titleFrame.height / 2)
                )

            if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(
                        typographyPreset.interiorTitleTypography == .rounded
                            ? .system(size: frameHeight * layout.titleBodyFontSize, weight: .regular, design: .rounded)
                            : .custom("Georgia", size: frameHeight * layout.titleBodyFontSize)
                    )
                    .foregroundColor(bodyColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                    .frame(
                        width: frameWidth * layout.titleBodyFrame.width,
                        height: frameHeight * layout.titleBodyFrame.height,
                        alignment: .center
                    )
                    .position(
                        x: frameWidth * (layout.titleBodyFrame.x + layout.titleBodyFrame.width / 2),
                        y: frameHeight * (layout.titleBodyFrame.y + layout.titleBodyFrame.height / 2)
                    )
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

}

struct MemoirCoverBackPage: View {
    /// Subject's display name from the closing page's `subtitle`; nil for books
    /// persisted before the credit line existed.
    let subtitle: String?
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    private let headingColor = Color(red: 0.20, green: 0.18, blue: 0.15)

    var body: some View {
        let layout = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: Double(frameWidth / max(frameHeight, 1)),
            isKidsBook: false
        )
        ZStack {
            MemoirCoverBackBackgroundPage(frameWidth: frameWidth, frameHeight: frameHeight)

            Text("Made with Memoir")
                .font(.custom("Georgia-Bold", size: frameHeight * layout.closingHeadingFontSize))
                .foregroundColor(headingColor)
                .multilineTextAlignment(.center)
                .frame(
                    width: frameWidth * layout.closingHeadingFrame.width,
                    height: frameHeight * layout.closingHeadingFrame.height,
                    alignment: .center
                )
                .position(
                    x: frameWidth * (layout.closingHeadingFrame.x + layout.closingHeadingFrame.width / 2),
                    y: frameHeight * (layout.closingHeadingFrame.y + layout.closingHeadingFrame.height / 2)
                )

            Text("Download on the App Store")
                .font(.system(size: frameHeight * layout.closingStoreFontSize, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(
                    width: frameWidth * layout.closingStoreTextFrame.width,
                    height: frameHeight * layout.closingStoreTextFrame.height,
                    alignment: .center
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

    private let background = Color(red: 0.955, green: 0.925, blue: 0.875)
    private let panel = Color(red: 0.99, green: 0.98, blue: 0.955)
    var body: some View {
        let layout = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: Double(frameWidth / max(frameHeight, 1)),
            isKidsBook: false
        )
        let iconWidth = frameWidth * layout.closingIconFrame.width
        let iconHeight = frameHeight * layout.closingIconFrame.height
        let badgeWidth = frameWidth * layout.closingBadgeFrame.width
        let badgeHeight = frameHeight * layout.closingBadgeFrame.height
        ZStack {
            background

            RoundedRectangle(cornerRadius: frameHeight * 0.028, style: .continuous)
                .fill(panel)
                .overlay(
                    RoundedRectangle(cornerRadius: frameHeight * 0.028, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .padding(frameWidth * 0.065)

            MemoirAppIcon(side: min(iconWidth, iconHeight))
                .position(
                    x: frameWidth * (layout.closingIconFrame.x + layout.closingIconFrame.width / 2),
                    y: frameHeight * (layout.closingIconFrame.y + layout.closingIconFrame.height / 2)
                )

            Capsule()
                .fill(Color.black)
                .frame(width: badgeWidth, height: badgeHeight)
                .position(
                    x: frameWidth * (layout.closingBadgeFrame.x + layout.closingBadgeFrame.width / 2),
                    y: frameHeight * (layout.closingBadgeFrame.y + layout.closingBadgeFrame.height / 2)
                )

            Image(systemName: "apple.logo")
                .font(.system(size: badgeHeight * 0.42, weight: .medium))
                .foregroundColor(.white)
                .position(
                    x: frameWidth * (layout.closingBadgeFrame.x + layout.closingBadgeFrame.width * 0.12),
                    y: frameHeight * (layout.closingBadgeFrame.y + layout.closingBadgeFrame.height / 2)
                )
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
