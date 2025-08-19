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
                // Modern gradient background
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        // Header with large profile photo
                        profileHeaderSection
                            .padding(.bottom, 32)
                        
                        // Form sections in cards
                        VStack(spacing: 20) {
                            nameFormCard
                            birthdayFormCard
                            personalDetailsFormCard
                            
                            // Delete section (if applicable)
                            if profileVM.profiles.count > 1 {
                                deleteProfileCard
                                    .padding(.top, 20)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
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
    
    private var profileHeaderSection: some View {
        VStack(spacing: 24) {
            // Large profile photo with elegant styling
            ZStack {
                if let photo = currentPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.3), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(.systemGray5),
                                    Color(.systemGray4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 60, weight: .light))
                                .foregroundColor(.secondary)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                }
                
                // Edit overlay button
                Button {
                    showSourceChooser = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(.black.opacity(0.7))
                                .overlay(
                                    Circle()
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .offset(x: 50, y: 50)
            }
            
            // Photo action buttons (only show if photo exists)
            if currentPhoto != nil {
                HStack(spacing: 16) {
                    Button("Crop") {
                        showCropper = true
                    }
                    .buttonStyle(ModernSecondaryButtonStyle())
                    
                    Button("Replace") {
                        showSourceChooser = true
                    }
                    .buttonStyle(ModernSecondaryButtonStyle())
                    
                    Button("Remove") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentPhoto = nil
                        }
                    }
                    .buttonStyle(ModernDestructiveButtonStyle())
                }
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Modern Form Cards
    
    private var nameFormCard: some View {
        ModernFormCard(title: "Name", icon: "person.fill") {
            ModernTextField(
                placeholder: "Enter your name",
                text: $name
            )
        }
    }
    
    private var birthdayFormCard: some View {
        ModernFormCard(title: "Birthday", icon: "calendar") {
            if let birthdate = selectedBirthdate {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DateFormatter.elegantStyle.string(from: birthdate))
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("Tap to change")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        showDatePicker.toggle()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.accentColor)
                            .frame(width: 28, height: 28)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showDatePicker.toggle()
                }
            } else {
                Button {
                    showDatePicker = true
                } label: {
                    HStack {
                        Text("Set birthday")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.accentColor)
                        
                        Spacer()
                        
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            if showDatePicker {
                modernBirthdayPicker
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity
                    ))
            }
        }
    }
    
    private var personalDetailsFormCard: some View {
        ModernFormCard(title: "Personal Details", icon: "person.text.rectangle") {
            VStack(spacing: 20) {
                // Ethnicity field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ethnicity / Race")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    ModernTextField(
                        placeholder: "e.g., Hispanic, Asian, Black",
                        text: $ethnicity,
                        isOptional: true
                    )
                }
                
                // Gender selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gender")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    modernGenderPicker
                    
                    if selectedGenderOption == .other {
                        ModernTextField(
                            placeholder: "Please specify",
                            text: $customGender,
                            isOptional: true
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity
                        ))
                    }
                }
            }
        }
    }
    
    private var deleteProfileCard: some View {
        ModernFormCard(title: "", icon: "", isDestructive: true) {
            VStack(spacing: 12) {
                Button("Delete Profile") {
                    profileVM.deleteSelectedProfile()
                    dismiss()
                }
                .buttonStyle(ModernDestructiveButtonStyle())
                
                Text("This action cannot be undone")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

// MARK: - Modern UI Components

    private var modernGenderPicker: some View {
    HStack(spacing: 8) {
        ForEach(GenderOption.allCases) { option in
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedGenderOption = option
                    updateGenderBinding()
                }
            } label: {
                Text(option.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(selectedGenderOption == option ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(selectedGenderOption == option ? Color.accentColor : Color(.systemGray6))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        Spacer()
    }
}

    private var modernBirthdayPicker: some View {
    VStack(spacing: 20) {
        VStack(spacing: 16) {
            // Year Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Year")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Picker("Year", selection: $selectedYear) {
                    ForEach(years.reversed(), id: \.self) { year in
                        Text(String(year))
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Month Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Month")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Picker("Month", selection: $selectedMonth) {
                    ForEach(months.indices, id: \.self) { index in
                        Text(months[index])
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .tag(index as Int?)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Day Picker
            if selectedMonth != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Day")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Picker("Day", selection: $selectedDay) {
                        ForEach(daysInMonth, id: \.self) { day in
                            Text(String(day))
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .tag(day as Int?)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        
        // Action buttons
        HStack(spacing: 12) {
            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDatePicker = false
                    resetDatePickers()
                }
            }
            .buttonStyle(ModernSecondaryButtonStyle())
            
            Button("Set Birthday") {
                if let date = composedDate {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedBirthdate = date
                        showDatePicker = false
                    }
                }
            }
            .buttonStyle(ModernPrimaryButtonStyle())
            .disabled(composedDate == nil)
        }
    }
    .padding(20)
    .background(
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    )
    .padding(.top, 12)
}

struct ModernFormCard<Content: View>: View {
    let title: String
    let icon: String
    let isDestructive: Bool
    let content: Content
    
    init(title: String, icon: String, isDestructive: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.isDestructive = isDestructive
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty {
                HStack(spacing: 12) {
                    if !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isDestructive ? .red : .accentColor)
                            .frame(width: 24, height: 24)
                    }
                    
                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(isDestructive ? .red : .primary)
                }
            }
            
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }
}

struct ModernTextField: View {
    let placeholder: String
    @Binding var text: String
    let isOptional: Bool
    
    init(placeholder: String, text: Binding<String>, isOptional: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.isOptional = isOptional
    }
    
    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 16, weight: .medium, design: .default))
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                    )
            )
            .overlay(
                HStack {
                    Spacer()
                    if isOptional {
                        Text("Optional")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.trailing, 12)
                    }
                }
            )
    }
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
    
    static let elegantStyle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()
}

// Modern Button Styles
struct ModernPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ModernSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.systemGray5), lineWidth: 0.5)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ModernDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red)
                    .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
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

