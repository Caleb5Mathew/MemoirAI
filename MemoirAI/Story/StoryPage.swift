import SwiftUI
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
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = StoryPageViewModel() // Your actual ViewModel from StoryPageViewModel.swift
    @EnvironmentObject var profileVM: ProfileViewModel // Ensure this is passed in

    // Access the shared instance of RCSubscriptionManager
    @StateObject private var subscriptionManager = RCSubscriptionManager.shared

    let localColors = StoryPageLocalColors() // Now this should be found

    @State private var currentImageIndex = 0
    @State private var showSettings = false
    @State private var selectedImageForFullScreen: UIImage? = nil
    @State private var hasRequestedGeneration = false // To track if user initiated generation

    // Progress simulation
    @State private var fakeProgress: Double = 0
    @State private var realProgress: Double = 0 // Tracks vm.progress
    @State private var cancellableTimer: AnyCancellable?

    @State private var showSubscriptionSheet = false // New state for paywall sheet

    // MARK: - Developer Access State
    @State private var isDeveloperAuthenticated: Bool = false // Set to true for direct access during dev if needed
    @State private var passwordAttempt: String = ""
    @State private var showPasswordError: Bool = false
    private let developerPassword = "Apologist123!" // Keep this secure or use a better auth method

    private var displayProgress: Double {
        if realProgress > 0.05 && realProgress > fakeProgress {
            return realProgress
        }
        return max(fakeProgress, realProgress)
    }
    
    @ViewBuilder
    private func storybookContentView(bookFrameWidth: CGFloat, bookContentHeightInsideFrame: CGFloat) -> some View {
        // IF LOADING
        if vm.isLoading {
            VStack(spacing: 12) {
                ProgressView(value: displayProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: localColors.terracotta))
                    .frame(height: 6)
                    .padding(.horizontal, 40)
                    .animation(.linear(duration: 0.1), value: displayProgress)

                Text("\(Int(displayProgress * 100))%")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(localColors.defaultGray)
            }
        // IF ERROR
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
        // IF IMAGES AVAILABLE (after generation)
        } else if hasRequestedGeneration && !vm.images.isEmpty {
             ZStack {
                TabView(selection: $currentImageIndex) {
                    ForEach(vm.images.indices, id: \.self) { idx in
                        Image(uiImage: vm.images[idx])
                            .resizable()
                            .aspectRatio(contentMode: .fill) // Changed to .fill to better fit frame
                            .frame(width: bookFrameWidth * 0.9, height: bookContentHeightInsideFrame) // Ensure this size is appropriate
                            .clipped()
                            .cornerRadius(8)
                            .tag(idx)
                            .onTapGesture {
                                selectedImageForFullScreen = vm.images[idx]
                            }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: bookFrameWidth * 0.9, height: bookContentHeightInsideFrame)
                .clipShape(RoundedRectangle(cornerRadius: 10)) // Clip the TabView

                if vm.images.count > 1 {
                    HStack {
                        Button(action: {
                            if currentImageIndex > 0 {
                                withAnimation(.easeInOut) { currentImageIndex -= 1 }
                            }
                        }) {
                            Image(systemName: "arrow.left.circle.fill")
                                .shadow(radius: 3)
                        }
                        .disabled(currentImageIndex == 0)
                        .opacity(currentImageIndex == 0 ? 0.3 : 1.0)

                        Spacer()

                        Button(action: {
                            if currentImageIndex < vm.images.count - 1 {
                                withAnimation(.easeInOut) { currentImageIndex += 1 }
                            }
                        }) {
                            Image(systemName: "arrow.right.circle.fill")
                                .shadow(radius: 3)
                        }
                        .disabled(currentImageIndex == vm.images.count - 1)
                        .opacity(currentImageIndex == vm.images.count - 1 ? 0.3 : 1.0)
                    }
                    .font(.system(size: 40, weight: .thin))
                    .foregroundColor(localColors.arrowColor)
                    .padding(.horizontal, bookFrameWidth * 0.02) // Adjust padding relative to content
                    .frame(width: bookFrameWidth * 0.95) // Align with content width
                }
            }
            .frame(width: bookFrameWidth * 0.9, height: bookContentHeightInsideFrame) // Central frame for content
        // INITIAL STATE
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
                    generateStorybookWithPaywallCheck()
                }) {
                    Text("Create My Storybook")
                        .font(.headline)
                        .foregroundColor(localColors.defaultWhite)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(localColors.terracotta)
                        .clipShape(Capsule())
                        .shadow(color: localColors.terracotta.opacity(0.4), radius: 5, y: 3)
                }
                .disabled(vm.isLoading)
                .padding(.top, 10)
            }
            .padding()
        }
    }
    
    // MARK: - Developer Password Entry Screen
    @ViewBuilder
    private func passwordEntryScreenView() -> some View {
        ZStack {
            localColors.softCream.ignoresSafeArea()
            VStack(spacing: 25) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(localColors.terracotta.opacity(0.8))

                Text("Developer Access Required")
                    .font(.storyPageSerifFont(size: 24))
                    .fontWeight(.semibold)
                    .foregroundColor(localColors.defaultBlack.opacity(0.85))

                Text("Enter the password to continue.")
                    .font(.system(size: 16))
                    .foregroundColor(localColors.defaultGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                SecureField("Password", text: $passwordAttempt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 40)
                    .frame(maxWidth: 300)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit(attemptDeveloperLogin)

                if showPasswordError {
                    Text("Incorrect password. Please try again.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(localColors.defaultRed)
                        .padding(.horizontal, 40)
                }

                Button(action: attemptDeveloperLogin) {
                    Text("Unlock Access")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: 280)
                        .background(localColors.terracotta)
                        .cornerRadius(12)
                        .shadow(color: localColors.terracotta.opacity(0.5), radius: 5, y: 3)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Text("Go Back")
                        .font(.subheadline)
                        .foregroundColor(localColors.defaultGray)
                }
                .padding(.bottom, 20)
            }
            .padding()
        }
    }

    var body: some View {
        if isDeveloperAuthenticated { // Or some other flag like !featureFlags.isPasswordProtectionEnabled
            NavigationStack {
                ZStack {
                    localColors.softCream
                        .ignoresSafeArea()
                        .overlay(
                            Image("paper_texture") // Make sure this image exists in your assets
                                .resizable()
                                .scaledToFill()
                                .opacity(0.05)
                                .ignoresSafeArea()
                        )

                    VStack(spacing: 0) { // Reduced spacing for tighter layout
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
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(localColors.defaultBlack.opacity(0.7))
                                    .padding(10)
                                    .background(localColors.subtleControlBackground)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, (UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0) + 5) // Adjust for safe area
                        .padding(.bottom, 10)

                        GeometryReader { geo in
                            let bookFrameWidth = geo.size.width * 0.92 // Slightly smaller frame
                            let bookContentAreaWidth = bookFrameWidth * 0.92 // Content area within frame
                            let bookContentHeightInsideFrame = bookContentAreaWidth * (9.0 / 16.0) // 16:9 aspect ratio for content
                            let bookFrameVerticalPadding: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 30 : 20 // Padding inside book frame
                            let bookFrameHeight = bookContentHeightInsideFrame + (bookFrameVerticalPadding * 2)


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
                                .frame(width: bookContentAreaWidth, height: bookContentHeightInsideFrame)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity) // Let ZStack center itself
                            .position(x: geo.size.width / 2, y: geo.size.height / 2) // Center in GeometryReader
                        }
                        // Spacer(minLength: 20) // Removed or adjusted depending on desired bottom space
                    }
                    .padding(.bottom, (UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 0) + 5) // Adjust for bottom safe area
                }
                .navigationBarHidden(true)
                .sheet(isPresented: $showSettings) {
                    SettingsView() // Ensure SettingsView is defined (placeholder below)
                        .environmentObject(profileVM)
                        .environmentObject(subscriptionManager) // Pass if settings needs it
                }
                .sheet(isPresented: $showSubscriptionSheet) {
                    PaywallViewRepresentable() // Your actual Paywall View
                        .environmentObject(subscriptionManager)
                        .onAppear { Task { await subscriptionManager.loadOfferings() } }
                }
                .overlay(FullScreenImageView(selectedImage: $selectedImageForFullScreen, colors: localColors)) // This should now be found
                .onAppear {
                    print("StoryPage (Authenticated) appeared. Profile: \(profileVM.selectedProfile.name ?? "N/A")")
                    Task { await subscriptionManager.refreshCustomerInfo() }
                }
                .onChange(of: profileVM.selectedProfile.id) {
                    print("StoryPage detected profile change. Clearing state.")
                    resetGenerationState()
                }
                .onChange(of: vm.progress) { newApiProgress in
                     if vm.isLoading {
                         if newApiProgress > 0.01 {
                             if fakeProgress < 0.5 && newApiProgress < 0.8 { fakeProgress = max(fakeProgress, 0.1 + newApiProgress * 0.4) }
                             cancellableTimer?.cancel()
                             realProgress = newApiProgress
                             if realProgress >= 1.0 { realProgress = 1.0 }
                         }
                     }
                 }
                .onChange(of: vm.isLoading) { isLoading in
                    if !isLoading {
                        cancellableTimer?.cancel()
                        if vm.errorMessage == nil && !vm.images.isEmpty {
                            if displayProgress < 1.0 { realProgress = 1.0; fakeProgress = 1.0 }
                        } else {
                            if vm.errorMessage != nil || (vm.images.isEmpty && hasRequestedGeneration) {
                                fakeProgress = 0
                                realProgress = 0
                            }
                        }
                    } else {
                        fakeProgress = 0
                        realProgress = 0
                        vm.progress = 0
                    }
                }
            }
        } else {
            passwordEntryScreenView()
                .onAppear {
                    print("StoryPage password screen appeared.")
                    passwordAttempt = ""
                    showPasswordError = false
                }
        }
    }

    private func resetGenerationState() {
        vm.images = []
        vm.errorMessage = nil
        currentImageIndex = 0
        fakeProgress = 0
        realProgress = 0
        vm.progress = 0
        cancellableTimer?.cancel()
        vm.isLoading = false
        hasRequestedGeneration = false
    }

    private func attemptDeveloperLogin() {
        if passwordAttempt == developerPassword {
            withAnimation { isDeveloperAuthenticated = true }
            showPasswordError = false
            passwordAttempt = ""
        } else {
            showPasswordError = true
            passwordAttempt = ""
        }
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
}

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

// MARK: - SettingsView Placeholder (Replace with your actual SettingsView)


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
