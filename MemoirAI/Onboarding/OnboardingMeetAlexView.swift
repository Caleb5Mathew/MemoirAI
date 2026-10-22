import SwiftUI

struct OnboardingMeetAlexView: View {
    let showsBackButton: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void

    init(
        showsBackButton: Bool = true,
        onBack: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onContinue: @escaping () -> Void
    ) {
        self.showsBackButton = showsBackButton
        self.onBack = onBack
        self.onSkip = onSkip
        self.onContinue = onContinue
    }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let colors = OnboardingColorTheme()

    var body: some View {
        GeometryReader { proxy in
            let layout = MeetAlexComposition(size: proxy.size, accessibility: dynamicTypeSize.isAccessibilitySize)
            ZStack(alignment: .bottomLeading) {
                Image("AlexOnboardingPortrait")
                    .resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
                    .clipped()
                    .position(x: proxy.size.width / 2, y: (proxy.size.height + proxy.safeAreaInsets.bottom - proxy.safeAreaInsets.top) / 2)
                    .accessibilityHidden(true)
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: colors.ink.opacity(0.12), location: 0),
                            .init(color: .clear, location: 0.34),
                            .init(color: colors.ink.opacity(0.24), location: 0.55),
                            .init(color: colors.ink.opacity(0.94), location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                    }

                VStack(spacing: 0) {
                    navigation
                    Spacer(minLength: layout.minimumPortraitSpace)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: -layout.headingSize * 0.55) {
                                Text("Meet")
                                Text("Alex.")
                            }
                                .font(.custom("IowanOldStyle-Roman", size: layout.headingSize, relativeTo: .largeTitle))
                                .tracking(-layout.headingSize * 0.06)
                                .foregroundStyle(.white)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Meet Alex.")
                                .accessibilityAddTraits(.isHeader)
                            Text("Alex created a book of his life stories for his kids and grandkids to read through.")
                                .font(.custom("AvenirNext-Regular", size: 17, relativeTo: .body))
                                .foregroundStyle(.white)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(.bottom)
                    .frame(maxHeight: layout.copyHeight)
                    .padding(.bottom, 24)
                    Button(action: onContinue) {
                        HStack {
                            Text("Show me the book")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.custom("AvenirNext-DemiBold", size: 14, relativeTo: .body))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 17)
                        .frame(minHeight: 56)
                        .background(colors.moss, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.bottom, 18)
                }
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: layout.contentWidth)
                .frame(maxWidth: .infinity, alignment: layout.isLandscape ? .trailing : .center)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var navigation: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "arrow.left").frame(width: 44, height: 44)
                    .background(colors.ink.opacity(0.58), in: Circle())
            }
            .accessibilityLabel("Back")
            .accessibilityHidden(!showsBackButton)
            .opacity(showsBackButton ? 1 : 0)
            .disabled(!showsBackButton)
            Spacer()
            Text("ALEX’S BOOK")
                .font(.custom("AvenirNext-DemiBold", size: 10, relativeTo: .caption))
                .tracking(1.8)
            Spacer()
            Button("Skip", action: onSkip)
                .font(.custom("AvenirNext-DemiBold", size: 13, relativeTo: .body))
                .frame(minWidth: 44, minHeight: 44)
                .background(colors.ink.opacity(0.58), in: Circle())
                .accessibilityLabel("Skip tour")
        }
        .foregroundStyle(colors.paper)
        .padding(.top, 8)
    }


}

struct MeetAlexComposition {
    let isLandscape: Bool
    let contentWidth: CGFloat
    let horizontalPadding: CGFloat
    let headingSize: CGFloat
    let minimumPortraitSpace: CGFloat
    let copyHeight: CGFloat

    init(size: CGSize, accessibility: Bool) {
        isLandscape = size.width > size.height
        contentWidth = isLandscape ? min(460, size.width * 0.58) : min(560, size.width)
        horizontalPadding = size.width < 380 ? 22 : 28
        headingSize = accessibility ? 48 : (isLandscape ? 48 : min(92, size.width * 0.22))
        minimumPortraitSpace = accessibility || isLandscape ? 12 : max(24, size.height * 0.20)
        copyHeight = accessibility ? max(100, size.height - 170) : (isLandscape ? 180 : headingSize * 1.85 + 90)
    }
}
