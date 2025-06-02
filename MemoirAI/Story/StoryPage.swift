//import SwiftUI
//import Combine // Required for Timer.publish
//
//// Define colors directly in this file since ColorTheme is not found
//struct StoryPageLocalColors { // Renamed to avoid potential conflicts
//    let softCream = Color(red: 0.98, green: 0.96, blue: 0.89)
//    let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
//    let defaultBlack = Color.black
//    let defaultGray = Color.gray
//    let defaultRed = Color.red
//    let defaultWhite = Color.white
//    let arrowColor = Color.white.opacity(0.9) // For arrows
//    let subtleControlBackground = Color.black.opacity(0.07) // For button backgrounds
//    let shadowColor = Color.black.opacity(0.15) // For shadows
//    let bookFrameFill = Color.white.opacity(0.55) // Slightly more opaque book frame
//    let bookFrameStroke = Color.gray.opacity(0.4)  // Slightly more opaque stroke
//    let fullScreenOverlayBackground = Color.black.opacity(0.85) // For full screen image
//}
//
//// Helper for custom serif-like font
//extension Font {
//    static func storyPageSerifFont(size: CGFloat) -> Font {
//        .system(size: size, design: .serif)
//    }
//}
//
//
//struct StoryPage: View {
//    let localColors = StoryPageLocalColors()
//
//    var body: some View {
//        ZStack {
//            localColors.softCream
//                .ignoresSafeArea()
//
//            VStack(spacing: 8) {
//                Image(systemName: "book.fill")
//                    .font(.system(size: 36))
//                    .foregroundColor(localColors.terracotta.opacity(0.8))
//
//                Text("Coming Soon!")
//                    .font(.title3)                    // smaller than largeTitle
//                    .fontWeight(.semibold)
//                    .foregroundColor(localColors.defaultBlack.opacity(0.85))
//
//                Text("Stay tuned for updates")
//                    .font(.footnote)
//                    .foregroundColor(localColors.defaultGray)
//                    .opacity(0.7)
//            }
//            .padding(.horizontal, 24)
//            .padding(.vertical, 32)
//            .background(localColors.defaultWhite.opacity(0.6))
//            .cornerRadius(12)
//            .shadow(color: localColors.shadowColor, radius: 6, x: 0, y: 3)
//        }
//    }
//}
//
//
//
//// ... (FullScreenImageView, StoryPage_Previews, and Placeholder ViewModels remain the same)
//// Make sure your placeholder ViewModels (StoryPageViewModel, ProfileViewModel, SettingsView) are available
//// from the previous implementation for the preview to work. I'm assuming they are present below.
//
//struct FullScreenImageView: View {
//    @Binding var selectedImage: UIImage?
//    let colors: StoryPageLocalColors
//
//    var body: some View {
//        if let image = selectedImage {
//            ZStack {
//                colors.fullScreenOverlayBackground
//                    .ignoresSafeArea()
//                    .onTapGesture {
//                        withAnimation(.easeInOut(duration: 0.3)) {
//                            selectedImage = nil
//                        }
//                    }
//
//                VStack {
//                    Spacer()
//                    Image(uiImage: image)
//                        .resizable()
//                        .scaledToFit()
//                        .cornerRadius(16)
//                        .padding(30)
//                        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
//                    Spacer()
//                    Button(action: {
//                        withAnimation(.easeInOut(duration: 0.3)) {
//                            selectedImage = nil
//                        }
//                    }) {
//                        Text("Close")
//                            .font(.headline)
//                            .padding(.horizontal, 24)
//                            .padding(.vertical, 12)
//                            .background(Color.white.opacity(0.9))
//                            .foregroundColor(colors.terracotta)
//                            .cornerRadius(12)
//                            .shadow(radius: 3)
//                    }
//                    .padding(.bottom, 40)
//                }
//            }
//            .transition(.opacity.combined(with: .scale(scale: 0.95)))
//            .animation(.easeInOut(duration: 0.3), value: selectedImage != nil)
//        }
//    }
//}
//
//
//struct StoryPage_Previews: PreviewProvider {
//    static var previews: some View {
//        let dummyProfileVM = ProfileViewModel()
//        StoryPage()
//            .environmentObject(dummyProfileVM)
//    }
//}



