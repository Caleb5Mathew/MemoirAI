import SwiftUI

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
        ZStack {
            background

            RoundedRectangle(cornerRadius: frameHeight * 0.028, style: .continuous)
                .fill(panel)
                .overlay(
                    RoundedRectangle(cornerRadius: frameHeight * 0.028, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .padding(frameWidth * 0.055)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: frameHeight * 0.03) {
                    Text(title)
                        .font(.system(size: isKidsBook ? frameHeight * 0.1 : frameHeight * 0.075, weight: .bold, design: .serif))
                        .foregroundColor(titleColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, frameWidth * 0.11)

                    if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(subtitle)
                            .font(.system(size: frameHeight * 0.032, weight: .medium, design: .serif))
                            .foregroundColor(bodyColor)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, frameWidth * 0.14)
                    }
                }

                Spacer()
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

    private let background = Color(red: 0.955, green: 0.925, blue: 0.875)
    private let panel = Color(red: 0.99, green: 0.98, blue: 0.955)
    private let headingColor = Color(red: 0.20, green: 0.18, blue: 0.15)
    private let bodyColor = Color(red: 0.36, green: 0.33, blue: 0.29)

    private var subjectName: String {
        let t = (subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "this storyteller" : t
    }

    private var badgeSide: CGFloat { frameHeight * 0.09 }

    var body: some View {
        ZStack {
            background

            RoundedRectangle(cornerRadius: frameHeight * 0.028, style: .continuous)
                .fill(panel)
                .overlay(
                    RoundedRectangle(cornerRadius: frameHeight * 0.028, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .padding(frameWidth * 0.065)

            VStack(spacing: frameHeight * 0.04) {
                Spacer()

                Text("This book was a life memoir of\n\(subjectName)")
                    .font(.system(size: frameHeight * 0.042, weight: .semibold, design: .serif))
                    .foregroundColor(bodyColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(frameHeight * 0.012)
                    .padding(.horizontal, frameWidth * 0.12)

                HStack(spacing: frameWidth * 0.02) {
                    Text("produced by")
                        .font(.system(size: frameHeight * 0.03, weight: .medium, design: .serif))
                        .foregroundColor(bodyColor)
                    MemoirLogoMark(side: badgeSide)
                    Text("Memoir")
                        .font(.system(size: frameHeight * 0.036, weight: .bold, design: .serif))
                        .foregroundColor(headingColor)
                }

                Image(uiImage: QRCodeCache.image(for: MemoirAppLinks.appLinkURL.absoluteString, size: badgeSide * 6))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: badgeSide, height: badgeSide)
                    .padding(frameHeight * 0.012)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: badgeSide * 0.18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: badgeSide * 0.18, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                Spacer()
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The Memoir logo mark for in-content use. Renders the dedicated asset when it
/// exists; falls back to a styled monogram until the artwork lands.
struct MemoirLogoMark: View {
    let side: CGFloat

    var body: some View {
        if let logo = UIImage(named: "MemoirLogoMark") {
            Image(uiImage: logo)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                .fill(Color(red: 0.20, green: 0.18, blue: 0.15))
                .frame(width: side, height: side)
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(side * 0.24)
                        .foregroundColor(Color(red: 0.955, green: 0.925, blue: 0.875))
                )
        }
    }
}
