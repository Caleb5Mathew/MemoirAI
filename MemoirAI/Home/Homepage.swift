// HomepageView.swift
// MemoirAI

import SwiftUI
import PhotosUI

// Wrapper to allow Data to be used with .sheet(item:)
struct IdentifiableData: Identifiable {
    let id = UUID()
    let data: Data
}

struct HomepageView: View {
    @State private var selectedTab = 0
    let promptOfTheDay = "Tell me about your first job."
    @State private var promptCompleted: Bool = false

    // Profile Logic
    @EnvironmentObject var profileVM: ProfileViewModel
    @State private var isShowingPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem? = nil
    @State private var selectedPhotoData: IdentifiableData? = nil

    // UserDefaults key for camera wiggle persistence
    // Using a static let makes it clear and reusable, and adding a version can be helpful.
    private static let cameraWiggleDisabledKey = "cameraWiggleDisabledKey_v1"

    // Control for the wiggle-animation on the edit icon, initialized from UserDefaults
    @State private var disableCameraWiggle: Bool = UserDefaults.standard.bool(forKey: HomepageView.cameraWiggleDisabledKey)
    
    // NEW: control presentation of AddProfileView
    @State private var showingAddProfile = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // TOP BAR – Title, Go Pro, Profile icon
                
                HStack {
                    Text("MemoirAI")
                        .font(.customSerifFallback(size: 22))
                        .foregroundColor(Color(red: 0.10, green: 0.22, blue: 0.14))

                    Spacer()

                    Button(action: {}) {
                        Text("Go Pro")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 1, green: 0.35, blue: 0.55),
                                        Color(red: 1, green: 0.65, blue: 0.25)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(18)
                            .shadow(color: Color.orange.opacity(0.3), radius: 6, x: 0, y: 3)
                    }