import SwiftUI
import PhotosUI
import Combine // Required for Timer.publish
// Import RevenueCat if you need to access its types directly here, though RCSubscriptionManager encapsulates most of it.
// import RevenueCat

// Ensure RCSubscriptionManager is defined and accessible (likely in its own file RCSubscriptionManager.swift)
// Ensure ProfileViewModel is defined and accessible
// Ensure StoryPageViewModel is defined and accessible (in StoryPageViewModel.swift)

// MARK: - Color Definitions
struct StoryPageLocalColors {
    let softCream = Color(red: 0.98, green: 0.96, blue: 0.89)
    let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    let defaultBlack = Color.black
    let defaultGray = Color.gray
    let defaultRed = Color.red
    let defaultWhite = Color.white
    let arrowColor = Color.white.opacity(0.9) // For arrows
    let subtleControlBackground = Color.black.opacity(0.07) // For button backgrounds
    let shadowColor = Color.black.opacity(0.15) // For shadows
    let bookFrameFill = Color.white.opacity(0.55) // Slightly more opaque book frame
    let bookFrameStroke = Color.gray.opacity(0.4)  // Slightly more opaque stroke
    let fullScreenOverlayBackground = Color.black.opacity(0.85) // For full screen image
}

// MARK: - Font Helper
extension Font {
    static func storyPageSerifFont(size: CGFloat) -> Font {
        .system(size: size, design: .serif)
    }
}

struct StoryPage: View {
    @State private var headshotImage: UIImage?            // stores the picked headshot
    @State private var grandparentName: String = ""       // stores the typed-in name
    @State private var showProfileSetup: Bool = false     // toggles the sheet
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = StoryPageViewModel()
    
    @State private var headshotPickerItem: PhotosPickerItem?
    
    @EnvironmentObject var profileVM: ProfileViewModel // Ensure this is passed in
    
    // Access the shared instance of RCSubscriptionManager
    @StateObject private var subscriptionManager = RCSubscriptionManager.shared
    
    let localColors = StoryPageLocalColors() // Now this should be found
    
    @State private var currentPageIndex = 0
    
    @State private var showSettings = false
    @State private var selectedImageForFullScreen: UIImage? = nil
    @State private var hasRequestedGeneration = false // To track if user initiated generation
    
    // Progress simulation
    @State private var fakeProgress: Double = 0
    @State private var realProgress: Double = 0 // Tracks vm.progress
    @State private var cancellableTimer: AnyCancellable?
    
    @State private var showSubscriptionSheet = false // New state for paywall sheet
    
    private var displayProgress: Double {
        if realProgress > 0.05 && realProgress > fakeProgress {
            return realProgress
        }
        return max(fakeProgress, realProgress)
    }
    @ViewBuilder
    private func storybookContentView(
        bookFrameWidth: CGFloat,
        bookContentHeightInsideFrame: CGFloat
    ) -> some View {
        let stripHeight = bookContentHeightInsideFrame * 0.20

        // LOADING STATE
        if vm.isLoading {
            VStack(spacing: 12) {
                ProgressView(value: displayProgress)
                    .progressViewStyle(
                        LinearProgressViewStyle(tint: localColors.terracotta)
                    )
                    .frame(height: 6)
                    .padding(.horizontal, 40)
                    .animation(.linear(duration: 0.1), value: displayProgress)

                Text("\(Int(displayProgress * 100))%")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(localColors.defaultGray)
            }

        // ERROR STATE
        } else if let error = vm.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(localColors.defaultRed.opacity(0.7))
                Text("Oh no! \(error)")
                    .font(.storyPageSerifFont(size: 16))
                    .multilineTextAlignment(.center)
                    .foregroundColor(localColors.defaultRed)
                    .padding(.horizontal, 5)
                Button("Try Creating Again") {
                    generateStorybookWithPaywallCheck()
                }
                .font(.headline)
                .foregroundColor(localColors.terracotta)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(localColors.terracotta.opacity(0.15))
                .cornerRadius(10)
            }
            .padding(20)

