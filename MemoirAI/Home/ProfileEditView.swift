//
//  ProfileEditView.swift
//  MemoirAI
//
//  Elegant profile editing interface matching design specs
//

import SwiftUI
import UIKit

struct ProfileEditView: View {
    @ObservedObject var profileVM: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    
    // Local state for editing
    @State private var name: String
    @State private var selectedBirthdate: Date?
    @State private var ethnicity: String
    @State private var gender: String
    @State private var currentPhoto: UIImage?
    
    // UI State
    @State private var showMoreOptions = false
    @State private var showBirthdayPicker = false
    @State private var showImagePicker = false
    @State private var pickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedGenderOption: GenderOption = .male
    
    private let profile: Profile
    
    init(profileVM: ProfileViewModel) {
        self.profileVM = profileVM
        self.profile = profileVM.selectedProfile
        
        // Initialize state from current profile
        self._name = State(initialValue: profile.name)
        self._selectedBirthdate = State(initialValue: profile.birthdate)
        self._ethnicity = State(initialValue: profile.ethnicity ?? "")
        self._gender = State(initialValue: profile.gender ?? "Male")
        self._currentPhoto = State(initialValue: profile.uiImage)
        
        // Set initial gender option
        if let initialGender = profile.gender {
            if initialGender == "Male" {
                self._selectedGenderOption = State(initialValue: .male)
            } else if initialGender == "Female" {
                self._selectedGenderOption = State(initialValue: .female)
            } else {
                self._selectedGenderOption = State(initialValue: .other)
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Cream gradient background
            LinearGradient(
                colors: [
                    Color(hex: "#FAE6D8"),
                    Color(hex: "#FFF9F3")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Navigation Bar
                HStack {
                    Text("Edit Profile")
                        .font(.custom("Georgia", size: 28))
                        .foregroundColor(DesignTokens.darkText)
                    
                    Spacer()
                    
                    Button("Save") {
                        saveProfile()
                        dismiss()
                    }
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DesignTokens.darkText)
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 30)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        // Profile Photo Section
                        profilePhotoSection
                        
                        // About You Section
                        aboutYouSection
                        
                        // More Section (expandable)
                        moreSection
                        
                        // Birthday Button
                        birthdaySection
                        
                        // Personal Details Section
                        personalDetailsSection
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(source: pickerSource, allowsCropping: true) { image in
                currentPhoto = image
            }
        }
        .sheet(isPresented: $showBirthdayPicker) {
            BirthdayPickerSheet(selectedDate: $selectedBirthdate)
        }
    }
    
    // MARK: - Profile Photo Section
    private var profilePhotoSection: some View {
        VStack(spacing: 16) {
            Text("PROFILE PHOTO")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.labelText)
                .kerning(1.2)
            
            Button {
                showImagePicker = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    // Avatar Circle
                    if let photo = currentPhoto {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                            )
                    } else {
                        ZStack {
                            Circle()
                                .fill(DesignTokens.avatarBG)
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundColor(DesignTokens.avatarIcon)
                        }
                    }
                    
                    // Orange + Badge
                    ZStack {
                        Circle()
                            .fill(DesignTokens.primaryOrange)
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .offset(x: -5, y: -5)
                }
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - About You Section
    private var aboutYouSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About You")
                .font(.custom("Georgia", size: 20))
                .foregroundColor(DesignTokens.darkText)
            
            // Name Field in White Card
            VStack {
                TextField("Grandparent", text: $name)
                    .font(.system(size: 18))
                    .foregroundColor(DesignTokens.darkText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
            }
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: DesignTokens.softShadow, radius: 8, x: 0, y: 2)
        }
    }
    
    // MARK: - More Section
    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showMoreOptions.toggle()
                }
            } label: {
                HStack {
                    Text("More")
                        .font(.custom("Georgia", size: 20))
                        .foregroundColor(DesignTokens.darkText)
                    
                    Spacer()
                    
                    Image(systemName: showMoreOptions ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignTokens.labelText)
                }
            }
            .buttonStyle(.plain)
            
            if showMoreOptions {
                VStack(spacing: 16) {
                    // Additional fields would go here
                    Text("Additional options")
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.labelText)
                        .padding(.top, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Birthday Section
    private var birthdaySection: some View {
        HStack {
            Spacer()
            
            Button {
                showBirthdayPicker = true
            } label: {
                HStack {
                    Text(selectedBirthdate != nil ? 
                         DateFormatter.birthdayFormat.string(from: selectedBirthdate!) : 
                         "Set Birthday")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(DesignTokens.primaryOrange)
                .cornerRadius(25)
                .shadow(color: DesignTokens.orangeShadow, radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
    }
    
    // MARK: - Personal Details Section
    private var personalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("PERSONAL DETAILS")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DesignTokens.labelText)
                .kerning(1.2)
            
            // More Options Navigation
            Button {
                // Handle more options
            } label: {
                HStack {
                    Text("More Options")
                        .font(.system(size: 18))
                        .foregroundColor(DesignTokens.darkText)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignTokens.labelText)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            
            // Ethnicity Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Ethnicity / Race (Optional)")
                    .font(.system(size: 14))
                    .foregroundColor(DesignTokens.labelText)
                
                VStack {
                    TextField("", text: $ethnicity)
                        .font(.system(size: 18))
                        .foregroundColor(DesignTokens.darkText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                }
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: DesignTokens.softShadow, radius: 8, x: 0, y: 2)
            }
            
            // Gender Selector
            VStack(alignment: .leading, spacing: 12) {
                Text("Gender")
                    .font(.system(size: 14))
                    .foregroundColor(DesignTokens.labelText)
                
                HStack(spacing: 0) {
                    ForEach(GenderOption.allCases, id: \.self) { option in
                        Button {
                            selectedGenderOption = option
                            gender = option.rawValue
                        } label: {
                            Text(option.rawValue)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(selectedGenderOption == option ? .white : DesignTokens.darkText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    selectedGenderOption == option ? 
                                    DesignTokens.primaryOrange : 
                                    Color.white
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .cornerRadius(25)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(DesignTokens.borderColor, lineWidth: 1)
                )
                .shadow(color: DesignTokens.softShadow, radius: 4, x: 0, y: 2)
            }
        }
    }
    
    // MARK: - Save Profile
    private func saveProfile() {
        let photoData = currentPhoto?.jpegData(compressionQuality: 0.8)
        
        let updatedProfile = Profile(
            id: profile.id,
            name: name.isEmpty ? "Grandparent" : name,
            photoData: photoData,
            birthdate: selectedBirthdate,
            ethnicity: ethnicity.isEmpty ? nil : ethnicity,
            gender: gender.isEmpty ? nil : gender,
            createdAt: profile.createdAt,
            updatedAt: Date()
        )
        
        profileVM.updateSelectedProfile(with: updatedProfile)
    }
}

// MARK: - Design Tokens
private struct DesignTokens {
    static let primaryOrange = Color(hex: "#C9652F")
    static let avatarBG = Color(hex: "#F5E6D8")
    static let avatarIcon = Color(hex: "#D4A574")
    static let darkText = Color(hex: "#2C2C2C")
    static let labelText = Color(hex: "#7A7A7A")
    static let borderColor = Color(hex: "#E8DAC3")
    static let softShadow = Color.black.opacity(0.08)
    static let orangeShadow = Color(hex: "#C9652F").opacity(0.3)
}

// MARK: - Gender Options
private enum GenderOption: String, CaseIterable {
    case male = "Male"
    case female = "Female"
    case other = "Other"
}

// MARK: - Birthday Picker Sheet
private struct BirthdayPickerSheet: View {
    @Binding var selectedDate: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var tempDate = Date()
    
    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Birthday",
                    selection: $tempDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(WheelDatePickerStyle())
                .labelsHidden()
                .padding()
                
                Spacer()
            }
            .navigationTitle("Select Birthday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        selectedDate = tempDate
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let date = selectedDate {
                tempDate = date
            }
        }
    }
}

// MARK: - Image Picker
private struct ImagePicker: UIViewControllerRepresentable {
    var source: UIImagePickerController.SourceType
    var allowsCropping: Bool
    var onPicked: (UIImage) -> Void
    
    func makeCoordinator() -> Coordinator { 
        Coordinator(onPicked: onPicked) 
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.allowsEditing = allowsCropping
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onPicked: (UIImage) -> Void
        
        init(onPicked: @escaping (UIImage) -> Void) { 
            self.onPicked = onPicked 
        }
        
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let key: UIImagePickerController.InfoKey = picker.allowsEditing ? .editedImage : .originalImage
            if let img = info[key] as? UIImage { 
                onPicked(img) 
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Extensions
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension DateFormatter {
    static let birthdayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
}