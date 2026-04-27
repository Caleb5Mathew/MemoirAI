import SwiftUI
import RevenueCat
import RevenueCatUI
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices

// ArtStyle Enum - ensure this is defined once globally or is accessible.
enum ArtStyle: String, CaseIterable, Identifiable {
    case realistic = "Realistic"
    case comic = "Comic"
    case kidsBook = "Kid's Book"
    case custom = "Custom"
    
    var id: String { self.rawValue }
    
    var placeholderSymbolName: String {
        switch self {
        case .realistic: return "photo.artframe"
        case .comic: return "book.pages"
        case .kidsBook: return "book.closed.fill"
        case .custom: return "wand.and.stars.inverse"
        }
    }
}

enum GeminiImageModelOption: String, CaseIterable, Identifiable {
    case gemini3ProPreview = "gemini-3-pro-image-preview"
    case gemini25FlashImage = "gemini-2.5-flash-image"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini3ProPreview:
            return "Gemini 3 Pro Preview"
        case .gemini25FlashImage:
            return "Gemini 2.5 Flash"
        }
    }
}

enum StyleReferencePreset: String, CaseIterable, Identifiable {
    case normal = "normal"
    case ref1 = "ref1"
    case ref2 = "ref2"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal:
            return "Normal"
        case .ref1:
            return "Ref 1"
        case .ref2:
            return "Ref 2"
        }
    }
}

// MARK: - Circular Progress Ring
struct CircularProgressRing: View {
    let progress: Double // 0.0 to 1.0 (1.0 = full allowance remaining)
    let lineWidth: CGFloat
    let size: CGFloat
    
