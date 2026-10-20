import SwiftUI

struct ProfileSwitcherView: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAddProfile = false
    @State private var editingProfile: Profile?
    
    private let baseBackground = LinenTheme.paper
    private let darkText = LinenTheme.ink
    private let terracotta = LinenTheme.accent
    
    var body: some View {
        ZStack {
            baseBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(LinenTheme.body(16, weight: .semibold))
                            .foregroundColor(darkText.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.9))

                            )
                    }
                    
                    Spacer()
                    
                    Text("Switch Profile")
                        .font(LinenTheme.heading(25))
                        .foregroundColor(darkText)
                    
                    Spacer()
                    
                    // Invisible spacer to center the title
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
                
                // Profile List
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(profileVM.profiles.indices, id: \.self) { index in
                            ProfileRowView(
                                profile: profileVM.profiles[index],
                                isSelected: index == profileVM.selectedProfileIndex,
                                onTap: {
                                    profileVM.selectedProfileIndex = index
                                    dismiss()
                                },
                                onEdit: {
                                    editingProfile = profileVM.profiles[index]
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Create New Profile Button
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.black.opacity(0.1))
                    
                    Button(action: {
                        showAddProfile = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(LinenTheme.body(20))
                            Text("Add profile")
                                .font(LinenTheme.body(18, weight: .semibold))
                        }
                        .foregroundColor(LinenTheme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(terracotta)
                        .cornerRadius(16)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                    .background(baseBackground)
                }
            }
        }
        .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
        .background(LinenTheme.paper.ignoresSafeArea())
        .sheet(isPresented: $showAddProfile) {
            AddProfileView()
                .environmentObject(profileVM)
        }
        .fullScreenCover(item: $editingProfile) { profile in
            ProfileEditView(profileVM: profileVM, profile: profile)
        }
    }
}

struct ProfileRowView: View {
    let profile: Profile
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    
    private let darkText = LinenTheme.ink
    private let terracotta = LinenTheme.accent
    
    var body: some View {
        HStack(spacing: 16) {
            // Profile Photo
            ZStack {
                if let uiImage = profile.uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .font(LinenTheme.body(24))
                        .foregroundColor(darkText.opacity(0.6))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(isSelected ? terracotta : Color.clear, lineWidth: 3)
            )
            .background(
                Circle()
                    .fill(LinenTheme.surface)

            )

            // Profile Name
            Text(profile.name)
                .font(LinenTheme.body(18, weight: .medium))
                .foregroundColor(darkText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack(spacing: 12) {
                // Checkmark if selected
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(LinenTheme.body(24))
                        .foregroundColor(terracotta)
                }

                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(LinenTheme.body(12, weight: .semibold))
                        Text("Edit")
                            .font(LinenTheme.body(13, weight: .semibold))
                    }
                    .foregroundColor(terracotta)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(terracotta.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LinenTheme.surface)

        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(profile.name) profile")
        .accessibilityHint("Tap to switch profile. Use Edit to change profile details.")
    }
}

struct ProfileSwitcherView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileSwitcherView()
            .environmentObject(ProfileViewModel())
    }
}
