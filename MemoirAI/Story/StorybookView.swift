import SwiftUI

// MARK: - Main Storybook View
struct StorybookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileVM: ProfileViewModel

    @State private var currentPage = 0
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [UIImage] = []

    // Sample pages for the finished book preview
    private let samplePages = MockBookPage.samplePages

    var body: some View {
        NavigationView {
            ZStack {
                // Warm parchment gradient background
                LinearGradient(
                    colors: [Tokens.bgPrimary, Tokens.bgWash],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView

                    GeometryReader { geo in
                        // Spread sizing: two 3:4 pages side-by-side → ~3:2 aspect
                        let maxW = geo.size.width * Tokens.bookMaxWidthPct
                        let targetAspect: CGFloat = 3.0 / 2.0
                        let maxH = geo.size.height * 0.60

                        var bookW = maxW
                        var bookH = bookW / targetAspect
                        if bookH > maxH {
                            bookH = maxH
                            bookW = bookH * targetAspect
                        }

                        VStack(spacing: 0) {
                            // Open book preview (always shown for the mock)
                            OpenBookView(
                                pages: samplePages,
                                currentPage: $currentPage,
                                bookWidth: bookW,
                                bookHeight: bookH
                            )

                            Spacer()

                            if samplePages.count > 1 {
                                Text("Swipe to flip pages")
                                    .font(Tokens.Typography.hint)
                                    .foregroundColor(Tokens.ink.opacity(0.6))
                                    .padding(.top, Tokens.bookSpacing)
                                    .padding(.bottom, Tokens.buttonSpacing)
                            }

                            actionButtonsView
                                .padding(.bottom, Tokens.bottomPadding)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerSheet(
                isPresented: $showPhotoPicker,
                onPhotosSelected: { photos in
                    selectedPhotos = photos
                }
            )
        }
        .onAppear { currentPage = 0 }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Tokens.ink.opacity(0.7))
                    .padding(10)
                    .background(Tokens.bgWash)
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: Tokens.headerSpacing) {
                Text("Create your book")
                    .font(Tokens.Typography.title)
                    .foregroundColor(Tokens.ink)

                Text("Flip through a finished book")
                    .font(Tokens.Typography.subtitle)
                    .foregroundColor(Tokens.ink.opacity(0.7))
            }

            Spacer()

            // Spacer to balance back button
            Color.clear
                .frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }

    // MARK: - Action Buttons View
    private var actionButtonsView: some View {
        VStack(spacing: Tokens.buttonSpacing) {
            // Primary: gradient-outline pill (navigates to creation flow)
            NavigationLink(destination: StoryPage().environmentObject(profileVM)) {
                Text("Create your own book")
                    .font(Tokens.Typography.button)
                    .foregroundColor(Tokens.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule().fill(Color.clear)
                    )
                    .primaryGradientOutline(lineWidth: Tokens.gradientStrokeWidth)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create your own book")

            // Secondary: soft cream filled pill (opens photo picker)
            Button(action: { showPhotoPicker = true }) {
                Text("Add photos")
                    .font(Tokens.Typography.button)
                    .fontWeight(.medium)
                    .foregroundColor(Tokens.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(Tokens.bgPrimary)
                            .shadow(color: Tokens.shadow.opacity(Tokens.softShadow.opacity),
                                    radius: Tokens.softShadow.radius,
                                    x: 0,
                                    y: Tokens.softShadow.y)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add photos")
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview
struct StorybookView_Previews: PreviewProvider {
    static var previews: some View {
        StorybookView()
            .environmentObject(ProfileViewModel())
    }
}
