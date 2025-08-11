import SwiftUI
import PhotosUI
import RevenueCat
import RevenueCatUI

struct OnboardingColorTheme {
    let softCream = Color(red: 253/255, green: 234/255, blue: 198/255)
    let terracotta = Color(red: 210/255, green: 112/255, blue: 45/255)
    let warmGreen = Color(red: 169/255, green: 175/255, blue: 133/255)
    let deepGreen = Color(red: 39/255, green: 60/255, blue: 34/255)
    let fadedGray = Color(red: 233/255, green: 204/255, blue: 158/255)
    let tileBackground = Color(red: 255/255, green: 241/255, blue: 213/255)
    
    // New design colors
    let beige = Color(red: 0.98, green: 0.94, blue: 0.86) // Same as app background
    let orange = Color(red: 0.83, green: 0.45, blue: 0.14) // Same orange as app
    let white = Color.white
    let overlay = Color.black.opacity(0.3)
}

struct OnboardingFlow: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var attHelper = ATTHelper.shared
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject private var iCloudManager: iCloudManager

    // User type selection
    @State private var userType: UserType?
    @State private var currentScreen = 0
    @State private var showPaywall = false

    // User data collection
    @State private var profileImage: UIImage?
    @State private var userName: String = ""
    @State private var selectedDate = Calendar.current.date(from: DateComponents(year: 1960, month: 1, day: 1)) ?? Date()
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var memoirMotivations: [String] = []
    
    // Color theme
    private let colors = OnboardingColorTheme()

    // Animation states
    @State private var showContent = false
    @State private var progressAnimation = 0.0

    enum UserType: String, CaseIterable {
        case gift = "gift"
        case personal = "personal"

        var totalScreens: Int {
            return 8 // 0 (selection) + 7 content screens
        }
    }

    var body: some View {
        ZStack {
            colors.softCream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Only show progress bar after the 5 intro slides
                if currentScreen >= 5 {
                    progressBar
                }

                TabView(selection: $currentScreen) {
                    userTypeSelectionScreen.tag(0)
                    screen1.tag(1)
                    screen2.tag(2)
                    profileSetupScreen.tag(3)
                    birthdayScreen.tag(4)
                    /*
                    motivationScreen.tag(5)
                    notificationScreen.tag(6)
                    completionScreen.tag(7)
                    */
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.5), value: currentScreen)
                .ignoresSafeArea() // <-- ADD THIS LINE
            }
        }
        .fullScreenCover(isPresented: $showPaywall, onDismiss: {
            // Mark locally and in Cloud when paywall closes
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding_local")
            UserDefaults.standard.synchronize()
            iCloudManager.completeOnboarding()
            dismiss()
        }) {
            Group {
                if RCSubscriptionManager.shared.offerings?.current?.availablePackages.isEmpty == false {
                    PaywallView(displayCloseButton: true)
                        .onAppear {
                            // 🎯 Track paywall view for Facebook ad attribution
                            FacebookAnalytics.logPaywallViewed()
                        }
                } else {
                    // Fallback view when paywall can't load
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("Subscription Temporarily Unavailable")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Please try again later or contact support.")
                            .multilineTextAlignment(.center)
                        
                        Button("Close") {
                            showPaywall = false
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(Color.white)
                }
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                showContent = true
            }
        }
        .onChange(of: currentScreen) { _ in
            updateProgress()
        }
    }

    // MARK: - Progress Bar
    private var progressBar: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(colors.fadedGray.opacity(0.5))
                        .frame(height: 4)

                    Rectangle()
                        .fill(colors.terracotta)
                        .frame(width: geometry.size.width * progressAnimation, height: 4)
                        .animation(.easeInOut(duration: 0.5), value: progressAnimation)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Screen 0: User Type Selection (NEW 5-SLIDE DESIGN)
    private var userTypeSelectionScreen: some View {
        // The content is now the main view
        VStack(spacing: 0) {
            Spacer()
            
            // Main content area
            VStack(spacing: 24) {
                // Title and subtitle
                VStack(spacing: 12) {
                    Text("Welcome to Memoir")
                        .font(.customSerifFallback(size: 28))
                        .fontWeight(.bold)
                        .foregroundColor(colors.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Text("Capture memories for yourself or as a heartfelt gift.")
                        .font(.body)
                        .foregroundColor(colors.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Pagination dots
                HStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(index == 0 ? colors.white : colors.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Continue button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentScreen = 1
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(colors.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(colors.orange)
                    .cornerRadius(16)
                    .shadow(color: colors.orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 50)
        }
        // The background is applied using a modifier
        .background(
            ZStack {
                Image("slideone")
                    .resizable()
                    .scaledToFill()
                
                LinearGradient(
                    colors: [
                        Color.clear,
                        colors.overlay,
                        colors.beige
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea() // This makes ONLY the background full-screen
        )
    }

    // MARK: - Screen 1: Dynamic Info Screen (NEW 5-SLIDE DESIGN)
    private var screen1: some View {
        // The content is now the main view
        VStack(spacing: 0) {
            Spacer()
            
            // Main content area
            VStack(spacing: 24) {
                // Title and subtitle
                VStack(spacing: 12) {
                    Text("Just speak — we'll capture")
                        .font(.customSerifFallback(size: 28))
                        .fontWeight(.bold)
                        .foregroundColor(colors.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Text("Answer guided prompts in your own voice, no typing needed.")
                        .font(.body)
                        .foregroundColor(colors.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Pagination dots
                HStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(index == 1 ? colors.white : colors.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Continue button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentScreen = 2
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(colors.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(colors.orange)
                    .cornerRadius(16)
                    .shadow(color: colors.orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 50)
        }
        // The background is applied using a modifier
        .background(
            ZStack {
                Image("slidetwo")
                    .resizable()
                    .scaledToFill()
                
                LinearGradient(
                    colors: [
                        Color.clear,
                        colors.overlay,
                        colors.beige
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea() // This makes ONLY the background full-screen
        )
    }

    // MARK: - Screen 2: Dynamic Info Screen (NEW 5-SLIDE DESIGN)
    private var screen2: some View {
        // The content is now the main view
        VStack(spacing: 0) {
            Spacer()
            
            // Main content area
            VStack(spacing: 24) {
                // Title and subtitle
                VStack(spacing: 12) {
                    Text("Watch your story unfold")
                        .font(.customSerifFallback(size: 28))
                        .fontWeight(.bold)
                        .foregroundColor(colors.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Text("Each recording adds a new chapter to your living memoir.")
                        .font(.body)
                        .foregroundColor(colors.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Pagination dots
                HStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(index == 2 ? colors.white : colors.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Continue button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentScreen = 3
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(colors.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(colors.orange)
                    .cornerRadius(16)
                    .shadow(color: colors.orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 50)
        }
        // The background is applied using a modifier
        .background(
            ZStack {
                Image("slidethree")
                    .resizable()
                    .scaledToFill()
                
                LinearGradient(
                    colors: [
                        Color.clear,
                        colors.overlay,
                        colors.beige
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea() // This makes ONLY the background full-screen
        )
    }

    // MARK: - Screen 3: Profile Setup (NEW 5-SLIDE DESIGN)
    private var profileSetupScreen: some View {
        // The content is now the main view
        VStack(spacing: 0) {
            Spacer()
            
            // Main content area
            VStack(spacing: 24) {
                // Title and subtitle
                VStack(spacing: 12) {
                    Text("From voice to keepsake")
                        .font(.customSerifFallback(size: 28))
                        .fontWeight(.bold)
                        .foregroundColor(colors.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Text("AI turns recordings into a beautiful book — print or digital.")
                        .font(.body)
                        .foregroundColor(colors.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Pagination dots
                HStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(index == 3 ? colors.white : colors.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Continue button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentScreen = 4
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(colors.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(colors.orange)
                    .cornerRadius(16)
                    .shadow(color: colors.orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 50)
        }
        // The background is applied using a modifier
        .background(
            ZStack {
                Image("slidefour")
                    .resizable()
                    .scaledToFill()
                
                LinearGradient(
                    colors: [
                        Color.clear,
                        colors.overlay,
                        colors.beige
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea() // This makes ONLY the background full-screen
        )
    }

    // MARK: - Screen 4: Birthday (NEW 5-SLIDE DESIGN)
    private var birthdayScreen: some View {
        // The content is now the main view
        VStack(spacing: 0) {
            Spacer()
            
            // Main content area
            VStack(spacing: 24) {
                // Title and subtitle
                VStack(spacing: 12) {
                    Text("Continue your story now")
                        .font(.customSerifFallback(size: 28))
                        .fontWeight(.bold)
                        .foregroundColor(colors.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Text("Share video-books with your family and keep the legacy alive.")
                        .font(.body)
                        .foregroundColor(colors.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Pagination dots
                HStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(index == 4 ? colors.white : colors.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Continue button
                Button(action: {
                    // Complete onboarding and go to the app
                    completeOnboarding()
                    
                    // 🎯 Track onboarding completion for Facebook
                    FacebookAnalytics.logOnboardingCompleted()
                    
                    // 🎯 Request ATT permission before paywall for optimal ad attribution
                    if attHelper.shouldShowATTPrompt {
                        attHelper.requestTrackingPermission()
                        // Small delay to let ATT prompt complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showPaywall = true
                        }
                    } else {
                        showPaywall = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("Continue")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(colors.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(colors.orange)
                    .cornerRadius(16)
                    .shadow(color: colors.orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 50)
        }
        // The background is applied using a modifier
        .background(
            ZStack {
                Image("slidefive")
                    .resizable()
                    .scaledToFill()
                
                LinearGradient(
                    colors: [
                        Color.clear,
                        colors.overlay,
                        colors.beige
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea() // This makes ONLY the background full-screen
        )
    }

    // MARK: - Screen 5: Motivation (ORIGINAL FUNCTIONALITY)
    private var motivationScreen: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 80))
                    .foregroundColor(colors.terracotta)
                    .scaleEffect(showContent ? 1.0 : 0.8)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: showContent)
                
                Text("Why Create a Memoir?")
                    .font(.customSerifFallback(size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(colors.deepGreen)
            }
            
            VStack(spacing: 16) {
                motivationOption(
                    icon: "book.closed.fill",
                    text: "Document my life story",
                    value: "document_life_story"
                )
                motivationOption(
                    icon: "gift.fill",
                    text: "Create a book for my family",
                    value: "family_book"
                )
                motivationOption(
                    icon: "person.2.circle.fill",
                    text: "Answer questions for family",
                    value: "family_questions"
                )
                motivationOption(
                    icon: "heart.text.square.fill",
                    text: "Preserve memories",
                    value: "preserve_memories"
                )
            }
            .padding(.horizontal, 32)
            
            Text("Select all that apply. This helps us understand what matters most to you.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(colors.deepGreen.opacity(0.7))
                .padding(.horizontal, 32)
            
            Spacer()
            
            modernContinueButton(
                action: { nextScreen() },
                isEnabled: !memoirMotivations.isEmpty
            )
        }
    }
    
    // MARK: - Screen 6: Notifications (ORIGINAL FUNCTIONALITY)
    private var notificationScreen: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 80))
                    .foregroundColor(colors.terracotta)
                
                Text("Stay Connected to Your Stories")
                    .font(.customSerifFallback(size: 28))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(colors.deepGreen)
                    .padding(.horizontal, 24)
            }
            
            VStack(spacing: 24) {
                notificationFeature(
                    icon: "calendar.badge.plus",
                    title: "Daily story prompts"
                )
                
                notificationFeature(
                    icon: "clock.badge",
                    title: "Weekly progress reminders"
                )
                
                notificationFeature(
                    icon: "party.popper.fill",
                    title: "Milestone celebrations"
                )
            }
            .padding(.horizontal, 32)
            
            Text("We'll never spam you—just gentle nudges to help you build your legacy.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(colors.deepGreen.opacity(0.7))
                .padding(.horizontal, 40)
            
            Spacer()
            
            modernContinueButton(
                title: "Enable Notifications",
                action: {
                    notificationManager.requestPermission()
                    nextScreen()
                }
            )
        }
    }
    
    // MARK: - Screen 7: Completion (ORIGINAL FUNCTIONALITY)
    private var completionScreen: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: (userType == .gift) ? "gift.circle.fill" : "book.fill")
                    .font(.system(size: 80))
                    .foregroundColor(colors.warmGreen)

                Text(screen5Title)
                    .font(.customSerifFallback(size: 26))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(colors.deepGreen)
                    .padding(.horizontal, 24)

                Text(screen5Subtitle)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(colors.deepGreen.opacity(0.7))
                    .padding(.horizontal, 32)
            }

            socialProofView()

            Spacer()

            modernContinueButton(
                title: screen5ButtonTitle,
                action: {
                    // Mark onboarding complete immediately so next launch skips it
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding_local")
                    UserDefaults.standard.synchronize()
                    completeOnboarding()
                    
                    // 🎯 Track onboarding completion for Facebook
                    FacebookAnalytics.logOnboardingCompleted()
                    
                    // 🎯 Request ATT permission before paywall for optimal ad attribution
                    if attHelper.shouldShowATTPrompt {
                        attHelper.requestTrackingPermission()
                        // Small delay to let ATT prompt complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showPaywall = true
                        }
                    } else {
                        showPaywall = true
                    }
                }
            )
        }
    }

    // MARK: - Dynamic Content Properties
    private var screen5Title: String {
        guard let userType = userType else { return "Start your Memoir" }
        if userType == .gift {
            return "A gift they'll treasure forever"
        } else {
            return "Start your Memoir"
        }
    }

    private var screen5Subtitle: String {
        guard let userType = userType else { return "You've lived an incredible story. Let's start capturing it—one voice note at a time." }
        if userType == .gift {
            return "This isn't just another gift—it's a way to preserve a voice, a personality, a legacy. Start capturing their story today."
        } else {
            return "You've lived an incredible story. Let's start capturing it—one voice note at a time."
        }
    }

    private var screen5ButtonTitle: String {
        guard let userType = userType else { return "Start My Memoir" }
        if userType == .gift {
            return "Start Their Memoir"
        } else {
            return "Start My Memoir"
        }
    }

    // MARK: - Helper Views
    private func motivationOption(icon: String, text: String, value: String) -> some View {
        Button(action: {
            if memoirMotivations.contains(value) {
                memoirMotivations.removeAll { $0 == value }
            } else {
                memoirMotivations.append(value)
            }
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(memoirMotivations.contains(value) ? .white : colors.terracotta)
                    .frame(width: 24)
                
                Text(text)
                    .font(.body)
                    .foregroundColor(memoirMotivations.contains(value) ? .white : colors.deepGreen)
                
                Spacer()
            }
            .padding(16)
            .background(memoirMotivations.contains(value) ? colors.terracotta : colors.tileBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colors.terracotta.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private func notificationFeature(icon: String, title: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(colors.terracotta)
                .frame(width: 30)
            
            Text(title)
                .font(.body)
                .foregroundColor(colors.deepGreen)
            
            Spacer()
        }
    }

    private func socialProofView() -> some View {
        return VStack(spacing: 16) {
            Text("Trusted by families everywhere")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(colors.terracotta)

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(0..<5) { _ in
                        Image(systemName: "star.fill")
                            .foregroundColor(colors.terracotta)
                            .font(.caption)
                    }
                }
                Text("Preserving stories that matter")
                    .font(.caption)
                    .foregroundColor(colors.deepGreen)
            }
        }
        .padding()
        .background(Color.white.opacity(0.6))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }

    private func modernContinueButton(title: String = "Continue", action: @escaping () -> Void, isEnabled: Bool = true) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isEnabled ? colors.terracotta : colors.fadedGray
            )
            .cornerRadius(16)
            .shadow(color: isEnabled ? colors.terracotta.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .disabled(!isEnabled)
        .padding(.horizontal, 24)
        .scaleEffect(isEnabled ? 1.0 : 0.95)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }

    // MARK: - Helper Functions
    private func nextScreen() {
        withAnimation(.easeInOut(duration: 0.5)) {
            currentScreen += 1
        }
    }

    private func updateProgress() {
        // For the new flow: 5 intro slides only
        // Progress should count all 5 slides
        let totalScreens = 5
        
        withAnimation(.easeInOut(duration: 0.5)) {
            progressAnimation = Double(currentScreen) / Double(totalScreens)
        }
    }
    
    private func completeOnboarding() {
        iCloudManager.completeOnboarding()
    }
}

// MARK: - Preview
#Preview {
    OnboardingFlow()
        .environmentObject(ProfileViewModel())
        .environmentObject(iCloudManager.shared)
        .onTapGesture(count: 3) {
            // Triple tap to reset onboarding for testing
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            print("🔄 Onboarding reset for testing")
        }
}
