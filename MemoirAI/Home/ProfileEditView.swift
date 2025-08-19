//
//  ProfileEditView.swift
//  MemoirAI
//
//  Comprehensive profile editing interface
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
    
    // Date picker state
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date()) - 30
    @State private var selectedMonth: Int? = nil
    @State private var selectedDay: Int? = nil
    @State private var showDatePicker = false
    
    // Photo picker state
    @State private var showSourceChooser = false
    @State private var showImagePicker = false
    @State private var showCropper = false
    @State private var pickerSource: UIImagePickerController.SourceType = .photoLibrary
    
    // Gender picker
    @State private var selectedGenderOption: GenderOption = .male
    @State private var customGender: String = ""
    
    private let profile: Profile
    
    init(profileVM: ProfileViewModel) {
        self.profileVM = profileVM
        self.profile = profileVM.selectedProfile
        
        // Initialize state from current profile
        self._name = State(initialValue: profile.name)
        self._selectedBirthdate = State(initialValue: profile.birthdate)
        self._ethnicity = State(initialValue: profile.ethnicity ?? "")
        self._gender = State(initialValue: profile.gender ?? "")
        self._currentPhoto = State(initialValue: profile.uiImage)
    }
    
    private let colors = LocalColors()
    
    private var years: [Int] {
        Array(1930...Calendar.current.component(.year, from: Date()))
    }
    
    private var months: [String] {
        Calendar.current.monthSymbols
    }
    
    private var daysInMonth: [Int] {
        guard let month = selectedMonth else { return [] }
        var components = DateComponents()
        components.year = selectedYear
        components.month = month + 1
        let calendar = Calendar.current
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return []
        }
        return Array(range)
    }
    
    private var composedDate: Date? {
        guard let month = selectedMonth, let day = selectedDay else { return nil }
        let components = DateComponents(year: selectedYear, month: month + 1, day: day)
        return Calendar.current.date(from: components)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                colors.softCream
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Photo Section
                        profilePhotoSection
                        
                        // Name Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.headline)
                                .foregroundColor(.black)
                            
                            TextField("Enter your name", text: $name)
                                .textFieldStyle(ProfileTextFieldStyle())
                        }
                        
                        // Birthday Section
                        birthdaySection
                        
                        // Personal Details Section
                        personalDetailsSection
                        
                        // Delete Profile Button (if multiple profiles exist)
                        if profileVM.profiles.count > 1 {
                            deleteProfileButton
                        }
                        
                        Spacer(minLength: 50)
                    }
                    .padding()
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            setupInitialState()
        }
        .confirmationDialog("Add Photo", isPresented: $showSourceChooser) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    pickerSource = .camera
                    showImagePicker = true
                }
            }
            Button("Choose from Library") {
                pickerSource = .photoLibrary
                showImagePicker = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(source: pickerSource, allowsCropping: true) { image in
                currentPhoto = image
            }
        }
        .sheet(isPresented: $showCropper) {
            if let photo = currentPhoto {
                ProfileImageCropperView(image: photo) { croppedImage in
                    currentPhoto = croppedImage
                }
            }
        }
    }
    
    private var profilePhotoSection: some View {
        VStack(spacing: 16) {
            Text("Profile Photo")
                .font(.headline)
                .foregroundColor(.black)
            
            if let photo = currentPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .shadow(radius: 4)
                
                HStack(spacing: 16) {
                    Button("Crop") {
                        showCropper = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button("Replace") {
                        showSourceChooser = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button("Remove") {
                        currentPhoto = nil
                    }
                    .buttonStyle(DestructiveButtonStyle())
                }
            } else {
                Button {
                    showSourceChooser = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.square")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("Add Photo")
                            .font(.subheadline)
                            .foregroundColor(.black)
                    }
                    .frame(width: 120, height: 120)
                    .background(colors.subtleBG)
                    .clipShape(Circle())
                }
            }
        }
    }
    
    private var birthdaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Birthday")
                .font(.headline)
                .foregroundColor(.black)
            
            if let birthdate = selectedBirthdate {
                HStack {
                    Text(DateFormatter.longStyle.string(from: birthdate))
                        .font(.body)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button("Change") {
                        showDatePicker = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding()
                .background(colors.subtleBG)
                .cornerRadius(10)
            } else {
                Button("Set Birthday") {
                    showDatePicker = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            
            if showDatePicker {
                birthdayPickerView
            }
        }
    }
    
    private var birthdayPickerView: some View {
        VStack(spacing: 16) {
            // Year Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Year")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Year", selection: $selectedYear) {
                    ForEach(years.reversed(), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(height: 100)
            }
            
            // Month Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Month")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Month", selection: $selectedMonth) {
                    ForEach(months.indices, id: \.self) { index in
                        Text(months[index]).tag(index as Int?)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(height: 100)
            }
            
            // Day Picker
            if selectedMonth != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Day")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("Day", selection: $selectedDay) {
                        ForEach(daysInMonth, id: \.self) { day in
                            Text(String(day)).tag(day as Int?)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .frame(height: 100)
                }
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    showDatePicker = false
                    resetDatePickers()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("Set Birthday") {
                    if let date = composedDate {
                        selectedBirthdate = date
                        showDatePicker = false
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(composedDate == nil)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 4)
    }
    
    private var personalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personal Details")
                .font(.headline)
                .foregroundColor(.black)
            
            // Ethnicity
            VStack(alignment: .leading, spacing: 4) {
                Text("Ethnicity / Race (Optional)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                TextField("e.g., Hispanic, Asian, Black", text: $ethnicity)
                    .textFieldStyle(ProfileTextFieldStyle())
            }
            
            // Gender
            VStack(alignment: .leading, spacing: 8) {
                Text("Gender (Optional)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Picker("Gender", selection: $selectedGenderOption) {
                    ForEach(GenderOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedGenderOption) {
                    updateGenderBinding()
                }
                
                if selectedGenderOption == .other {
                    TextField("Please specify", text: $customGender)
                        .textFieldStyle(ProfileTextFieldStyle())
                        .onChange(of: customGender) {
                            updateGenderBinding()
                        }
                }
            }
        }
    }
    
    private var deleteProfileButton: some View {
        VStack(spacing: 8) {
            Button("Delete Profile") {
                profileVM.deleteSelectedProfile()
                dismiss()
            }
            .buttonStyle(DestructiveButtonStyle())
            
            Text("This action cannot be undone")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    private func setupInitialState() {
        // Initialize date pickers if birthday exists
        if let birthdate = selectedBirthdate {
            let calendar = Calendar.current
            selectedYear = calendar.component(.year, from: birthdate)
            selectedMonth = calendar.component(.month, from: birthdate) - 1
            selectedDay = calendar.component(.day, from: birthdate)
        }
        
        // Initialize gender picker
        if let standardOption = GenderOption(rawValue: gender) {
            selectedGenderOption = standardOption
        } else if !gender.isEmpty {
            selectedGenderOption = .other
            customGender = gender
        }
    }
    
    private func resetDatePickers() {
        selectedMonth = nil
        selectedDay = nil
    }
    
    private func updateGenderBinding() {
        switch selectedGenderOption {
        case .male, .female:
            gender = selectedGenderOption.rawValue
        case .other:
            gender = customGender
        }
    }
    
    private func saveProfile() {
        let photoData = currentPhoto?.jpegData(compressionQuality: 0.8)
        
        let updatedProfile = Profile(
            id: profile.id,
            name: name.isEmpty ? "Unnamed" : name,
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

// MARK: - Supporting Types and Extensions

fileprivate struct LocalColors {
    let softCream = Color(red: 0.98, green: 0.96, blue: 0.89)
    let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    let subtleBG = Color.black.opacity(0.05)
}

fileprivate enum GenderOption: String, CaseIterable, Identifiable {
    case male = "Male"
    case female = "Female"
    case other = "Other"
    
    var id: Self { self }
}

// Custom button styles
fileprivate struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(red: 0.82, green: 0.45, blue: 0.32))
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

fileprivate struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

fileprivate struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundColor(.red)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

extension DateFormatter {
    static let longStyle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()
}

// MARK: - Shared Components

private struct ImagePicker: UIViewControllerRepresentable {
    var source: UIImagePickerController.SourceType
    var allowsCropping: Bool
    var onPicked: (UIImage) -> Void
    
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }
    
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

private struct ProfileImageCropperView: View {
    let image: UIImage
    var onFinished: (UIImage) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.9).ignoresSafeArea()
                    
                    Color.clear
                        .frame(width: geo.size.width, height: geo.size.width)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .clipped()
                        .overlay(
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
    
    private func renderCropped(in geoSize: CGSize) -> UIImage {
        let renderer = ImageRenderer(content:
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .offset(offset)
                .scaleEffect(scale)
                .frame(width: geoSize.width, height: geoSize.width)
        )
        renderer.scale = 1
        return renderer.uiImage ?? image
    }
}

private struct ProfileTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 16, design: .default))
            .padding(12)
            .background(Color.black.opacity(0.05))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}