        // CONTENT STATE (images + text pages)
        } else if hasRequestedGeneration && !vm.pageItems.isEmpty {
            ZStack {
                TabView(selection: $currentPageIndex) {
                    ForEach(vm.pageItems.indices, id: \.self) { idx in
                        switch vm.pageItems[idx] {
                        case .illustration(let image, let caption):
                            IllustrationPage(
                                image: image,
                                caption: caption,
                                frameWidth: bookFrameWidth * 0.9,
                                frameHeight: bookContentHeightInsideFrame
                            )
                            .tag(idx)
                            .onTapGesture {
                                selectedImageForFullScreen = image
                            }
                        case .textPage(let index, let total, let text):
                            TextPageView(
                                index: index,
                                total: total,
                                text: text,
                                frameWidth: bookFrameWidth * 0.9,
                                frameHeight: bookContentHeightInsideFrame
                            )
                            .tag(idx)
                        case .qrCode(_, let url):
                            QRCodePage(
                                url: url,
                                frameWidth: bookFrameWidth * 0.9,
                                frameHeight: bookContentHeightInsideFrame
                            )
                            .tag(idx)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(
                    width: bookFrameWidth * 0.9,
                    height: bookContentHeightInsideFrame
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Page navigation arrows
                if vm.pageItems.count > 1 {
                    HStack {
                        Button {
                            if currentPageIndex > 0 {
                                withAnimation(.easeInOut) { currentPageIndex -= 1 }
                            }
                        } label: {
                            Image(systemName: "arrow.left.circle.fill")
                                .shadow(radius: 3)
                        }
                        .disabled(currentPageIndex == 0)
                        .opacity(currentPageIndex == 0 ? 0.3 : 1.0)

                        Spacer()

                        Button {
                            if currentPageIndex < vm.pageItems.count - 1 {
                                withAnimation(.easeInOut) { currentPageIndex += 1 }
                            }
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .shadow(radius: 3)
                        }
                        .disabled(currentPageIndex == vm.pageItems.count - 1)
                        .opacity(currentPageIndex == vm.pageItems.count - 1 ? 0.3 : 1.0)
                    }
                    .font(.system(size: 40, weight: .thin))
                    .foregroundColor(localColors.arrowColor)
                    .padding(.horizontal, bookFrameWidth * 0.02)
                    .frame(width: bookFrameWidth * 0.95)
                }
            }
            .frame(
                width: bookFrameWidth * 0.9,
                height: bookContentHeightInsideFrame
            )

        // INITIAL PROMPT STATE
        } else {
            VStack(spacing: 12) {
                Text("Your storybook awaits!")
                    .font(.storyPageSerifFont(size: 18))
                    .foregroundColor(localColors.defaultBlack.opacity(0.9))
                Text("Tap below to bring this profile's memories to life.")
                    .font(.system(size: 14))
                    .foregroundColor(localColors.defaultGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Button(action: {
                    showProfileSetup = true
                }) {
                    Text("Create My Storybook")
                        .font(.headline)
                        .foregroundColor(localColors.defaultWhite)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(localColors.terracotta)
                        .clipShape(Capsule())
                        .shadow(
                            color: localColors.terracotta.opacity(0.4),
                            radius: 5, y: 3
                        )
                }
                .disabled(vm.isLoading)
                .padding(.top, 10)
            }
            .padding()
        }
    }

    private func resetGenerationState() {
        vm.images = []
        vm.errorMessage = nil
        currentPageIndex = 0        // ← renamed
        fakeProgress = 0
        realProgress = 0
        vm.progress = 0
        cancellableTimer?.cancel()
        vm.isLoading = false
        hasRequestedGeneration = false
    }

        
        private func generateStorybookWithPaywallCheck() {
            let pagesToAttempt = vm.expectedPageCount()
            
            guard pagesToAttempt > 0 else {
                print("StoryPage: Attempting to generate 0 pages. Aborting.")
                vm.errorMessage = "Please select a valid number of pages to generate."
                return
            }
            
            if subscriptionManager.canGenerate(pages: pagesToAttempt) {
                print("StoryPage: Check successful. Proceeding with generation of \(pagesToAttempt) pages.")
                startActualGenerationProcess(pagesExpected: pagesToAttempt)
            } else {
                print("StoryPage: Usage limit hit/no plan. Tier: \(subscriptionManager.activeTier?.displayName ?? "None"), Rem: \(subscriptionManager.remainingAllowance), Req: \(pagesToAttempt)")
                vm.isLoading = false
                hasRequestedGeneration = false
                showSubscriptionSheet = true
            }
        }
        
        private func startActualGenerationProcess(pagesExpected: Int) {
            resetGenerationState()
            hasRequestedGeneration = true
            vm.isLoading = true
            
            let fakeIncrementPerTick = 0.004
            let targetFakeProgress = 0.4
            
            cancellableTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { _ in
                if fakeProgress < targetFakeProgress && !Task.isCancelled {
                    fakeProgress += fakeIncrementPerTick
                    if fakeProgress >= targetFakeProgress {
                        fakeProgress = targetFakeProgress
                        cancellableTimer?.cancel()
                    }
                } else {
                    cancellableTimer?.cancel()
                }
            }
            
            let currentProfileID = profileVM.selectedProfile.id
            Task {
                await vm.generateStorybook(forProfileID: currentProfileID)
                
                await MainActor.run {
                    cancellableTimer?.cancel()
                    
                    if vm.errorMessage == nil && !vm.images.isEmpty {
                        let actualPagesGenerated = vm.images.count
                        if actualPagesGenerated > 0 {
                            subscriptionManager.consume(pages: actualPagesGenerated)
                            print("StoryPage: Consumed \(actualPagesGenerated) pages.")
                        }
                        self.realProgress = 1.0
                        self.fakeProgress = 1.0
                    } else {
                        print("StoryPage: Gen failed/no images. Error: \(vm.errorMessage ?? "N/A").")
                        self.realProgress = 0.0
                        self.fakeProgress = 0.0
                    }
                    if vm.isLoading { print("Warning: vm.isLoading is still true post-generation.")}
                }
            }
        }
    // ← right after your `startActualGenerationProcess` method’s closing `}`

    var body: some View {
        NavigationStack {
            ZStack {
                localColors.softCream
                    .ignoresSafeArea()
                    .overlay(
                        Image("paper_texture")
                            .resizable()
                            .scaledToFill()
                            .opacity(0.05)
                            .ignoresSafeArea()
                    )

                VStack(spacing: 0) {
                    // HEADER
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(localColors.defaultBlack.opacity(0.7))
                                .padding(10)
                                .background(localColors.subtleControlBackground)
                                .clipShape(Circle())
                        }
                        Spacer()
                        Text("Your Storybook")
                            .font(.storyPageSerifFont(size: 22))
                            .fontWeight(.medium)
                            .foregroundColor(localColors.defaultBlack.opacity(0.8))
                        Spacer()
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(localColors.defaultBlack.opacity(0.7))
                                .padding(10)
                                .background(localColors.subtleControlBackground)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 5)
                    .padding(.bottom, 10)

                    // STORYBOOK CONTENT
                    GeometryReader { geo in
                        let bookFrameWidth = geo.size.width * 0.92
                        let bookContentAreaWidth = bookFrameWidth * 0.92
                        let bookContentHeightInsideFrame = bookContentAreaWidth * (9.0 / 16.0)
                        let verticalPad: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 30 : 20
                        let bookFrameHeight = bookContentHeightInsideFrame + (verticalPad * 2)

                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(localColors.bookFrameFill)
                                .frame(width: bookFrameWidth, height: bookFrameHeight)
                                .shadow(color: localColors.shadowColor, radius: 12, x: 0, y: 6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(localColors.bookFrameStroke, lineWidth: 1.5)
                                )

                            storybookContentView(
                                bookFrameWidth: bookContentAreaWidth,
                                bookContentHeightInsideFrame: bookContentHeightInsideFrame
                            )
                            .frame(
                                width: bookContentAreaWidth,
                                height: bookContentHeightInsideFrame
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height / 2
                        )
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 5)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(profileVM)
                    .environmentObject(subscriptionManager)
            }
            .sheet(isPresented: $showSubscriptionSheet) {
                PaywallViewRepresentable()
                    .environmentObject(subscriptionManager)
                    .onAppear { Task { await subscriptionManager.loadOfferings() } }
            }
            .sheet(isPresented: $showProfileSetup, onDismiss: {
                generateStorybookWithPaywallCheck()
            }) {
                ProfileSetupView(
                    headshotImage: $headshotImage,
                    name: $grandparentName
                )
                .environmentObject(profileVM)
            }
            .overlay(
                FullScreenImageView(
                    selectedImage: $selectedImageForFullScreen,
                    colors: localColors
                )
            )
            .onAppear {
                if headshotImage == nil,
                   let test = UIImage(named: "old") {
                    headshotImage = test
                    vm.subjectPhoto = test
                }
                if vm.styleTile == nil,
                   let style = UIImage(named: "kidsref") {
                    vm.styleTile = style
                }
                Task { await subscriptionManager.refreshCustomerInfo() }
            }
            .onChange(of: profileVM.selectedProfile.id) { _ in
                resetGenerationState()
            }
            .onChange(of: vm.progress) { newApiProgress in
                // your existing progress-tracking logic
            }
            .onChange(of: vm.isLoading) { isLoading in
                // your existing loading-state logic
            }
        }
    }

} // ← Make sure this single brace closes `struct StoryPage`

    // MARK: - FullScreenImageView (Ensure this is defined)
    struct FullScreenImageView: View {
        @Binding var selectedImage: UIImage?
        let colors: StoryPageLocalColors // ensure StoryPageLocalColors is defined
        
        var body: some View {
            if let image = selectedImage {
                ZStack {
                    colors.fullScreenOverlayBackground
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedImage = nil
                            }
                        }
                    
                    VStack {
                        Spacer()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(16)
                            .padding(30)
                            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedImage = nil
                            }
                        }) {
                            Text("Close")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.9))
                                .foregroundColor(colors.terracotta) // ensure colors.terracotta is valid
                                .cornerRadius(12)
                                .shadow(radius: 3)
                        }
                        .padding(.bottom, 40)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeInOut(duration: 0.3), value: selectedImage != nil)
            }
        }
    }
    
    
    // MARK: - Placeholder for Paywall View
    struct PaywallViewRepresentable: View {
        @EnvironmentObject var subscriptionManager: RCSubscriptionManager
        @Environment(\.dismiss) var dismiss
        
        var body: some View {
            NavigationView {
                VStack(spacing: 20) {
                    Text("Unlock More Pages!")
                        .font(.largeTitle).bold()
                        .padding(.top, 40)
                    
                    if let offerings = subscriptionManager.offerings {
                        if let currentOffering = offerings.current { // Use .current for default offering
                            Text("Choose a plan to continue creating amazing storybooks:")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            ForEach(currentOffering.availablePackages) { pkg in
                                Button {
                                    Task {
                                        do {
                                            print("Paywall: Purchasing \(pkg.storeProduct.localizedTitle)")
                                            try await subscriptionManager.purchase(package: pkg)
                                            if subscriptionManager.activeTier != nil {
                                                print("Paywall: Purchase successful. Tier: \(subscriptionManager.activeTier!.displayName). Dismissing.")
                                                dismiss()
                                            } else {
                                                print("Paywall: Purchase flow done, no active tier yet.")
                                            }
                                        } catch {
                                            print("❌ Paywall: Purchase failed: \(error.localizedDescription)")
                                            // TODO: Show user-facing alert for purchase failure
                                        }
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(pkg.storeProduct.localizedTitle).font(.title2).bold()
                                        Text(pkg.storeProduct.localizedDescription).font(.subheadline).foregroundColor(.gray)
                                        Text("Price: \(pkg.storeProduct.localizedPriceString)").font(.headline)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.gray.opacity(0.15))
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))
                                }
                                .padding(.horizontal)
                            }
                        } else {
                            Text("No subscription plans currently available.")
                            Button("Refresh Plans") { Task { await subscriptionManager.loadOfferings() } }
                        }
                    } else {
                        VStack { Text("Loading plans..."); ProgressView() }
                    }
                    Spacer()
                }
                .navigationTitle("Go Premium")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) { Button("Dismiss") { dismiss() } }
                }
                .onAppear{
                    if subscriptionManager.offerings == nil {
                        Task { await subscriptionManager.loadOfferings() }
                    }
                }
            }
        }
    }
    
    // MARK: - Preview
    struct StoryPage_Previews: PreviewProvider {
        static var previews: some View {
            // Create a dummy ProfileViewModel for the preview
            let dummyProfileVM = ProfileViewModel()
            // You might want to select a default profile for the preview if your VM supports it
            // Example: dummyProfileVM.selectProfile(dummyProfileVM.profiles.first)
            
            // Create a dummy StoryPageViewModel (if needed for preview, but it's @StateObject in StoryPage)
            // let dummyStoryPageVM = StoryPageViewModel()
            
            // Create a dummy RCSubscriptionManager (if needed for preview)
            // let dummySubManager = RCSubscriptionManager.shared // This might try to init RevenueCat
            
            StoryPage()
                .environmentObject(dummyProfileVM)
            // .environmentObject(dummySubManager) // If sub manager is used in preview setup directly
            // If StoryPage directly initializes VMs with specific states for preview, do that here.
        }
    }
    // MARK: – Illustration & Text Pages
