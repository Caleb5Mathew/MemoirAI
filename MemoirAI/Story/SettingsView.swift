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

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var subscriptionManager: RCSubscriptionManager
    @EnvironmentObject var profileVM: ProfileViewModel
    @ObservedObject private var authService = AuthenticationService.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    
    // Colors
    let softCream = LinenTheme.paper
    let terracotta = LinenTheme.accent
    let darkText = LinenTheme.ink
    
    // Settings States
    @AppStorage("memoirPageCount") var pageCountSetting: Int = 2
    @AppStorage("memoirArtStyle") private var selectedArtStyleRawValue: String = ArtStyle.kidsBook.rawValue
    @AppStorage("memoirMemorySource") private var memorySourceSetting: String = "memoir"
    @AppStorage("memoirGeminiModelOverride") private var geminiModelOverrideRawValue: String = GeminiImageModelOption.gemini3ProPreview.rawValue
    @AppStorage("memoirStyleReferencePreset") private var styleReferencePresetRawValue: String = StyleReferencePreset.normal.rawValue
    
    @State private var sliderPageCount: Double = 2.0
    
    @State private var devKey: String = ""
    @State private var showDevSheet: Bool = false
    @State private var devResult: DevUnlockResult? = nil
    @State private var devTapCount: Int = 0
    @State private var showDevDashboard: Bool = false
    @State private var showDevOpsDashboard: Bool = false
    @State private var devErrorMessage: String?
    @State private var isVerifyingDevAccess = false
    
    // Paywall
    @State private var showPaywall: Bool = false
    
    // Memory enhancement
    @State private var showMemoryEnhancement: Bool = false
    @State private var hasUnseenOrders = false
    @State private var orderBadgeListener: ListenerRegistration?
    @State private var showOrderHistory = false
    @State private var showSupportCopiedAlert = false
    @State private var showAudioPrivacyAlert = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var accountDeletionError: String?
    @State private var accountDeletionRequiresReauthentication = false
    
    private enum DevUnlockResult {
        case success
        case incorrect
    }
    
    private var canAccessDeveloperGeminiToggle: Bool {
        subscriptionManager.isDeveloperUnlocked
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
            return StorybookGenerationBatchPolicy.maximumSelectablePages(
                remainingAllowance: subscriptionManager.remainingAllowance
            )
        } else {
            // Minimum 1 to prevent slider range crash (1...0 is invalid)
            return StorybookGenerationBatchPolicy.maximumSelectablePages(
                remainingAllowance: FreePreviewConfig.freeImagesRemaining
            )
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
                    VStack(spacing: 16) {
                        // Usage Ring Card
                        usageCard

                        if subscriptionManager.hasBillingIssue {
                            SubscriptionBillingNotice(hasActiveSubscription: subscriptionManager.hasActiveSubscription)
                        }
                        if !subscriptionManager.hasBillingIssue || subscriptionManager.hasActiveSubscription,
                           let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions") {
                            Link("Manage App Store subscription", destination: subscriptionsURL)
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Page Count Section
                        pageCountSection
                        
                        // Developer-only model override
                        if canAccessDeveloperGeminiToggle {
                            geminiModelSection
                        }
                        
                        // Characters Section
                        memoryEnhancementSection
                        
                        // Account Section
                        accountSection

                        // Support Section
                        supportSection

                        if canAccessDevDashboard {
                            devDashboardSection
                            printOpsDashboardSection
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                    .adaptiveContentWidth(AdaptiveLayoutPolicy.workflowMaxWidth)
                }
            }
            .adaptiveContentWidth(AdaptiveLayoutPolicy.workflowMaxWidth)

            if isDeletingAccount {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Deleting your account…")
                        .font(LinenTheme.body(16, weight: .semibold))
                    Text("Keep MemoirAI open while we remove account data and clear this device.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(32)
            }
            
        }
        .tint(LinenTheme.accent)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(isDeletingAccount)
        .onAppear {
            sliderPageCount = Double(pageCountSetting)
            clampPageCountIfNeeded()
            // Generation currently has one supported style and one supported memory source.
            // Normalize legacy choices so hidden settings cannot affect a new book.
            selectedArtStyleRawValue = ArtStyle.kidsBook.rawValue
            memorySourceSetting = "memoir"
            if !canAccessDeveloperGeminiToggle {
                geminiModelOverrideRawValue = GeminiImageModelOption.gemini3ProPreview.rawValue
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitesting") {
                showDevSheet = true
            }
            #endif
            loadOrderBadge()
        }
        .onDisappear {
            orderBadgeListener?.remove()
        }
        .onChange(of: subscriptionManager.remainingAllowance) { _, _ in
            clampPageCountIfNeeded()
        }
        .sheet(isPresented: $showDevSheet) { devUnlockSheet }
        .fullScreenCover(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
        .sheet(isPresented: $showMemoryEnhancement) {
            RecentMemoriesView(
                enhancementMode: true,
                initialMemoirMode: currentMemoirMode()
            )
                .environmentObject(profileVM)
        }
        .fullScreenCover(isPresented: $showDevDashboard) {
            NavigationStack {
                DevDashboardView()
            }
        }
        .fullScreenCover(isPresented: $showDevOpsDashboard) {
            NavigationStack {
                DevOpsDashboardView()
            }
        }
        .fullScreenCover(isPresented: $showOrderHistory) {
            OrderHistoryView()
        }
        .alert("Email Copied", isPresented: $showSupportCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("We couldn't open Mail, so we copied \(SupportContact.email) to your clipboard.")
        }
        .alert(CloudTranscriptionDisclosure.title, isPresented: $showAudioPrivacyAlert) {
            Button("Done", role: .cancel) { }
        } message: {
            Text(CloudTranscriptionDisclosure.message)
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountConfirmation) {
            Button("Delete Account", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This requests permanent deletion from your MemoirAI account and clears this device. Apple iCloud sync and offline devices may take time to update. Paid order records required for fulfillment or legal retention may remain. Deleting your account does not cancel an App Store subscription.")
        }
        .alert(
            "Account Deletion Failed",
            isPresented: Binding(
                get: { accountDeletionError != nil },
                set: { if !$0 { accountDeletionError = nil } }
            )
        ) {
            if accountDeletionRequiresReauthentication {
                Button("Sign Out and Sign In Again") {
                    accountDeletionRequiresReauthentication = false
                    accountDeletionError = nil
                    signOut()
                    dismiss()
                }
            }
            Button("OK", role: .cancel) { accountDeletionError = nil }
        } message: {
            Text(accountDeletionError ?? "Please try again.")
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
                    Text(result == .success ? "Unlocked!" : (devErrorMessage ?? "Access denied"))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(result == .success ? .green : .red)
                .transition(.opacity.combined(with: .scale))
            }
            
            Button {
                Task { await verifyDeveloperAccess() }
            } label: {
                Group {
                    if isVerifyingDevAccess {
                        ProgressView().tint(.white)
                    } else {
                        Text("Unlock")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 120)
                .padding(.vertical, 12)
                .background(devKey.isEmpty ? Color.gray.opacity(0.3) : terracotta)
                .cornerRadius(10)
            }
            .accessibilityIdentifier("devUnlockButton")
            .disabled(devKey.isEmpty || isVerifyingDevAccess)
            
            Spacer()
            Spacer()
        }
        .adaptiveSheetDetents(preferredHeight: 320)
        .presentationDragIndicator(.visible)
        .onDisappear {
            devKey = ""
            devResult = nil
            devErrorMessage = nil
            isVerifyingDevAccess = false
        }
    }

    @MainActor
    private func verifyDeveloperAccess() async {
        isVerifyingDevAccess = true
        defer { isVerifyingDevAccess = false }
        do {
            try await subscriptionManager.authorizeDeveloperAccess(devKey)
            withAnimation { devResult = .success }
            devErrorMessage = nil
            devKey = ""
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            showDevSheet = false
            devResult = nil
        } catch {
            devErrorMessage = error.localizedDescription
            withAnimation { devResult = .incorrect }
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
            
            Text("Settings")
                .font(LinenTheme.heading())
                .foregroundColor(darkText)
                .accessibilityIdentifier("settingsHeaderTitle")
            
            Spacer()
            
            Color.clear
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard DeveloperAccessDistributionPolicy.permitsCurrentBuild else { return }
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
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
    
    // MARK: - Usage Card with Ring
    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(isSubscribed ? "Your subscription" : "Free preview")
                    .font(LinenTheme.body(16, weight: .semibold))
                Spacer()
                Text(subscriptionManager.isDeveloperUnlockedSession ? "Unlimited" : "\(actualRemainingImages) left")
                    .font(LinenTheme.heading(22))
                    .foregroundColor(canGenerate ? LinenTheme.forest : LinenTheme.secondary)
            }
            ProgressView(value: min(1, max(0, allowanceProgress)))
                .tint(LinenTheme.forest)
                .accessibilityLabel("Available illustration allowance")
            if isSubscribed {
                Text(subscriptionManager.isDeveloperUnlockedSession
                     ? "Developer access"
                     : "Illustrations reset \(subscriptionManager.getRenewalDateString())")
                    .font(LinenTheme.body(14))
                    .foregroundColor(LinenTheme.secondary)
            } else {
                HStack {
                    Text("\(FreePreviewConfig.freeImagesRemaining) of \(FreePreviewConfig.maxPagesWithoutSubscription) free illustrations")
                        .font(LinenTheme.body(14))
                        .foregroundColor(LinenTheme.secondary)
                    Spacer()
                    Button("View plans") { showPaywall = true }
                        .font(LinenTheme.body(14, weight: .semibold))
                        .foregroundColor(LinenTheme.accent)
                }
            }
        }
        .foregroundColor(LinenTheme.ink)
        .padding(20)
        .background(LinenTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Page Count Section
    private var pageCountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Book length")
                .font(LinenTheme.body(16, weight: .semibold))
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

            Text("Up to \(StorybookGenerationBatchPolicy.maximumPagesPerBook) memories per book")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            
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
        .background(LinenTheme.card)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LinenTheme.line, lineWidth: 1))
    }
    
    // MARK: - Developer Model Section
    private var geminiModelSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Developer: Gemini Model")
                .font(LinenTheme.body(16, weight: .semibold))
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
        .background(LinenTheme.card)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LinenTheme.line, lineWidth: 1))
    }

    // MARK: - Memory Enhancement Section
    private var memoryEnhancementSection: some View {
        Button(action: {
            showMemoryEnhancement = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(terracotta.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18))
                        .foregroundColor(terracotta)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enhance Memories")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(darkText)
                    
                    Text("Add details for better storybook images")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(16)
            .background(LinenTheme.card)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LinenTheme.line, lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    /// Opens `OrderHistoryView` to show past/active print orders. Uses full-screen cover so it works when Settings is a sheet (no `NavigationStack` in parent).
    private var printOrdersLibraryRow: some View {
        Button {
            showOrderHistory = true
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

    // MARK: - Support Section
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            notificationSettingsRow

            Button {
                guard let privacyURL = URL(string: "https://memoirai-7db06.web.app/privacy") else { return }
                openURL(privacyURL)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised")
                        .frame(width: 22)
                    Text("Privacy Policy")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .frame(width: 16)
                }
            }

            Button {
                showAudioPrivacyAlert = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .frame(width: 22)
                    Text("Audio & Transcription Privacy")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .frame(width: 16)
                }
            }

            Button {
                SupportContact.contact { showSupportCopiedAlert = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                        .frame(width: 22)
                    Text("Contact Support")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .frame(width: 16)
                }
            }

            Text("MemoirAI keeps your memories private and gives you control over saved recordings.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.top, 2)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 6)
        .buttonStyle(.plain)
    }

    // MARK: - Account Section
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account")
                .font(LinenTheme.body(16, weight: .semibold))
                .foregroundColor(darkText)
            
            if let user = authService.user {
                if AuthenticationService.shared.isGuestUser(user) {
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
                            
                            Text("Link Apple or Google to access on other devices")
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

                    if DeveloperAccessDistributionPolicy.permitsCurrentBuild {
                        developerModeRow
                    }
                } else {
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
                    
                    if DeveloperAccessDistributionPolicy.permitsCurrentBuild {
                        developerModeRow
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                LinkedAccountsView()

                Divider().padding(.vertical, 8)

                Button(role: .destructive) {
                    showDeleteAccountConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                        Text("Delete Account")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDeletingAccount)
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
        .background(LinenTheme.card)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LinenTheme.line, lineWidth: 1))
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
            .background(LinenTheme.card)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LinenTheme.line, lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Print-order queue for Caleb. Visible only when developer-unlocked; the screen itself is
    /// authorized server-side (see `Firebase/AdminOpsService.swift`), so a non-admin who reaches it
    /// just sees a friendly explanation instead of any order data.
    private var printOpsDashboardSection: some View {
        Button(action: {
            showDevOpsDashboard = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(terracotta.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(terracotta)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Print Ops Dashboard")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(darkText)
                    Text("Review and fulfill print orders")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(16)
            .background(LinenTheme.card)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LinenTheme.line, lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var notificationSettingsRow: some View {
        let action = NotificationPermissionPolicy.action(for: notificationManager.authorizationStatus)

        return Button {
            switch action {
            case .request:
                notificationManager.requestPermission()
            case .openSettings:
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            case .none:
                break
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: action == .none ? "bell.badge" : "bell.slash")
                    .frame(width: 22)
                Text(action == .none ? "Notifications enabled" : "Enable notifications")
                Spacer()
                if action != .none {
                    Image(systemName: "arrow.up.right")
                        .frame(width: 16)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(action == .none)
        .task {
            notificationManager.refreshAuthorizationStatus()
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
        Task {
            do {
                try await AuthenticationService.shared.signOut()
            } catch {
                print("❌ Sign out failed: \(error)")
            }
        }
    }

    private func deleteAccount() {
        guard !isDeletingAccount else { return }
        guard let deletedUserID = Auth.auth().currentUser?.uid else {
            accountDeletionError = "You are not signed in."
            return
        }
        isDeletingAccount = true
        accountDeletionError = nil
        Task {
            do {
                try await AuthenticationService.shared.deleteAccount()
                profileVM.resetAfterAccountDeletion(userID: deletedUserID)
                await AuthenticationService.shared.prepareAuthenticatedSessionForLaunch()
                dismiss()
            } catch {
                if let authError = error as? AuthenticationService.AuthError,
                   case .requiresRecentLogin = authError {
                    accountDeletionRequiresReauthentication = true
                }
                accountDeletionError = error.localizedDescription
                isDeletingAccount = false
            }
        }
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
                        .font(LinenTheme.body(16, weight: .semibold))
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