                    Button(action: {
                        // Could open settings/profile management
                    }) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 28, height: 28)
                            .foregroundColor(.gray)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // PROFILE PHOTO VIEW (wiggles until tapped)
                        ProfilePhotoView(
                            viewModel: profileVM,
                            disableWiggle: $disableCameraWiggle
                        ) {
                            // Action when the ProfilePhotoView's tappable element is activated
                            showingAddProfile = true // Show the AddProfileView
                            
                            // If the wiggle is not yet disabled, disable it and persist the change
                            if !disableCameraWiggle {
                                disableCameraWiggle = true
                                UserDefaults.standard.set(true, forKey: HomepageView.cameraWiggleDisabledKey)
                            }
                        }

                        // TITLE
                        VStack(spacing: 10) {
                            Text("Your voice.\nYour legacy.")
                                .font(.customSerifFallback(size: 30))
                                .foregroundColor(Color(red: 0.10, green: 0.22, blue: 0.14))
                                .multilineTextAlignment(.center)

                            Text("Capture your stories for future generations — no typing, just talking.")
                                .font(.subheadline)
                                .foregroundColor(Color.black.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // START RECORDING
                        NavigationLink(destination: RecordMemoryView().environmentObject(profileVM)) {
                            Text("Start Recording")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color(red: 0.83, green: 0.45, blue: 0.14))
                                )
                                .padding(.horizontal)
                                .shadow(color: Color.orange.opacity(0.25), radius: 6, x: 0, y: 3)
                        }

                        // PROMPT OF THE DAY & STORY PAGE
                        HStack(spacing: 12) {
                            NavigationLink(destination: RecordMemoryView(promptOfTheDay: promptOfTheDay)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Text("Prompt of the Day")
                                            .font(.footnote)
                                            .fontWeight(.bold)
                                            .foregroundColor(.black)
                                        if promptCompleted {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 16))
                                                .scaleEffect(promptCompleted ? 1.0 : 0.1)
                                                .opacity(promptCompleted ? 1 : 0)
                                                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: promptCompleted)
                                        }
                                    }
                                    Text(promptOfTheDay)
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.85))
                                        .multilineTextAlignment(.leading)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(promptCompleted
                                    ? Color.green.opacity(0.15)
                                    : Color(red: 0.98, green: 0.93, blue: 0.80))
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                            }

                            NavigationLink(destination: StoryPage()) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Your StoryPage")
                                        .font(.footnote)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    Text("A Summer Vacation")
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.85))
                                    HStack {
                                        Text("2 min")
                                        Spacer()
                                        Text("Apr 20")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.black.opacity(0.6))
                                }
                                .padding()
                                .background(Color(red: 0.98, green: 0.93, blue: 0.80))
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                                .frame(maxWidth: .infinity, minHeight: 100)
                            }
                        }
                        .padding(.horizontal)

                        // CONTINUE YOUR MEMOIR
                        NavigationLink(destination: MemoirView().environmentObject(profileVM)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Continue Your Memoir")
                                        .font(.footnote)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    Text("Chapter 3 of 10 Completed")
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.7))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color(red: 0.98, green: 0.93, blue: 0.80))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                            .padding(.horizontal)
                        }

                        Spacer(minLength: 36)
                    }
                    .padding(.top, 24)
                }
                .onAppear {
                    resetDailyPromptIfNeeded()
                    // Note: disableCameraWiggle is already initialized from UserDefaults.
                    // If you needed to refresh it for some other reason upon view appearing,
                    // you could re-read it here, but direct initialization of @State is usually sufficient.
                }
            }
            .background(Color(red: 0.98, green: 0.94, blue: 0.86).ignoresSafeArea())
        }
        // NEW: Present AddProfileView modally
        .sheet(isPresented: $showingAddProfile) {
            AddProfileView() // Assuming AddProfileView is defined elsewhere
                .environmentObject(profileVM)
        }
        // Photo picker wiring (currently unused once AddProfileView handles photo)
        .photosPicker(isPresented: $isShowingPhotoPicker, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { // Using new syntax for Swift 5.7+
            if let newItem = photoSelection { // photoSelection is already the new value
                loadPhotoData(newItem)
            }
        }
        .sheet(item: $selectedPhotoData) { wrapper in
            CropSheetView(photoData: wrapper.data) { croppedData in // Assuming CropSheetView and Profile are defined
                // This Profile struct definition would need to match your actual Profile model
                // For example: struct Profile { var name: String; var photoData: Data? }
                // profileVM.addProfile(Profile(name: "Unnamed", photoData: croppedData)) // Adjust as per your Profile model
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true) // Consider if this is intended for iOS 16+ (use .persistentSystemOverlays(.hidden) for status bar)
    }

    private func loadPhotoData(_ newItem: PhotosPickerItem) {
        Task {
            do {
                if let data = try await newItem.loadTransferable(type: Data.self) {
                    selectedPhotoData = IdentifiableData(data: data)
                }
            } catch {
                print("Failed to load transferable data: \(error)")
            }
        }
    }

    private func resetDailyPromptIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = UserDefaults.standard.object(forKey: "PromptCompletedDate") as? Date

        if lastDate == nil ||
            Calendar.current.compare(today, to: lastDate!, toGranularity: .day) != .orderedSame {
            UserDefaults.standard.set(false, forKey: promptOfTheDay) // Reset completion status for the specific prompt text
            UserDefaults.standard.set(today, forKey: "PromptCompletedDate") // Update the last checked date
        }

        promptCompleted = UserDefaults.standard.bool(forKey: promptOfTheDay)
    }
}

// Assume these views/models are defined elsewhere for preview and functionality:
// struct ProfilePhotoView: View { /* ... */ var disableWiggle: Binding<Bool>; var action: () -> Void; /* ... */ }
// class ProfileViewModel: ObservableObject { /* ... */ @Published var currentProfile: Profile? /* ... */ func addProfile(_ profile: Profile) {} }
// struct Profile { var name: String; var photoData: Data? } // Example
// struct RecordMemoryView: View { var promptOfTheDay: String? = nil; /* ... */ }
// struct StoryPage: View { /* ... */ }
// struct AddProfileView: View { /* ... */ }
// struct CropSheetView: View { var photoData: Data; var onCropped: (Data) -> Void; /* ... */ }
// Extension for Font.customSerifFallback needs to be available.

struct HomepageView_Previews: PreviewProvider {
    static var previews: some View {
        HomepageView()
            .environmentObject(ProfileViewModel()) // Make sure ProfileViewModel is properly initialized for previews
            .previewDevice("iPhone 15 Pro")
    }
}
