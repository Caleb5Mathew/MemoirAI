////
//  ProfileSetupView.swift
//  MemoirAI
//
//  Now supports in-place cropping of the selected headshot, optional race/ethnicity, and gender.
//

import SwiftUI
import UIKit

fileprivate struct LocalColors {
    static let softCream   = Color(red: 0.98, green: 0.96, blue: 0.89)
    static let terracotta  = Color(red: 0.82, green: 0.45, blue: 0.32)
    static let defaultGray = Color.gray
    static let subtleBG    = Color.black.opacity(0.05)
}

fileprivate extension Font {
    static func appSerif(_ size: CGFloat) -> Font {
        .system(size: size, design: .serif)
    }
}

// Custom Gender Picker options (Decline option removed)
fileprivate enum GenderOption: String, CaseIterable, Identifiable {
    case male = "Male"
    case female = "Female"
    case other = "Other"
    
    var id: Self { self }
}


/// Bottom sheet for headshot source: always shows camera + library; camera tap shows an alert when unavailable (e.g. Simulator).
private struct HeadshotPhotoSourceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onLibrary: () -> Void
    let onCamera: () -> Void
    let onCameraUnavailable: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Photo")
                .font(.headline)
                .padding(.top, 12)

            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    onCamera()
                    dismiss()
                } else {
                    onCameraUnavailable()
                }
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(LocalColors.terracotta)

            Button {
                onLibrary()
                dismiss()
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }
}

// Custom TextField Style for the form
struct AppTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.appSerif(18))
            .padding(12)
            .background(LocalColors.subtleBG)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}

struct ProfileSetupView: View {
    // External bindings
    @Binding var headshotImage: UIImage?
    @Binding var name: String
    @Binding var race: String
    @Binding var gender: String
    let onGenerate: () -> Void
    
    // Environment objects needed for SettingsView
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var subscriptionManager: RCSubscriptionManager
    
    // NEW: Auto-save using AppStorage
    @AppStorage("memoirEthnicity") private var savedEthnicity: String = ""
    @AppStorage("memoirGender") private var savedGender: String = ""
    
    // Dismiss
    @Environment(\.dismiss) private var dismiss
    
    // Settings navigation
    @State private var showSettings = false
    
    // Pick / crop state
    @State private var showSourceChooser = false
    @State private var showImagePicker   = false
    @State private var showCropper       = false
    @State private var pickerSource: UIImagePickerController.SourceType = .photoLibrary
    /// Set before closing the source sheet; consumed in `onDismiss` to present the image picker (avoids stacked-sheet issues).
    @State private var pendingPickerSourceAfterSourceSheet: UIImagePickerController.SourceType?
    @State private var showCameraUnavailableAlert = false
    
    // Track if user has added/modified photo in this session
    @State private var hasUserAddedPhoto = false
    
    // Internal state for the gender picker, defaulting to .male
    @State private var selectedGender: GenderOption = .male
    @State private var customGender: String = ""
    
    // Computed property to check if the button should be enabled
    var isGenerateButtonDisabled: Bool {
        if subscriptionManager.isPersistentDevMode { return false }
        return headshotImage == nil
    }
    