struct IllustrationPage: View {
    let image: UIImage
    let caption: String
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            // ▪︎ Full‐page image
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: frameWidth, height: frameHeight)
                .clipped()
                .cornerRadius(8)

            // ▪︎ Translucent caption banner (20% of height)
            Rectangle()
                .fill(StoryPageLocalColors().softCream.opacity(0.85))
                .frame(height: frameHeight * 0.20)
                .overlay(
                    Text(caption)
                        // ↓ Reduce font multiplier from 0.12 → 0.04 (≈ 1/3)
                        .font(.system(size: frameHeight * 0.04, weight: .light))
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)                     // allow unlimited lines
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16),
                    alignment: .leading
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct TextPageView: View {
    let index: Int
    let total: Int
    let text: String
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            // ▪︎ Background “page” styling (paper + border)
            RoundedRectangle(cornerRadius: 10)
                .fill(StoryPageLocalColors().softCream.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(StoryPageLocalColors().bookFrameStroke, lineWidth: 0.8)
                )

            // ▪︎ Scrollable text content
            ScrollView {
                Text(text)
                    // ↓ “Light serif” at ~1/3 the previous size:
                    .font(.system(
                        size: frameHeight * 0.045,
                        weight: .light,
                        design: .serif
                    ))
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
            }
            
            // ▪︎ Page index in top‐left corner
            Text("\(index)/\(total)")
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundColor(StoryPageLocalColors().defaultGray)
                .padding(8)
        }
        .frame(width: frameWidth, height: frameHeight)
    }
}
struct QRCodePage: View {
    let url: URL
    let frameWidth:  CGFloat
    let frameHeight: CGFloat

    private let colors = StoryPageLocalColors()

    var body: some View {
        VStack(spacing: 12) {
            // ▪︎ Title at top:
            Text("Hear or see your memory here")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundColor(colors.terracotta)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            // ▪︎ QR code in the middle; 40% of frameWidth
            Image(uiImage: .qrCode(
                from: url.absoluteString,
                size: frameWidth * 0.4
            ))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: frameWidth * 0.4, height: frameWidth * 0.4)
            .shadow(radius: 4)
            .padding(.vertical, 8)

            // ▪︎ URL text at bottom:
            Text(url.absoluteString)
                .font(.caption2)
                .foregroundColor(colors.defaultGray)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.bottom, 8)
        }
        .frame(width: frameWidth, height: frameHeight)
        .background(colors.softCream.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colors.bookFrameStroke, lineWidth: 0.8)
        )
    }
}