    // Orange/Yellow gradient colors
    private let gradientColors = [
        Color(red: 1.0, green: 0.6, blue: 0.2),  // Orange
        Color(red: 1.0, green: 0.8, blue: 0.3),  // Yellow-orange
        Color(red: 1.0, green: 0.55, blue: 0.1)  // Deep orange
    ]
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    Color.gray.opacity(0.15),
                    lineWidth: lineWidth
                )
            
            // Progress ring with gradient
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: gradientColors),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
        }
        .frame(width: size, height: size)
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var subscriptionManager: RCSubscriptionManager
    @EnvironmentObject var profileVM: ProfileViewModel
    
    // Colors
    let softCream = Color(red: 0.98, green: 0.96, blue: 0.89)
    let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    let darkText = Color.black.opacity(0.85)
    
    // Settings States
    @AppStorage("memoirPageCount") var pageCountSetting: Int = 2
    @AppStorage("memoirArtStyle") private var selectedArtStyleRawValue: String = ArtStyle.kidsBook.rawValue
    @AppStorage("memoirCustomArtStyleText") private var customArtStyleText: String = ""
    @AppStorage("memoirMemorySource") var memorySourceSetting: String = "all"
    @AppStorage("memoirGeminiModelOverride") private var geminiModelOverrideRawValue: String = GeminiImageModelOption.gemini3ProPreview.rawValue
    @AppStorage("memoirStyleReferencePreset") private var styleReferencePresetRawValue: String = StyleReferencePreset.normal.rawValue
    
    @State private var sliderPageCount: Double = 2.0
    
    // Developer Key
    @State private var devKey: String = ""
    @State private var showDevSheet: Bool = false
    @State private var devResult: DevUnlockResult? = nil
    @State private var devTapCount: Int = 0
    
    // Paywall
    @State private var showPaywall: Bool = false
    
    // Character Management
    @State private var showCharacterManagement: Bool = false
    @State private var showDevDashboard: Bool = false
    @State private var hasUnseenOrders = false
    @State private var orderBadgeListener: ListenerRegistration?
    @State private var showLibrary = false
    
    private enum DevUnlockResult {
        case success
        case incorrect
    }
    
    private var currentSelectedArtStyle: ArtStyle {
        ArtStyle(rawValue: selectedArtStyleRawValue) ?? .kidsBook
    }

    private var isInternalDeveloperBuild: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }

    private var canAccessDeveloperGeminiToggle: Bool {
        isInternalDeveloperBuild && subscriptionManager.isDeveloperUnlocked
    }

    private var canAccessDevDashboard: Bool {
        subscriptionManager.isDeveloperUnlocked
    }

    private var isSubscribed: Bool {
        subscriptionManager.hasActiveSubscription
    }
    
    private var maxAllowance: Int {
        isSubscribed ? 100 : FreePreviewConfig.maxPagesWithoutSubscription
    }
    
    // For free users, limit to what they have remaining (minimum 1 to prevent slider crash)
    private var maxSelectablePages: Int {
        if isSubscribed {
            return max(1, subscriptionManager.remainingAllowance)
        } else {
            // Minimum 1 to prevent slider range crash (1...0 is invalid)
            return max(1, FreePreviewConfig.freeImagesRemaining)
        }
    }
    
    // Actual remaining images (works for both subscribed and free users)
    private var actualRemainingImages: Int {
        isSubscribed ? subscriptionManager.remainingAllowance : FreePreviewConfig.freeImagesRemaining
    }
    
    // Whether user can generate at all
    private var canGenerate: Bool {
        isSubscribed ? subscriptionManager.remainingAllowance > 0 : FreePreviewConfig.canGenerateFreePreview
    }
    
    // Progress for the ring (remaining / total)
    private var allowanceProgress: Double {
        let total = Double(maxAllowance)
        let remaining = Double(actualRemainingImages)
        guard total > 0 else { return 1.0 }
        return remaining / total
    }
    
    private func clampPageCountIfNeeded() {
        if pageCountSetting > maxSelectablePages {
            pageCountSetting = maxSelectablePages
            sliderPageCount = Double(maxSelectablePages)
        }
    }
    
    var body: some View {
        ZStack {
            softCream
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Usage Ring Card
                        usageCard
                        
                        // Page Count Section
                        pageCountSection
                        
                        // Art Style Section
                        artStyleSection

                        // Developer-only model override
                        if canAccessDeveloperGeminiToggle {
                            geminiModelSection
                        }
                        
                        // Memory Source Section
                        memorySourceSection
                        
                        // Characters Section
                        charactersSection
                        
                        // Account Section
                        accountSection

                        // Developer dashboard entry at the very bottom
                        if canAccessDevDashboard {
                            devDashboardSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            sliderPageCount = Double(pageCountSetting)
            clampPageCountIfNeeded()
            // Temporarily only Kid's Book is offered in Art Style; keep storage aligned.
            selectedArtStyleRawValue = ArtStyle.kidsBook.rawValue
            if !canAccessDeveloperGeminiToggle {
                geminiModelOverrideRawValue = GeminiImageModelOption.gemini3ProPreview.rawValue
            }
            // UI tests pass -uitesting; auto-show dev sheet to skip 5-tap
            if ProcessInfo.processInfo.arguments.contains("-uitesting") {
                showDevSheet = true
            }
            loadOrderBadge()
        }
        .onDisappear {
            orderBadgeListener?.remove()
        }
        .onChange(of: subscriptionManager.hasActiveSubscription) { _, _ in
            clampPageCountIfNeeded()
        }
        .sheet(isPresented: $showDevSheet) {
            devUnlockSheet
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(displayCloseButton: true)
        }
        .sheet(isPresented: $showCharacterManagement) {
            CharacterManagementView()
                .environmentObject(profileVM)
        }
        .fullScreenCover(isPresented: $showDevDashboard) {
            NavigationStack {
                DevDashboardView()
            }
        }
        .fullScreenCover(isPresented: $showLibrary) {
            StorybookGalleryView(onBookSelected: nil)
                .environmentObject(profileVM)
        }
    }
    
    // MARK: - Dev Unlock Sheet
    private var devUnlockSheet: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "key.fill")
                .font(.system(size: 32))
                .foregroundColor(.gray.opacity(0.4))
            
            Text("Developer Access")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
            
            SecureField("Enter key", text: $devKey)
                .font(.system(size: 15))
                .accessibilityIdentifier("devPasswordField")
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal, 40)
            
            // Result message
            if let result = devResult {
                HStack(spacing: 6) {
                    Image(systemName: result == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(result == .success ? "Unlocked!" : "Incorrect")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(result == .success ? .green : .red)
                .transition(.opacity.combined(with: .scale))
            }
            
            Button(action: {
                if devKey == "Apologist123!" {
                    RCSubscriptionManager.shared.enablePersistentDevMode()
                    withAnimation { devResult = .success }
                    devKey = ""
                    // Auto dismiss after success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showDevSheet = false
                        devResult = nil
                    }
                } else {
                    withAnimation { devResult = .incorrect }
                    // Clear incorrect message after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation { devResult = nil }
                    }
                }
            }) {
                Text("Unlock")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 120)
                    .padding(.vertical, 12)
                    .background(devKey.isEmpty ? Color.gray.opacity(0.3) : terracotta)
                    .cornerRadius(10)
            }
            .accessibilityIdentifier("devUnlockButton")
            .disabled(devKey.isEmpty)
            
            Spacer()
            Spacer()
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .onDisappear {
            devKey = ""
            devResult = nil
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(darkText)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("settingsBack")
            
            Spacer()
            
            Text("Settings")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundColor(darkText)
                .accessibilityIdentifier("settingsHeaderTitle")
            
            Spacer()
            
            Color.clear
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .onTapGesture {
                    devTapCount += 1
                    if devTapCount >= 5 {
                        showDevSheet = true
                        devTapCount = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if devTapCount < 5 { devTapCount = 0 }
                    }
                }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
    
    // MARK: - Usage Card with Ring
    private var usageCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                // Circular Progress Ring
                ZStack {
                    CircularProgressRing(
                        progress: allowanceProgress,
                        lineWidth: 10,
                        size: 90
                    )
                    
                    VStack(spacing: 2) {
                        if isSubscribed {
                            Text("\(subscriptionManager.remainingAllowance)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(darkText)
                            Text("left")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                        } else {
                            // Show ACTUAL remaining free preview images
                            Text("\(FreePreviewConfig.freeImagesRemaining)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(FreePreviewConfig.freeImagesRemaining > 0 ? darkText : .red)
                            Text(FreePreviewConfig.freeImagesRemaining > 0 ? "left" : "images")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Usage Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(isSubscribed ? "Image Allowance" : "Free Preview")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(darkText)
                    
                    if isSubscribed {
                        Text("\(subscriptionManager.remainingAllowance) of 100 images")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        Text("Resets \(subscriptionManager.getRenewalDateString())")
                            .font(.system(size: 12))
                            .foregroundColor(.gray.opacity(0.8))
                    } else {
                        // Show actual remaining for free users
                        let remaining = FreePreviewConfig.freeImagesRemaining
                        let total = FreePreviewConfig.maxPagesWithoutSubscription
                        
                        if remaining > 0 {
                            Text("\(remaining) of \(total) free images left")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        } else {
                            Text("Free preview used")
                                .font(.system(size: 14))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        
                        Text("Subscribe for 100 images / month")
                            .font(.system(size: 12))
                            .foregroundColor(terracotta)
                    }
                }
                
                Spacer()
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.6))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Page Count Section
    private var pageCountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Memories to Generate")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(darkText)
            
            HStack(spacing: 10) {
                Text("\(pageCountSetting)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(canGenerate ? terracotta : .gray)
                    .frame(width: 36, alignment: .center)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: pageCountSetting)
                
                Slider(value: $sliderPageCount, in: 1...Double(max(2, maxSelectablePages)), step: 1)
                    .tint(canGenerate ? terracotta : .gray)
                    .disabled(!canGenerate || maxSelectablePages <= 1)
                    .onChange(of: sliderPageCount) { _, newValue in
                        pageCountSetting = Int(newValue)
                    }
                
                Text("\(maxSelectablePages)")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            .opacity(canGenerate ? 1.0 : 0.5)
            
            // Warning if exceeding allowance (subscribed users)
            if isSubscribed && pageCountSetting > subscriptionManager.remainingAllowance {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Exceeds remaining allowance")
                        .font(.system(size: 12))
                }
                .foregroundColor(.red.opacity(0.8))
                .padding(.top, 4)
            }
            
            // Warning for free users who have exhausted their preview
            if !isSubscribed && !canGenerate {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.7))
                    
                    Text("No images left. ")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    + Text("Subscribe")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                    + Text(" to continue")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .padding(.top, 4)
                .onTapGesture {
                    showPaywall = true
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.6))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Art Style Section
    private var artStyleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Art Style")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(darkText)

            // Temporarily only Kid's Book — restore grid below when re-enabling other styles.
            ArtStyleChip(
                style: .kidsBook,
                isSelected: true,
                accentColor: terracotta
            ) {
                selectedArtStyleRawValue = ArtStyle.kidsBook.rawValue
            }
            .frame(maxWidth: .infinity)

            /*
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ArtStyle.allCases) { style in
                    ArtStyleChip(
                        style: style,
                        isSelected: currentSelectedArtStyle == style,
                        accentColor: terracotta
                    ) {
                        selectedArtStyleRawValue = style.rawValue
                    }
                }
            }
            */

            // Custom style input (hidden while only Kid's Book is offered)
            /*
            if currentSelectedArtStyle == .custom {
                TextField("Describe your style...", text: $customArtStyleText, axis: .vertical)
                    .font(.system(size: 14))
                    .padding(12)
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .lineLimit(1...3)
                    .tint(terracotta)
                    .padding(.top, 4)
            }
            */
        }
        .padding(20)
        .background(Color.white.opacity(0.6))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.2), value: currentSelectedArtStyle)
    }

    private var styleReferenceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Style Reference")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(darkText)

            Picker("Style reference", selection: $styleReferencePresetRawValue) {
                ForEach(StyleReferencePreset.allCases) { preset in
                    Text(preset.displayName).tag(preset.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text("When enabled, Gemini receives an additional style image reference. Use this for more consistent kids-book styling across pages.")
                .font(.system(size: 12))
                .foregroundColor(.gray)

            if currentSelectedArtStyle != .kidsBook {
                Text("Tip: This has the strongest effect with Kid's Book style.")
                    .font(.system(size: 12))
                    .foregroundColor(.gray.opacity(0.85))
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.6))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Memory Source Section
    private var geminiModelSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Developer: Gemini Model")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(darkText)

            Picker("Gemini model", selection: $geminiModelOverrideRawValue) {
                ForEach(GeminiImageModelOption.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text("Default users always use Gemini 3 Pro Preview. This override is only active in developer mode.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(20)
        .background(Color.white.opacity(0.6))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: - Memory Source Section
    private var memorySourceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Memory Source")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(darkText)
            
            Picker("Source", selection: $memorySourceSetting) {
                Text("All").tag("all")
                Text("Chapters").tag("memoir")
                Text("Recordings").tag("recordings")
            }
            .pickerStyle(.segmented)
            
            Text("Choose which memories to include when generating your book")
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .padding(.top, 4)
        }
        .padding(20)
        .background(Color.white.opacity(0.6))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Characters Section
    private var charactersSection: some View {
        Button(action: {
            showCharacterManagement = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(terracotta.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(terracotta)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("My Characters")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(darkText)
                    
                    Text("Manage characters across memories")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(16)
            .background(Color.white.opacity(0.6))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    /// Opens My Library (`StorybookGalleryView`) for ordering prints from saved books. Uses full-screen cover so it works when Settings is a sheet (no `NavigationStack` in parent).
    private var printOrdersLibraryRow: some View {
        Button {
            showLibrary = true
        } label: {
            HStack {
                Image(systemName: "shippingbox")
                    .font(.system(size: 14))
                Text("Print Orders")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                if hasUnseenOrders {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
            }
            .foregroundColor(terracotta)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Account Section
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(darkText)
            
            if let user = Auth.auth().currentUser {
                if user.isAnonymous {
                    // Anonymous user - show link option
                    HStack(spacing: 12) {
                        Circle()
                            .fill(terracotta.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(terracotta)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Syncing Anonymously")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(darkText)
                            
                            Text("Link Google to access on other devices")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Sync indicator
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green.opacity(0.7))
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    printOrdersLibraryRow

                    SignInWithAppleButton(.signIn) { request in
                        request.nonce = AuthenticationService.shared.prepareAppleSignIn()
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                            Task { await linkAppleAccount(credential: credential) }
                        case .failure(let error):
                            print("❌ Apple sign-in failed: \(error.localizedDescription)")
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button(action: linkGoogleAccount) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 22, height: 22)
                                Text("G")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                            Text("Link Google Account")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.95))
                        .foregroundColor(Color.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    developerModeRow
                } else {
                    // Signed in with Google
                    HStack(spacing: 12) {
                        Circle()
                            .fill(terracotta.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(String((user.displayName ?? user.email ?? "U").prefix(1)).uppercased())
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(terracotta)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName ?? "User")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(darkText)
                            
                            Text(user.email ?? "")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green.opacity(0.7))
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    printOrdersLibraryRow
                    
                    Button(action: signOut) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 14))
                            Text("Sign Out")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.red.opacity(0.8))
                    }
                    
                    developerModeRow
                }
            } else {
                // Not signed in yet (loading)
                HStack(spacing: 12) {
                    ProgressView()
                        .frame(width: 44, height: 44)
                    
                    Text("Connecting...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(darkText)
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.6))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var developerModeRow: some View {
        Button {
            showDevSheet = true
        } label: {
            HStack {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 14))
                Text("Developer Mode")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.gray.opacity(0.6))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Dev Dashboard Section
    private var devDashboardSection: some View {
        Button(action: {
            showDevDashboard = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.24, green: 0.67, blue: 0.92).opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "gauge.open.with.lines.needle.33percent")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.19, green: 0.56, blue: 0.84))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Dev Dashboard")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(darkText)
                    Text("Costs, telemetry, reconciliation")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(16)
            .background(Color.white.opacity(0.6))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func linkGoogleAccount() {
        Task {
            do {
                try await AuthenticationService.shared.linkGoogleAccount()
            } catch {
                print("❌ Link failed: \(error)")
            }
        }
    }

    private func linkAppleAccount(credential: ASAuthorizationAppleIDCredential) async {
        do {
            try await AuthenticationService.shared.linkAppleAccount(credential: credential)
        } catch {
            print("❌ Link Apple failed: \(error)")
        }
    }
    
    private func loadOrderBadge() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        orderBadgeListener?.remove()
        orderBadgeListener = OrderService.shared.ordersListener(userId: userId) { orders in
            hasUnseenOrders = OrderService.hasUnseenStatusUpdate(orders: orders)
        }
    }

    private func signOut() {
        do {
            try AuthenticationService.shared.signOut()
        } catch {
            print("❌ Sign out failed: \(error)")
        }
    }
    
}

// MARK: - Art Style Chip
struct ArtStyleChip: View {
    let style: ArtStyle
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: style.placeholderSymbolName)
                    .font(.system(size: 16))
                
                Text(style.rawValue)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : Color.black.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? accentColor : Color.white.opacity(0.8))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accentColor : Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("artStyle_\(style.rawValue)")
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// Keep existing ArtStyleButton for backward compatibility
struct ArtStyleButton: View {
    let style: ArtStyle
    let isSelected: Bool
    
    let selectedBorderColor: Color
    let selectedBackgroundColor: Color
    let defaultBackgroundColor: Color
    let defaultBorderColor: Color
    let selectedTextColor: Color
    let defaultTextColor: Color
    let selectedSymbolColor: Color
    let defaultSymbolColor: Color
    
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? selectedBackgroundColor : defaultBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? selectedBorderColor : defaultBorderColor, lineWidth: isSelected ? 2.5 : 1.5)
                    )
                    .aspectRatio(1.0, contentMode: .fit)
                
                VStack {
                    Spacer()
                    
                    Image(systemName: style.placeholderSymbolName)
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(isSelected ? selectedSymbolColor : defaultSymbolColor)
                        .padding(.bottom, 5)
                    
                    Text(style.rawValue)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(isSelected ? selectedTextColor : defaultTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                }
                .padding(8)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}

// MARK: - Settings View With Generate Button
struct SettingsViewWithGenerate: View {
    let onGenerate: () -> Void
    
    @EnvironmentObject var subscriptionManager: RCSubscriptionManager
    @EnvironmentObject var profileVM: ProfileViewModel
    
    let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    let softCream = Color(red: 0.98, green: 0.96, blue: 0.89)
    
    var body: some View {
        ZStack {
            SettingsView()
                .environmentObject(subscriptionManager)
                .environmentObject(profileVM)
            
            VStack {
                Spacer()
                
                Button(action: onGenerate) {
                    Text("Save & Generate")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(terracotta)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("saveAndGenerateButton")
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .background(
                    LinearGradient(
                        colors: [Color.clear, softCream.opacity(0.9), softCream],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 110)
                )
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView()
        }
    }
}