    var body: some View {
        ZStack {
            LocalColors.softCream.ignoresSafeArea()
            
            ScrollView { // Use a ScrollView to prevent overflow on smaller screens
                VStack {
                    // ── Header (dismiss) ──────────────────────────
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.black)
                                .padding(8)
                                .background(LocalColors.subtleBG)
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding()
                    
                    Spacer(minLength: 12)
                    
                    // ── Photo / picker ───────────────────────────
                    Group {
                        if let shot = headshotImage {
                            VStack(spacing: 10) {
                                Button {
                                    showSourceChooser = true
                                } label: {
                                    Image(uiImage: shot)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 200, maxHeight: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 20))
                                        .shadow(radius: 4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(LocalColors.terracotta.opacity(0.35), lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Headshot photo")
                                .accessibilityHint("Tap to replace your headshot with a new photo")
                                
                                Text("Tap your photo to upload or change your headshot")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(LocalColors.defaultGray)
                                
                                Menu {
                                    Button("Crop Photo")    { showCropper       = true }
                                    Button("Replace Photo") { showSourceChooser = true }
                                } label: {
                                    Text(hasUserAddedPhoto ? "Edit Photo" : "Add Photo")
                                        .font(.callout.weight(.semibold))
                                }
                            }
                            .padding(.bottom, 4)
                            
                        } else {
                            VStack(spacing: 10) {
                                Button { showSourceChooser = true } label: {
                                    VStack(spacing: 12) {
                                        Image(systemName: "person.crop.square")
                                            .font(.system(size: 80))
                                            .foregroundColor(LocalColors.defaultGray.opacity(0.6))
                                        Text("Add Headshot")
                                            .font(.headline.weight(.semibold))
                                            .foregroundColor(.black)
                                        Text("Tap to choose from camera or library")
                                            .font(.subheadline)
                                            .foregroundColor(LocalColors.defaultGray)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 200)
                                    .background(LocalColors.subtleBG)
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(LocalColors.terracotta.opacity(0.35), lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add headshot")
                                .accessibilityHint("Tap to take or choose a headshot photo")
                            }
                        }
                    }
                    .padding(.horizontal, 60)

                    // --- USER INPUT FIELDS ---
                    VStack(spacing: 16) {
                        // Labeled input so the purpose is clear even after the user starts typing
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ethnicity / Race")
                                .font(.headline)
                                .foregroundColor(.black)
                            TextField("e.g., Hispanic, Asian, Black", text: $race)
                                .textFieldStyle(AppTextFieldStyle())
                                .accessibilityIdentifier("ethnicityRaceField")
                        }
                        .onChange(of: race) { newValue in
                            // Auto-save when user types
                            savedEthnicity = newValue
                            // Sync back to profile
                            syncRaceToProfile(newValue)
                        }
                        
                        // --- Gender Picker ---
                        Picker("Gender", selection: $selectedGender) {
                            ForEach(GenderOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: selectedGender) { _ in
                            updateGenderBinding()
                            // Auto-save when user changes selection
                            savedGender = gender
                            // Sync back to profile
                            syncGenderToProfile(gender)
                        }
                        
                        // --- Custom Gender Text Field ---
                        if selectedGender == .other {
                            TextField("Please specify gender", text: $customGender)
                                .textFieldStyle(AppTextFieldStyle())
                                .transition(.opacity.animation(.easeIn))
                                .onChange(of: customGender) { _ in
                                    updateGenderBinding()
                                    // Auto-save custom gender
                                    savedGender = gender
                                    // Sync back to profile
                                    syncGenderToProfile(gender)
                                }
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    
                    // ── Explanation text ────────────────────────
                    Text("""
                        A headshot helps lock the appearance.
                        Providing race/ethnicity and gender helps the AI create a more faithful and respectful portrait.
                        """)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 40)
                        .padding(.top, 12)
                    
                    Spacer()
                    
                    // ── Review Settings CTA ────────────────────────────
                    Button {
                        showSettings = true
                    } label: {
                        Text("Review Settings")
                            .font(.headline.weight(.semibold))
                            .accessibilityIdentifier("reviewSettingsButton")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(LocalColors.terracotta)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(isGenerateButtonDisabled)
                    .opacity(isGenerateButtonDisabled ? 0.6 : 1.0)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 30)
                }
            }
        }
        // ── Pick / crop modals ─────────────────────────────
        .sheet(isPresented: $showSourceChooser, onDismiss: {
            if let source = pendingPickerSourceAfterSourceSheet {
                pendingPickerSourceAfterSourceSheet = nil
                pickerSource = source
                showImagePicker = true
            }
        }) {
            HeadshotPhotoSourceSheet(
                onLibrary: { pendingPickerSourceAfterSourceSheet = .photoLibrary },
                onCamera: { pendingPickerSourceAfterSourceSheet = .camera },
                onCameraUnavailable: { showCameraUnavailableAlert = true }
            )
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(source: pickerSource, allowsCropping: true) { img in
                headshotImage = img
                hasUserAddedPhoto = true // Mark that user has added a photo
            }
        }
        .sheet(isPresented: $showCropper) {
            if let current = headshotImage {
                ImageCropperView(image: current) { cropped in
                    headshotImage = cropped
                    hasUserAddedPhoto = true // Mark that user has modified the photo
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsViewWithGenerate(onGenerate: {
                // User tapped Save & Generate in settings
                onGenerate()
                showSettings = false
                dismiss()
            })
            .environmentObject(profileVM)
            .environmentObject(subscriptionManager)
        }
        .alert("Camera Not Available", isPresented: $showCameraUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Taking a photo requires a camera. Use “Choose from Library” here, or try again on a physical iPhone.")
        }
        .onAppear {
            let profile = profileVM.selectedProfile

            // Auto-fill ethnicity from the currently selected profile so users do not re-enter it.
            // Keep the field editable after hydration.
            if let profileEthnicity = profile.ethnicity?.trimmingCharacters(in: .whitespacesAndNewlines),
               !profileEthnicity.isEmpty {
                race = profileEthnicity
            } else if race.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !savedEthnicity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Backward-compatible fallback for older users who only have AppStorage values.
                race = savedEthnicity
            }

            // Populate gender from profile (takes priority) - MUST happen before setInitialGenderState
            if let profileGender = profile.gender, !profileGender.isEmpty {
                if gender.isEmpty {
                    gender = profileGender
                }
            } else if gender.isEmpty && !savedGender.isEmpty {
                gender = savedGender
            }
            
            // Populate name from profile if available and binding is empty
            if name.isEmpty && !profile.name.isEmpty {
                name = profile.name
            }
            
            // Set initial gender state after all values are set
            setInitialGenderState()
        }
    }
    
    // Populates the internal state from the external binding when the view appears
    private func setInitialGenderState() {
        if let standardOption = GenderOption(rawValue: gender) {
            // Handles "Male" or "Female" if they are already in the binding
            selectedGender = standardOption
        } else if !gender.isEmpty {
            // Handles a pre-existing custom gender from the binding
            selectedGender = .other
            customGender = gender
        } else {
            // The binding is empty, so set our default and update the binding
            selectedGender = .male
            updateGenderBinding() // Syncs the binding with the new default state
        }
    }
    
    // Updates the external binding based on the user's selection
    private func updateGenderBinding() {
        switch selectedGender {
        case .male, .female:
            gender = selectedGender.rawValue
        case .other:
            gender = customGender
        }
    }
    
    // Sync race/ethnicity back to profile
    private func syncRaceToProfile(_ raceValue: String) {
        let profile = profileVM.selectedProfile
        let updatedProfile = Profile(
            id: profile.id,
            name: profile.name,
            photoData: profile.photoData,
            birthdate: profile.birthdate,
            ethnicity: raceValue.isEmpty ? nil : raceValue,
            gender: profile.gender,
            createdAt: profile.createdAt,
            updatedAt: Date(),
            childNames: profile.childNames,
            faceDescription: profile.faceDescription,
            faceDescriptionPhotoHash: profile.faceDescriptionPhotoHash
        )
        profileVM.updateSelectedProfile(with: updatedProfile)
    }
    
    // Sync gender back to profile
    private func syncGenderToProfile(_ genderValue: String) {
        let profile = profileVM.selectedProfile
        let updatedProfile = Profile(
            id: profile.id,
            name: profile.name,
            photoData: profile.photoData,
            birthdate: profile.birthdate,
            ethnicity: profile.ethnicity,
            gender: genderValue.isEmpty ? nil : genderValue,
            createdAt: profile.createdAt,
            updatedAt: Date(),
            childNames: profile.childNames,
            faceDescription: profile.faceDescription,
            faceDescriptionPhotoHash: profile.faceDescriptionPhotoHash
        )
        profileVM.updateSelectedProfile(with: updatedProfile)
    }
}

//
//
private struct ImagePicker: UIViewControllerRepresentable {
    var source: UIImagePickerController.SourceType
    var allowsCropping: Bool
    var onPicked: (UIImage) -> Void
    
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType   = source
        picker.allowsEditing = allowsCropping
        picker.delegate     = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }
        
        func imagePickerController(_ picker: UIImagePickerController,
                                     didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let key: UIImagePickerController.InfoKey = picker.allowsEditing ? .editedImage : .originalImage
            if let img = info[key] as? UIImage { onPicked(img) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

//
//
struct ImageCropperView: View {
    let image: UIImage
    var onFinished: (UIImage) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    // Drag / zoom state
    @State private var scale: CGFloat   = 1
    @State private var offset: CGSize   = .zero
    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.9).ignoresSafeArea()
                    
                    // Cropping square frame
                    Color.clear
                        .frame(width: geo.size.width,
                               height: geo.size.width)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .clipped()
                        .overlay(
                            // Movable / zoomable image
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .offset(offset)
                                .scaleEffect(scale)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            offset = CGSize(width: lastOffset.width + value.translation.width,
                                                            height: lastOffset.height + value.translation.height)
                                        }
                                        .onEnded { _ in lastOffset = offset }
                                )
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { newScale in
                                            scale = lastScale * newScale
                                        }
                                        .onEnded { _ in lastScale = scale }
                                )
                        )
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(.white)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            let cropped = renderCropped(in: geo.size)
                            onFinished(cropped)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    }
                }
            }
        }
        .statusBarHidden(true)
    }
    
    // Render the visible square into a UIImage
    private func renderCropped(in geoSize: CGSize) -> UIImage {
        let renderer = ImageRenderer(content:
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .offset(offset)
                .scaleEffect(scale)
                .frame(width: geoSize.width,
                       height: geoSize.width)
        )
        renderer.scale = 1
        return renderer.uiImage ?? image
    }
}


//
//
struct ProfileSetupView_Previews: PreviewProvider {
    @State static var img: UIImage? = nil
    @State static var name = ""
    @State static var race = ""
    @State static var gender = "" // Added for preview
    
    static var previews: some View {
        ProfileSetupView(headshotImage: $img,
                         name: $name,
                         race: $race,
                         gender: $gender, // Pass binding
                         onGenerate: {
            print("Generate button tapped with name: \(name), race: \(race), gender: \(gender)")
        })
    }
}
