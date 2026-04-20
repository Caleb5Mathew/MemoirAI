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
    let heading: String
    let bodyText: String
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    private let background = Color(red: 0.955, green: 0.925, blue: 0.875)
    private let panel = Color(red: 0.99, green: 0.98, blue: 0.955)
    private let headingColor = Color(red: 0.20, green: 0.18, blue: 0.15)
    private let bodyColor = Color(red: 0.36, green: 0.33, blue: 0.29)
    private let brandColor = Color(red: 0.50, green: 0.45, blue: 0.40)

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

            VStack(alignment: .leading, spacing: 0) {
                Text(heading)
                    .font(.system(size: frameHeight * 0.052, weight: .bold, design: .serif))
                    .foregroundColor(headingColor)
                    .padding(.top, frameHeight * 0.12)
                    .padding(.horizontal, frameWidth * 0.11)

                Text(bodyText)
                    .font(.system(size: frameHeight * 0.034, weight: .regular, design: .serif))
                    .foregroundColor(bodyColor)
                    .lineSpacing(frameHeight * 0.01)
                    .multilineTextAlignment(.leading)
                    .padding(.top, frameHeight * 0.05)
                    .padding(.horizontal, frameWidth * 0.11)

                Spacer()

                HStack {
                    Spacer()
                    Text("Made with MemoirAI  •  memoirai.app")
                        .font(.system(size: frameHeight * 0.018, weight: .semibold))
                        .foregroundColor(brandColor)
                        .padding(.trailing, frameWidth * 0.1)
                        .padding(.bottom, frameHeight * 0.06)
                }
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
