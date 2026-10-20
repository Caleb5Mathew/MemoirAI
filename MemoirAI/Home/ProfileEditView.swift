//
//  ProfileEditView.swift
//  MemoirAI
//

import SwiftUI
import UIKit

// MARK: - Design System
private enum DS {
    static let accent = LinenTheme.accent
    static let accentSoft = LinenTheme.accent.opacity(0.14)
    static let bg = LinenTheme.paper
    static let card = LinenTheme.paper
    static let textPrimary = LinenTheme.ink
    static let textSecondary = LinenTheme.secondary
    static let textTertiary = LinenTheme.secondary
    static let fieldBg = LinenTheme.surface
    static let divider = LinenTheme.line
    static let stroke = LinenTheme.line
    static let cardRadius: CGFloat = 20
}

struct ProfileEditView: View {
    @ObservedObject var profileVM: ProfileViewModel
    @ObservedObject private var subscriptionManager = RCSubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedBirthdate: Date?
    @State private var ethnicity: String
    @State private var gender: String
    @State private var transcriptionTerms: String
    @State private var currentPhoto: UIImage?

    @State private var showBirthdayPicker = false
    @State private var showImagePicker = false
    @State private var pickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedGenderOption: GenderOption = .male

    @FocusState private var focusedField: Field?
    @State private var appeared = false

    @State private var showDevModeSheet = false
    @State private var devPassword = ""
    @State private var devUnlockResult: ProfileEditDevUnlockResult?
    @State private var devUnlockErrorMessage: String?
    @State private var isVerifyingDevAccess = false

    private enum ProfileEditDevUnlockResult {
        case success, incorrect
    }

    enum Field: Hashable {
        case name, ethnicity, transcriptionTerms
    }

    private let profile: Profile

