import SwiftUI
import PhotosUI

// MARK: - Color Theme (matching app)
struct OnboardingColorTheme {
    let softCream = Color(red: 253/255, green: 234/255, blue: 198/255)
    let terracotta = Color(red: 210/255, green: 112/255, blue: 45/255)
    let warmGreen = Color(red: 169/255, green: 175/255, blue: 133/255)
    let deepGreen = Color(red: 39/255, green: 60/255, blue: 34/255)
    let fadedGray = Color(red: 233/255, green: 204/255, blue: 158/255)
    let tileBackground = Color(red: 255/255, green: 241/255, blue: 213/255)
}

struct OnboardingFlow: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationManager = NotificationManager.shared
    @EnvironmentObject var profileVM: ProfileViewModel
    
    // Color theme
    private let colors = OnboardingColorTheme()
    
    // Screen management
    @State private var currentScreen = 1
    private let totalScreens = 7
    
    // User data collection
    @State private var profileImage: UIImage?
    @State private var userName: String = ""
    @State private var selectedDate = Calendar.current.date(from: DateComponents(year: 1960, month: 1, day: 1)) ?? Date()
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var memoirMotivations: [String] = []
    
    // Animation states
    @State private var showContent = false
    @State private var progressAnimation = 0.0
    
    var body: some View {
        ZStack {
            // Background
            colors.softCream
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress Bar
                progressBar
                
                // Content
                TabView(selection: $currentScreen) {
                    welcomeScreen.tag(1)
                    howItWorksScreen.tag(2)
                    notificationScreen.tag(3)
                    profileSetupScreen.tag(4)
                    motivationScreen.tag(5)
                    birthdayScreen.tag(6)
                    completionScreen.tag(7)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.5), value: currentScreen)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                showContent = true
            }
            updateProgress()
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
    
    // MARK: - Screen 1: Welcome
    private var welcomeScreen: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 80))
                    .foregroundColor(colors.terracotta)
                    .scaleEffect(showContent ? 1.0 : 0.8)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: showContent)
                
                VStack(spacing: 12) {
                    Text("Welcome to")
                        .font(.customSerifFallback(size: 24))
                        .foregroundColor(colors.warmGreen)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.8).delay(0.2), value: showContent)
                    
                    Text("Memoir")
                        .font(.customSerifFallback(size: 42))
                        .fontWeight(.bold)
                        .foregroundColor(colors.deepGreen)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.8).delay(0.4), value: showContent)
                    
                    Text("Your voice. Your legacy.")
                        .font(.customSerifFallback(size: 20))
                        .foregroundColor(colors.terracotta)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.8).delay(0.6), value: showContent)
                }
                
                Text("Transform your life stories into a beautiful memoir for future generations. No typing required—just share your memories naturally.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(colors.deepGreen.opacity(0.7))
                    .padding(.horizontal, 32)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.8).delay(0.8), value: showContent)
            }
            
            Spacer()
            
            modernContinueButton(action: { nextScreen() })
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.8).delay(1.0), value: showContent)
        }
    }
    
    // MARK: - Screen 2: How It Works
    private var howItWorksScreen: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Text("How Memoir Works")
                .font(.customSerifFallback(size: 32))
                .fontWeight(.bold)
                .foregroundColor(colors.deepGreen)
            
            VStack(spacing: 32) {
                howItWorksStep(
                    icon: "calendar.badge.plus",
                    number: "1",
                    title: "DAILY OR WEEKLY PROMPTS",
                    description: "Answer thoughtful prompts at your own pace"
                )
                
                howItWorksStep(
                    icon: "book.fill",
                    number: "2",
                    title: "ORGANIZED CHAPTERS OF YOUR LIFE",
                    description: "Your stories are beautifully organized by life stages"
                )
                
                howItWorksStep(
                    icon: "person.2.fill",
                    number: "3",
                    title: "SHARE WITH FAMILY AND LOVED ONES",
                    description: "Create lasting memories for future generations"
                )
            }
            .padding(.horizontal, 24)
            
            Text("It's that simple.")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(colors.terracotta)
            
            Spacer()
            
            modernContinueButton(action: { nextScreen() })
        }
    }
    
    // MARK: - Screen 3: Notifications
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
    
    // MARK: - Screen 4: Profile Setup
    private var profileSetupScreen: some View {
        VStack(spacing: 40) {
            Spacer()
            
            profileSetupHeader
            
            VStack(spacing: 32) {
                profilePhotoSection
                profileNameSection
            }
            
            Spacer()
            
            modernContinueButton(action: { nextScreen() })
        }
    }
    
    // MARK: - Profile Setup Components
    private var profileSetupHeader: some View {
        Text("Make a Profile")
            .font(.customSerifFallback(size: 28))
            .fontWeight(.bold)
            .foregroundColor(colors.deepGreen)
    }
    
    private var profilePhotoSection: some View {
        VStack(spacing: 16) {
            profilePhotoView
            
            Text("Add Your Photo")
                .font(.headline)
                .foregroundColor(colors.deepGreen)
            
            Text("Help family connect with your stories")
                .font(.subheadline)
                .foregroundColor(colors.warmGreen)
                .multilineTextAlignment(.center)
        }
    }
    
    private var profilePhotoView: some View {
        Group {
            if let image = profileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(colors.terracotta, lineWidth: 3)
                    )
                    .onTapGesture {
                        // Allow retaking photo
                    }
            } else {
                profilePhotoPicker
            }
        }
    }
    
    private var profilePhotoPicker: some View {
        PhotosPicker(selection: $photoPickerItem, matching: .images) {
            ZStack {
                Circle()
                    .fill(colors.fadedGray.opacity(0.3))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                            .foregroundColor(colors.terracotta)
                    )
                
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(colors.terracotta)
                    Text("Add Photo")
                        .font(.caption)
                        .foregroundColor(colors.terracotta)
                }
            }
        }
        .onChange(of: photoPickerItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    profileImage = image
                }
            }
        }
    }
    
    private var profileNameSection: some View {
        VStack(spacing: 16) {
            Text("What Should We Call You?")
                .font(.headline)
                .foregroundColor(colors.deepGreen)
            
            TextField("Grandma, Dad, Mom, etc.", text: $userName)
                .font(.body)
                .foregroundColor(colors.deepGreen)
                .padding(16)
                .background(colors.tileBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colors.terracotta.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 24)
            
            Text("This helps us personalize your memoir and makes it feel more intimate.")
                .font(.caption)
                .foregroundColor(colors.warmGreen)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
    
    // MARK: - Screen 5: Motivation
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
    
    // MARK: - Screen 6: Birthday
    private var birthdayScreen: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 80))
                    .foregroundColor(colors.terracotta)
                
                Text("When Were You Born?")
                    .font(.customSerifFallback(size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(colors.deepGreen)
                
                Text("This helps us create a timeline of your life")
                    .font(.body)
                    .foregroundColor(colors.deepGreen.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 24) {
                // Date Picker
                DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(WheelDatePickerStyle())
                    .labelsHidden()
                    .foregroundColor(colors.deepGreen)
                    .colorScheme(.light)
                    .frame(height: 120)
                    .background(colors.tileBackground)
                    .cornerRadius(12)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            modernContinueButton(
                action: { nextScreen() },
                isEnabled: true
            )
        }
    }
    
    // MARK: - Screen 7: Completion
    private var completionScreen: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(colors.warmGreen)
                    .scaleEffect(showContent ? 1.0 : 0.8)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: showContent)
                
                Text("Welcome to Memoir!")
                    .font(.customSerifFallback(size: 28))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(colors.deepGreen)
                
                Text("You're all set up and ready to start preserving your memories.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(colors.deepGreen.opacity(0.7))
                    .padding(.horizontal, 32)
            }
            
            VStack(spacing: 20) {
                Text("What's Next:")
                    .font(.headline)
                    .foregroundColor(colors.deepGreen)
                
                VStack(spacing: 16) {
                    nextStepItem(icon: "calendar.badge.plus", text: "Answer your first story prompt")
                    nextStepItem(icon: "book.fill", text: "Explore story chapters")
                    nextStepItem(icon: "person.2.fill", text: "Invite family members")
                }
                .padding(.horizontal, 32)
            }
            
            Spacer()
            
            modernContinueButton(
                title: "Start My Memoir",
                action: {
                    completeOnboarding()
                }
            )
        }
    }
    
    // MARK: - Helper Views
    private func howItWorksStep(icon: String, number: String, title: String, description: String) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(colors.terracotta)
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(colors.deepGreen)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(colors.deepGreen.opacity(0.7))
            }
            
            Spacer()
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
    
    private func nextStepItem(icon: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(colors.terracotta)
                .frame(width: 24)
            
            Text(text)
                .font(.body)
                .foregroundColor(colors.deepGreen)
            
            Spacer()
        }
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
            if currentScreen < totalScreens {
                currentScreen += 1
            }
        }
    }
    
    private func updateProgress() {
        withAnimation(.easeInOut(duration: 0.5)) {
            progressAnimation = Double(currentScreen) / Double(totalScreens)
        }
    }
    
    private func completeOnboarding() {
        // Create profile with onboarding data
        let profileName = userName.isEmpty ? "My Profile" : userName
        var profileImageData: Data? = nil
        
        if let image = profileImage {
            profileImageData = image.jpegData(compressionQuality: 0.8)
        }
        
        let newProfile = Profile(name: profileName, photoData: profileImageData)
        
        // Clear any existing default profiles and add the new one
        profileVM.profiles.removeAll()
        profileVM.addProfile(newProfile)
        
        // Save additional user data
        UserDefaults.standard.set(selectedDate, forKey: "userBirthday")
        UserDefaults.standard.set(Calendar.current.component(.year, from: selectedDate), forKey: "userBirthYear")
        
        if !userName.isEmpty {
            UserDefaults.standard.set(userName, forKey: "userName")
        }
        
        if !memoirMotivations.isEmpty {
            UserDefaults.standard.set(memoirMotivations, forKey: "memoirMotivations")
        }
        
        // Schedule notifications
        notificationManager.scheduleDailyPrompt()
        notificationManager.scheduleWeeklyReminder()
        
        // Mark onboarding as completed
        hasCompletedOnboarding = true
        
        // Dismiss onboarding
        dismiss()
    }
}

#Preview {
    OnboardingFlow()
        .environmentObject(ProfileViewModel())
        .onTapGesture(count: 3) {
            // Triple tap to reset onboarding for testing
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            print("🔄 Onboarding reset for testing")
        }
} 
