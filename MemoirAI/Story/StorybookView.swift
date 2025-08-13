import SwiftUI
import WebKit

// MARK: - Main Storybook View
struct StorybookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileVM: ProfileViewModel

    @State private var currentPage = 0
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [UIImage] = []
    @State private var flipbookReady = false
    @State private var useFallback = false
    @State private var webView: WKWebView?

    // Sample pages for the finished book preview
    private let samplePages = MockBookPage.samplePages
    private let flipbookPages = FlipPage.samplePages
    
    // Helper function to calculate book size outside ViewBuilder context
    private func calculateBookSize(for size: CGSize) -> CGSize {
        let maxW = size.width * Tokens.bookMaxWidthPct
        let targetAspect: CGFloat = 3.0 / 2.0
        let maxH = size.height * 0.60

        var bookW = maxW
        var bookH = bookW / targetAspect
        if bookH > maxH {
            bookH = maxH
            bookW = bookH * targetAspect
        }
        
        return CGSize(width: bookW, height: bookH)
    }

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
                        let bookSize = calculateBookSize(for: geo.size)
                        
                        VStack(spacing: 0) {
                            // Flipbook preview with fallback to native OpenBookView
                            if useFallback {
                                // Fallback to native implementation
                                ZStack {
                                    OpenBookView(
                                        pages: samplePages,
                                        currentPage: $currentPage,
                                        bookWidth: bookSize.width,
                                        bookHeight: bookSize.height
                                    )
                                    
                                    // Debug overlay for fallback
                                    VStack {
                                        HStack {
                                            Text("Native Fallback")
                                                .font(.caption)
                                                .padding(4)
                                                .background(Color.red.opacity(0.8))
                                                .foregroundColor(.white)
                                                .cornerRadius(4)
                                            Spacer()
                                        }
                                        Spacer()
                                    }
                                    .padding(8)
                                }
                            } else {
                                // Flipbook implementation with external chevrons
                                ZStack {
                                    FlipbookView(
                                        pages: flipbookPages,
                                        currentPage: $currentPage,
                                        onReady: {
                                            print("StorybookView: Flipbook ready!")
                                            flipbookReady = true
                                        },
                                        onFlip: { pageIndex in
                                            print("StorybookView: Page flipped to \(pageIndex)")
                                            currentPage = pageIndex
                                        }
                                    )
                                    .frame(width: bookSize.width, height: bookSize.height)
                                    
                                    // Debug overlay (remove in production)
                                    VStack {
                                        HStack {
                                            Text("Flipbook: \(flipbookReady ? "Ready" : "Loading")")
                                                .font(.caption)
                                                .padding(4)
                                                .background(flipbookReady ? Color.green.opacity(0.8) : Color.orange.opacity(0.8))
                                                .foregroundColor(.white)
                                                .cornerRadius(4)
                                            Spacer()
                                        }
                                        Spacer()
                                    }
                                    .padding(8)
                                    
                                    // Outside chevrons (similar to OpenBookView)
                                    if flipbookPages.count > 1 {
                                        HStack {
                                            arrowButton(system: "chevron.left",
                                                        disabled: currentPage == 0,
                                                        accessibility: "Previous page") {
                                                if currentPage > 0 {
                                                    hapticFeedback()
                                                    withAnimation(.easeInOut(duration: 0.25)) {
                                                        currentPage -= 1
                                                    }
                                                }
                                            }

                                            Spacer(minLength: 0)

                                            arrowButton(system: "chevron.right",
                                                        disabled: currentPage >= flipbookPages.count - 1,
                                                        accessibility: "Next page") {
                                                if currentPage < flipbookPages.count - 1 {
                                                    hapticFeedback()
                                                    withAnimation(.easeInOut(duration: 0.25)) {
                                                        currentPage += 1
                                                    }
                                                }
                                            }
                                        }
                                        .frame(width: bookSize.width + Tokens.chevronSize * 0.8, height: bookSize.height)
                                    }
                                }
                                .onAppear {
                                    print("StorybookView: Flipbook view appeared")
                                    // Set a timeout to fallback if flipbook doesn't load
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { // Increased timeout
                                        if !flipbookReady {
                                            print("StorybookView: Flipbook timeout - falling back to native")
                                            useFallback = true
                                        }
                                    }
                                }
                            }

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
    
    // MARK: - Helper Functions
    private func hapticFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func arrowButton(system: String,
                             disabled: Bool,
                             accessibility: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Tokens.paper.opacity(0.85))
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: Tokens.shadow.opacity(0.4), radius: 2, x: 0, y: 1)

                Image(systemName: system)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Tokens.ink.opacity(disabled ? 0.35 : 0.7))
            }
            .frame(width: Tokens.chevronSize, height: Tokens.chevronSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
        .accessibilityLabel(accessibility)
    }
}

// MARK: - Preview
struct StorybookView_Previews: PreviewProvider {
    static var previews: some View {
        StorybookView()
            .environmentObject(ProfileViewModel())
    }
}