    init(profileVM: ProfileViewModel, profile: Profile? = nil) {
        self.profileVM = profileVM
        let resolvedProfile = profile ?? profileVM.selectedProfile
        self.profile = resolvedProfile

        self._name = State(initialValue: resolvedProfile.name)
        self._selectedBirthdate = State(initialValue: resolvedProfile.birthdate)
        self._ethnicity = State(initialValue: resolvedProfile.ethnicity ?? "")
        self._gender = State(initialValue: resolvedProfile.gender ?? "Male")
        self._transcriptionTerms = State(initialValue: resolvedProfile.transcriptionGlossary.joined(separator: ", "))
        self._currentPhoto = State(initialValue: resolvedProfile.uiImage)

        if let initialGender = resolvedProfile.gender {
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
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                navBar
                scrollContent
            }
            .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
        }
        .analyticsScreen("profile_edit")
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(source: pickerSource, allowsCropping: true) { image in
                currentPhoto = image
            }
        }
        .sheet(isPresented: $showBirthdayPicker) {
            BirthdayPickerSheet(selectedDate: $selectedBirthdate)
        }
        .sheet(isPresented: $showDevModeSheet) {
            profileEditDevModeSheet
        }
    }

    // MARK: - Nav Bar
    private var navBar: some View {
        HStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(LinenTheme.body(14, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.92))
                            .overlay(
                                Circle().stroke(DS.stroke, lineWidth: 1)
                            )
                    )
            }

            Spacer()

            Text("Edit Profile")
                .font(LinenTheme.heading(25))
                .foregroundColor(DS.textPrimary)
                .tracking(-0.5)
                 .fixedSize(horizontal: false, vertical: true)


            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                saveProfile()
                dismiss()
            } label: {
                Text("Save")
                    .font(LinenTheme.body(15, weight: .bold))
                    .foregroundColor(LinenTheme.onAccent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(DS.accent)

                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    // MARK: - Scroll Content
    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                avatarSection
                    .padding(.top, 4)

                nameAndBirthdayCard
                    .staggerIn(appeared: appeared, delay: 0.04)

                personalDetailsCard
                    .staggerIn(appeared: appeared, delay: 0.08)

                transcriptionCard
                    .staggerIn(appeared: appeared, delay: 0.10)

                LinkedAccountsView()
                    .padding(16)
                    .background(DS.card, in: RoundedRectangle(cornerRadius: 16))
                    .staggerIn(appeared: appeared, delay: 0.12)

                if DeveloperAccessDistributionPolicy.permitsCurrentBuild {
                    developerOptionsEntry
                        .staggerIn(appeared: appeared, delay: 0.12)
                }

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
        }
    }

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Names & Places")
                .font(LinenTheme.body(15, weight: .semibold))
                .foregroundColor(DS.textPrimary)

            Text("Add uncommon names or places, separated by commas, to improve voice transcripts.")
                .font(LinenTheme.body(13))
                .foregroundColor(DS.textSecondary)

            TextField("e.g. Rosalie, Chautauqua, St. Louis", text: $transcriptionTerms, axis: .vertical)
                .lineLimit(2...4)
                .font(LinenTheme.body(16))
                .foregroundColor(DS.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DS.fieldBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(focusedField == .transcriptionTerms ? DS.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
                .focused($focusedField, equals: .transcriptionTerms)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .fill(DS.card)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                        .stroke(DS.stroke, lineWidth: 1)
                )

        )
    }

    // MARK: - Avatar
    private var avatarSection: some View {
        VStack(spacing: 16) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showImagePicker = true
            } label: {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(DS.accent.opacity(0.15), lineWidth: 3)
                        .frame(width: 96, height: 106)

                    if let photo = currentPhoto {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 98)
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 44, bottomLeadingRadius: 15, bottomTrailingRadius: 15, topTrailingRadius: 44))
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.fieldBg, DS.divider],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 88, height: 98)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 42, weight: .thin))
                                    .foregroundColor(DS.textTertiary)
                            )
                    }

                    // Camera badge
                    Circle()
                        .fill(DS.accent)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(LinenTheme.body(14, weight: .medium))
                                .foregroundColor(LinenTheme.onAccent)
                        )

                        .offset(x: 32, y: 38)
                }
            }
            .buttonStyle(ProfileScaleButtonStyle())

            Text("Tap to change photo")
                .font(LinenTheme.body(13, weight: .medium))
                .foregroundColor(DS.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .staggerIn(appeared: appeared, delay: 0)
    }

    // MARK: - Name & Birthday Card
    private var nameAndBirthdayCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Name field
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(LinenTheme.body(13, weight: .semibold))
                    .foregroundColor(DS.textTertiary)
                    .textCase(.uppercase)
                    .kerning(0.4)

                TextField("Enter name", text: $name)
                    .font(LinenTheme.body(17, weight: .regular))
                    .foregroundColor(DS.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.fieldBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(focusedField == .name ? DS.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
                    .focused($focusedField, equals: .name)
                    .animation(.easeOut(duration: 0.2), value: focusedField)
            }

            // Birthday
            VStack(alignment: .leading, spacing: 8) {
                Text("Birthday")
                    .font(LinenTheme.body(13, weight: .semibold))
                    .foregroundColor(DS.textTertiary)
                    .textCase(.uppercase)
                    .kerning(0.4)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showBirthdayPicker = true
                } label: {
                    HStack {
                        Text(selectedBirthdate != nil ?
                             DateFormatter.birthdayFormat.string(from: selectedBirthdate!) :
                             "Set birthday")
                            .font(LinenTheme.body(17))
                            .foregroundColor(selectedBirthdate != nil ? DS.textPrimary : DS.textTertiary)

                        Spacer()

                        Image(systemName: "calendar")
                            .font(LinenTheme.body(15, weight: .medium))
                            .foregroundColor(DS.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.fieldBg)
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .fill(DS.card)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                        .stroke(DS.stroke, lineWidth: 1)
                )

        )
    }

    // MARK: - Personal Details Card
    private var personalDetailsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Text("Personal Details")
                    .font(LinenTheme.body(15, weight: .semibold))
                    .foregroundColor(DS.textPrimary)

                Text("Optional")
                    .font(LinenTheme.body(12, weight: .medium))
                    .foregroundColor(DS.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(DS.fieldBg)
                    )
            }

            // Ethnicity
            VStack(alignment: .leading, spacing: 8) {
                Text("Ethnicity / Heritage")
                    .font(LinenTheme.body(13, weight: .semibold))
                    .foregroundColor(DS.textTertiary)
                    .textCase(.uppercase)
                    .kerning(0.4)

                TextField("e.g. Italian-American", text: $ethnicity)
                    .font(LinenTheme.body(17, weight: .regular))
                    .foregroundColor(DS.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.fieldBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(focusedField == .ethnicity ? DS.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
                    .focused($focusedField, equals: .ethnicity)
                    .animation(.easeOut(duration: 0.2), value: focusedField)
            }

            // Gender
            VStack(alignment: .leading, spacing: 10) {
                Text("Gender")
                    .font(LinenTheme.body(13, weight: .semibold))
                    .foregroundColor(DS.textTertiary)
                    .textCase(.uppercase)
                    .kerning(0.4)

                genderPicker
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .fill(DS.card)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                        .stroke(DS.stroke, lineWidth: 1)
                )

        )
    }

    // MARK: - Gender Picker
    private var genderPicker: some View {
        HStack(spacing: 0) {
            ForEach(GenderOption.allCases, id: \.self) { option in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedGenderOption = option
                        gender = option.rawValue
                    }
                } label: {
                    Text(option.rawValue)
                        .font(LinenTheme.body(15, weight: .semibold))
                        .foregroundColor(selectedGenderOption == option ? .white : DS.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Group {
                                if selectedGenderOption == option {
                                    Capsule().fill(DS.accent)

                                }
                            }
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule().fill(DS.fieldBg)
        )
    }

    // MARK: - Developer mode (persistent unlock)
    private var developerOptionsEntry: some View {
        Button {
            showDevModeSheet = true
        } label: {
            Text("Developer Options")
                .font(LinenTheme.body(11, weight: .medium))
                .foregroundColor(DS.textTertiary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileEditDevModeSheet: some View {
        NavigationStack {
            Group {
                if subscriptionManager.isPersistentDevMode {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("Developer Mode Active")
                            .font(LinenTheme.body(17, weight: .semibold))
                            .foregroundColor(DS.textPrimary)
                        Text("Subscription bypass and elevated allowance persist across app launches until you disable.")
                            .font(LinenTheme.body(13))
                            .foregroundColor(DS.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Button {
                            subscriptionManager.disablePersistentDevMode()
                            showDevModeSheet = false
                        } label: {
                            Text("Disable Developer Mode")
                                .font(LinenTheme.body(15, weight: .semibold))
                                .foregroundColor(LinenTheme.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.85))
                                .cornerRadius(10)
                        }
                        .padding(.horizontal, 24)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "key.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray.opacity(0.4))
                        Text("Developer Access")
                            .font(LinenTheme.body(16, weight: .medium))
                            .foregroundColor(.gray)
                        SecureField("Enter key", text: $devPassword)
                            .font(LinenTheme.body(15))
                            .padding(12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal, 40)
                        if let result = devUnlockResult {
                            HStack(spacing: 6) {
                                Image(systemName: result == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                Text(result == .success ? "Unlocked!" : (devUnlockErrorMessage ?? "Access denied"))
                            }
                            .font(LinenTheme.body(14, weight: .medium))
                            .foregroundColor(result == .success ? .green : .red)
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
                            .background(devPassword.isEmpty ? Color.gray.opacity(0.3) : DS.accent)
                            .cornerRadius(10)
                        }
                        .disabled(devPassword.isEmpty || isVerifyingDevAccess)
                        Spacer()
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("Developer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showDevModeSheet = false
                    }
                    .foregroundColor(DS.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onDisappear {
            devPassword = ""
            devUnlockResult = nil
            devUnlockErrorMessage = nil
            isVerifyingDevAccess = false
        }
    }

    @MainActor
    private func verifyDeveloperAccess() async {
        isVerifyingDevAccess = true
        defer { isVerifyingDevAccess = false }
        do {
            try await subscriptionManager.authorizeDeveloperAccess(devPassword)
            withAnimation { devUnlockResult = .success }
            devUnlockErrorMessage = nil
            devPassword = ""
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            showDevModeSheet = false
            devUnlockResult = nil
        } catch {
            devUnlockErrorMessage = error.localizedDescription
            withAnimation { devUnlockResult = .incorrect }
        }
    }

    // MARK: - Save
    private func saveProfile() {
        let photoData = currentPhoto?.jpegData(compressionQuality: 0.8)
        let glossary = transcriptionTerms
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let updatedProfile = Profile(
            id: profile.id,
            name: name.isEmpty ? "Grandparent" : name,
            photoData: photoData,
            birthdate: selectedBirthdate,
            ethnicity: ethnicity.isEmpty ? nil : ethnicity,
            gender: gender.isEmpty ? nil : gender,
            createdAt: profile.createdAt,
            updatedAt: Date(),
            childNames: profile.childNames,
            transcriptionGlossary: Array(glossary.prefix(40)),
            faceDescription: profile.faceDescription,
            faceDescriptionPhotoHash: profile.faceDescriptionPhotoHash
        )

        profileVM.updateProfile(updatedProfile)
    }
}

// MARK: - Stagger Animation Modifier
private struct StaggerModifier: ViewModifier {
    let appeared: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(.easeOut(duration: 0.45).delay(delay), value: appeared)
    }
}

private extension View {
    func staggerIn(appeared: Bool, delay: Double) -> some View {
        modifier(StaggerModifier(appeared: appeared, delay: delay))
    }
}

// MARK: - Scale Button Style
private struct ProfileScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
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
    @State private var pickerMode: PickerMode = .wheel

    private enum PickerMode: String, CaseIterable {
        case calendar = "Calendar"
        case wheel = "Wheel"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $pickerMode) {
                    ForEach(PickerMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(DS.accent)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Group {
                    Group {
                        if pickerMode == .calendar {
                            DatePicker(
                                "Birthday",
                                selection: $tempDate,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .accentColor(DS.accent)
                        } else {
                            DatePicker(
                                "Birthday",
                                selection: $tempDate,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.95))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(DS.stroke, lineWidth: 1)
                            )
                    )

                }
                .padding(.horizontal, 20)
                .transition(.opacity)

                Spacer()
            }
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("Select Birthday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .foregroundColor(DS.textSecondary)
                    .font(LinenTheme.body(16, weight: .semibold))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        selectedDate = tempDate
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(DS.accent)
                }
            }
        }
        .onAppear {
            if let date = selectedDate {
                tempDate = date
            } else {
                let calendar = Calendar.current
                tempDate = calendar.date(byAdding: .year, value: -80, to: Date()) ?? Date()
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
extension DateFormatter {
    static let birthdayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
}
