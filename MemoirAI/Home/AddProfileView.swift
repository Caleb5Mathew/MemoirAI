import SwiftUI
import PhotosUI
import RevenueCat
import RevenueCatUI

struct AddProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileVM: ProfileViewModel
    @StateObject private var subscriptionManager = RCSubscriptionManager.shared

    // Style constants
    private let headerFontSize: CGFloat = 25
    private let subHeaderFontSize: CGFloat = 21  // 3/4 of header
    private let bodyFontSize: CGFloat = 16
    private let baseBackground = LinenTheme.paper
    private var inputBackground: Color { LinenTheme.surface }

    @State private var name: String = ""
    @FocusState private var isNameFieldFocused: Bool
    @State private var photoSelection: PhotosPickerItem? = nil
    @State private var selectedPhotoData: Data? = nil
    @State private var photoLoadError: String?
    @State private var showPaywall = false
    
    // Developer unlock states
    @State private var devTapCount = 0
    @State private var showDevSheet = false
    @State private var devKey = ""
    @State private var devResult: DevUnlockResult? = nil
    @State private var devErrorMessage: String?
    @State private var isVerifyingDevAccess = false
    
    private enum DevUnlockResult {
        case success
        case incorrect
    }

    var body: some View {
        ZStack {
            baseBackground
                .ignoresSafeArea()

            GeometryReader { geometry in
                if profileVM.canCreateNewProfile {
                    profileCreationView(minHeight: geometry.size.height)
                } else {
                    subscriptionRequiredView(minHeight: geometry.size.height)
                }
            }
        }
        .onChange(of: photoSelection) { oldValue, newValue in
            guard let item = newValue else { return }
            loadPhotoData(from: item)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
        .sheet(isPresented: $showDevSheet) {
            devUnlockSheet
        }
    }

    // ✨ NEW: Subscription required view
    private func subscriptionRequiredView(minHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(LinenTheme.accent)
            
            // Title
            VStack(spacing: 12) {
                Text("Multiple Profiles")
                    .font(LinenTheme.heading(25))
                    .foregroundColor(LinenTheme.ink)
                    .fontWeight(.light)
                
                Text("Create profiles for multiple family members and keep their stories separate")
                    .font(LinenTheme.body(16))
                    .fontWeight(.light)
                    .foregroundColor(LinenTheme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Current status
            VStack(spacing: 8) {
                Text("Current: \(profileVM.profiles.count)/1 profile")
                    .font(LinenTheme.body(16, weight: .medium))
                    .foregroundColor(.gray)
                
                Text("Subscribe to create unlimited profiles")
                    .font(LinenTheme.body(14))
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.black.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
            
            // CTA Buttons
            VStack(spacing: 16) {
                Button(action: { showPaywall = true }) {
                    Text("Subscribe Now")
                        .font(LinenTheme.body(16, weight: .semibold))
                        .foregroundColor(LinenTheme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinenTheme.accent)
                        .cornerRadius(24)
                }
                .padding(.horizontal)
                
                Button("Maybe Later") {
                    dismiss()
                }
                .font(LinenTheme.body(16))
                .fontWeight(.light)
                .foregroundColor(.gray)
            }
            .padding(.bottom, 20)
            }
            .frame(minHeight: minHeight)
            .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
    
    // ✅ Normal profile creation view
    private func profileCreationView(minHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 24) {
            // Title
            VStack(spacing: 6) {
                Text("Add profile")
                    .font(LinenTheme.heading(25))
                    .foregroundColor(LinenTheme.ink)
                    .fontWeight(.light)
                    .onTapGesture {
                        guard DeveloperAccessDistributionPolicy.permitsCurrentBuild else { return }
                        devTapCount += 1
                        if devTapCount >= 5 {
                            showDevSheet = true
                            devTapCount = 0
                        }
                        // Reset after 2 seconds if not completed
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if devTapCount < 5 { devTapCount = 0 }
                        }
                    }
                Text("Who is this memory profile for?")
                    .font(LinenTheme.body(16))
                    .fontWeight(.light)
                    .foregroundColor(LinenTheme.secondary)
            }
            .padding(.top, 40)

            // Name Input with pencil icon
            HStack {
                TextField("Enter their name...", text: $name)
                    .font(LinenTheme.body(16))
                    .fontWeight(.light)
                    .foregroundColor(LinenTheme.secondary)
                    .padding()
                    .background(inputBackground)
                    .cornerRadius(16)

                    .focused($isNameFieldFocused)

                if !isNameFieldFocused {
                    Image(systemName: "pencil")
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.trailing, 16)
                        .onTapGesture {
                            isNameFieldFocused = true
                        }
                }
            }
            .padding(.horizontal)

            // Profile Picture Picker
            VStack(spacing: 8) {
                Text("Add a Profile Picture")
                    .font(.customSerifFallback(size: subHeaderFontSize))
                    .fontWeight(.light)
                    .foregroundColor(LinenTheme.ink)

                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let data = selectedPhotoData,
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(
                                    style: StrokeStyle(lineWidth: 2, dash: [8, 8])
                                )
                                .foregroundColor(.gray.opacity(0.4))
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(inputBackground)
                                )
                                .overlay(
                                    Image(systemName: "photo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 100, height: 100)
                                        .foregroundColor(.gray.opacity(0.6))
                                )
                        }
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 20))


                    PhotosPicker(
                        selection: $photoSelection,
                        matching: .images
                    ) {
                        Image(systemName: "camera.fill")
                            .font(LinenTheme.body(16))
                            .padding(10)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    .offset(x: -12, y: -12)
                }

                if selectedPhotoData == nil {
                    Text("Tap to upload")
                        .font(.caption)
                        .fontWeight(.light)
                        .foregroundColor(.black.opacity(0.5))
                }
            }

            Spacer(minLength: 24)

            if let photoLoadError {
                Text(photoLoadError)
                    .font(LinenTheme.body(13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button(action: saveProfile) {
                Text("Save Profile")
                    .font(LinenTheme.body(16, weight: .semibold))
                    .foregroundColor(LinenTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(normalizedName == nil ? LinenTheme.secondary.opacity(0.35) : LinenTheme.accent)
                    .cornerRadius(24)
                    .padding(.horizontal)
            }
            .disabled(normalizedName == nil)

            // Cancel Button
            Button("Cancel") {
                dismiss()
            }
            .font(LinenTheme.body(16))
            .fontWeight(.light)
            .foregroundColor(.gray)
            .padding(.bottom, 20)
            }
            .frame(minHeight: minHeight)
            .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func loadPhotoData(from item: PhotosPickerItem) {
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    selectedPhotoData = data
                    photoLoadError = nil
                } else {
                    photoLoadError = "That photo could not be loaded. Choose another image."
                }
            } catch {
                photoLoadError = "That photo could not be loaded. Choose another image."
                print("Failed to load photo: \(error)")
            }
        }
    }

    private var normalizedName: String? {
        ProfileNamePolicy.normalized(name)
    }

    private func saveProfile() {
        guard let normalizedName else { return }
        let profile = Profile(name: normalizedName, photoData: selectedPhotoData)
        
        if profileVM.addProfile(profile) {
            dismiss()
        } else {
            // This shouldn't happen due to UI gating, but handle gracefully
            showPaywall = true
        }
    }
    
    // MARK: – Developer Unlock Sheet
    private var devUnlockSheet: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "key.fill")
                .font(.system(size: 32))
                .foregroundColor(.gray.opacity(0.4))
            
            Text("Developer Access")
                .font(LinenTheme.body(16, weight: .medium))
                .foregroundColor(.gray)
            
            SecureField("Enter key", text: $devKey)
                .font(LinenTheme.body(15))
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
                .font(LinenTheme.body(14, weight: .medium))
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
                            .font(LinenTheme.body(15, weight: .semibold))
                            .foregroundColor(LinenTheme.onAccent)
                    }
                }
                .frame(width: 120)
                .padding(.vertical, 12)
                .background(devKey.isEmpty ? Color.gray.opacity(0.3) : LinenTheme.accent)
                .cornerRadius(10)
            }
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
}

struct AddProfileView_Previews: PreviewProvider {
    static var previews: some View {
        AddProfileView()
            .environmentObject(ProfileViewModel())
    }
}
