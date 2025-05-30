import SwiftUI
import MessageUI

// MARK: - Create Family View

struct CreateFamilyView: View {
    @EnvironmentObject var familyManager: FamilyManager
    @EnvironmentObject var profileVM: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var familyName: String = ""
    @State private var showSuccessMessage = false
    @FocusState private var isTextFieldFocused: Bool
    
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let backgroundColor = Color(red: 0.98, green: 0.94, blue: 0.86)
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundColor.ignoresSafeArea()
                
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(spacing: 32) {
                            VStack(spacing: 16) {
                                Image(systemName: "house.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(terracotta)
                                
                                Text("Create Your Family")
                                    .font(.customSerifFallback(size: 28))
                                    .fontWeight(.bold)
                                    .foregroundColor(accentColor)
                                
                                Text("Start sharing your memories with family members")
                                    .font(.body)
                                    .foregroundColor(.black.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 32)
                            
                            VStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Family Name")
                                        .font(.headline)
                                        .foregroundColor(accentColor)
                                    
                                    TextField("e.g., The Johnson Family", text: $familyName)
                                        .font(.body)
                                        .foregroundColor(accentColor)
                                        .focused($isTextFieldFocused)
                                        .padding(16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white)
                                                .shadow(
                                                    color: isTextFieldFocused ? terracotta.opacity(0.3) : Color.clear,
                                                    radius: isTextFieldFocused ? 8 : 0
                                                )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    isTextFieldFocused ? terracotta : Color.gray.opacity(0.3),
                                                    lineWidth: isTextFieldFocused ? 2 : 1
                                                )
                                        )
                                        .scaleEffect(isTextFieldFocused ? 1.02 : 1.0)
                                        .animation(.easeInOut(duration: 0.2), value: isTextFieldFocused)
                                        .id("familyNameField")
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("You'll be the family admin and can:")
                                        .font(.subheadline)
                                        .foregroundColor(accentColor)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        bulletPoint("Invite new family members")
                                        bulletPoint("Manage family settings")
                                        bulletPoint("See all shared stories")
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(12)
                            }
                            
                            VStack(spacing: 12) {
                                Button(action: createFamily) {
                                    Text("Create Family")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(familyName.isEmpty ? Color.gray : terracotta)
                                        .cornerRadius(12)
                                }
                                .disabled(familyName.isEmpty)
                            }
                            .padding(.bottom, 32)
                        }
                        .padding()
                        .onChange(of: isTextFieldFocused) { focused in
                            if focused {
                                // Add subtle haptic feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo("familyNameField", anchor: .center)
                                }
                            }
                        }
                    }
                }
                .keyboardAdaptive()
                
                if showSuccessMessage {
                    successOverlay
                }
            }
            .navigationTitle("Create Family")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(accentColor)
                }
            }
        }
    }
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(terracotta)
                .font(.caption)
                .padding(.top, 2)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.black.opacity(0.7))
            
            Spacer()
        }
    }
    
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Family Created!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("You can now invite family members to start sharing stories together.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                
                Button("Continue") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(8)
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(16)
            .padding(.horizontal, 40)
        }
    }
    
    private func createFamily() {
        familyManager.createFamily(name: familyName, adminProfile: profileVM.selectedProfile)
        
        withAnimation {
            showSuccessMessage = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            dismiss()
        }
    }
}

// MARK: - Join Family View

struct JoinFamilyView: View {
    @EnvironmentObject var familyManager: FamilyManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var inviteCode: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @FocusState private var isCodeFieldFocused: Bool
    
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let backgroundColor = Color(red: 0.98, green: 0.94, blue: 0.86)
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundColor.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        VStack(spacing: 16) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 60))
                                .foregroundColor(terracotta)
                            
                            Text("Join a Family")
                                .font(.customSerifFallback(size: 28))
                                .fontWeight(.bold)
                                .foregroundColor(accentColor)
                            
                            Text("Enter the invite code shared by your family member")
                                .font(.body)
                                .foregroundColor(.black.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 32)
                        
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Invite Code")
                                    .font(.headline)
                                    .foregroundColor(accentColor)
                                
                                TextField("Enter 6-digit code", text: $inviteCode)
                                    .font(.system(.title2, design: .monospaced))
                                    .foregroundColor(accentColor)
                                    .fontWeight(.bold)
                                    .textCase(.uppercase)
                                    .multilineTextAlignment(.center)
                                    .focused($isCodeFieldFocused)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white)
                                            .shadow(
                                                color: isCodeFieldFocused ? terracotta.opacity(0.3) : Color.clear,
                                                radius: isCodeFieldFocused ? 8 : 0
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                isCodeFieldFocused ? terracotta : Color.gray.opacity(0.3),
                                                lineWidth: isCodeFieldFocused ? 2 : 1
                                            )
                                    )
                                    .scaleEffect(isCodeFieldFocused ? 1.02 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: isCodeFieldFocused)
                                    .onChange(of: inviteCode) { newValue in
                                        inviteCode = String(newValue.prefix(6)).uppercased()
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Once you join, you'll be able to:")
                                    .font(.subheadline)
                                    .foregroundColor(accentColor)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    bulletPoint("Listen to family stories")
                                    bulletPoint("Add reactions and comments")
                                    bulletPoint("Share your own memories")
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(12)
                        }
                        
                        VStack(spacing: 12) {
                            Button(action: joinFamily) {
                                Text("Join Family")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(inviteCode.count == 6 ? terracotta : Color.gray)
                                    .cornerRadius(12)
                            }
                            .disabled(inviteCode.count != 6)
                        }
                        .padding(.bottom, 32)
                    }
                    .padding()
                }
                .keyboardAdaptive()
            }
            .navigationTitle("Join Family")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(accentColor)
                }
            }
            .onChange(of: isCodeFieldFocused) { focused in
                if focused {
                    // Add subtle haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .alert("Success!", isPresented: $showSuccess) {
                Button("Continue") { dismiss() }
            } message: {
                Text("Welcome to the family! You can now see and share stories together.")
            }
        }
    }
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(terracotta)
                .font(.caption)
                .padding(.top, 2)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.black.opacity(0.7))
            
            Spacer()
        }
    }
    
    private func joinFamily() {
        let success = familyManager.joinFamilyWithCode(inviteCode)
        
        if success {
            showSuccess = true
        } else {
            errorMessage = "Invalid invite code. Please check with your family member for the correct code."
            showError = true
        }
    }
}

// MARK: - Invite Family View

struct InviteFamilyView: View {
    @EnvironmentObject var familyManager: FamilyManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var inviteEmail: String = ""
    @State private var inviteName: String = ""
    @State private var selectedRole: FamilyMember.FamilyRole = .member
    @State private var showInviteSent = false
    @FocusState private var focusedField: FocusedField?
    
    enum FocusedField {
        case name, email
    }
    
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let backgroundColor = Color(red: 0.98, green: 0.94, blue: 0.86)
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundColor.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            Text("Invite Family Member")
                                .font(.customSerifFallback(size: 24))
                                .fontWeight(.bold)
                                .foregroundColor(accentColor)
                            
                            if let family = familyManager.currentFamily {
                                shareCodeSection(inviteCode: family.inviteCode ?? "NONE")
                            }
                        }
                        .padding(.top, 32)
                        
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Name")
                                    .font(.headline)
                                    .foregroundColor(accentColor)
                                
                                TextField("Family member's name", text: $inviteName)
                                    .font(.body)
                                    .foregroundColor(accentColor)
                                    .focused($focusedField, equals: .name)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white)
                                            .shadow(
                                                color: focusedField == .name ? terracotta.opacity(0.3) : Color.clear,
                                                radius: focusedField == .name ? 8 : 0
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                focusedField == .name ? terracotta : Color.gray.opacity(0.3),
                                                lineWidth: focusedField == .name ? 2 : 1
                                            )
                                    )
                                    .scaleEffect(focusedField == .name ? 1.02 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: focusedField)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.headline)
                                    .foregroundColor(accentColor)
                                
                                TextField("email@example.com", text: $inviteEmail)
                                    .font(.body)
                                    .foregroundColor(accentColor)
                                    .focused($focusedField, equals: .email)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white)
                                            .shadow(
                                                color: focusedField == .email ? terracotta.opacity(0.3) : Color.clear,
                                                radius: focusedField == .email ? 8 : 0
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                focusedField == .email ? terracotta : Color.gray.opacity(0.3),
                                                lineWidth: focusedField == .email ? 2 : 1
                                            )
                                    )
                                    .scaleEffect(focusedField == .email ? 1.02 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: focusedField)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Role")
                                    .font(.headline)
                                    .foregroundColor(accentColor)
                                
                                Picker("Role", selection: $selectedRole) {
                                    ForEach(FamilyMember.FamilyRole.allCases, id: \.self) { role in
                                        if role != .admin { // Only admin can be admin
                                            Text(role.displayName).tag(role)
                                        }
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                        }
                        
                        VStack(spacing: 12) {
                            Button(action: sendInvite) {
                                Text("Send Invitation")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(canSendInvite ? terracotta : Color.gray)
                                    .cornerRadius(12)
                            }
                            .disabled(!canSendInvite)
                            
                            Text("They'll receive an invitation link to join your family")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.bottom, 32)
                    }
                    .padding()
                }
                .keyboardAdaptive()
            }
            .navigationBarHidden(true)
            .onChange(of: focusedField) { field in
                if field != nil {
                    // Add subtle haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }
            }
            .alert("Invitation Sent!", isPresented: $showInviteSent) {
                Button("Done") { dismiss() }
            } message: {
                Text("We've sent an invitation to \(inviteName). They'll be able to join your family stories!")
            }
        }
    }
    
    private func shareCodeSection(inviteCode: String) -> some View {
        VStack(spacing: 12) {
            Text("Family Invite Code")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            HStack {
                Text(inviteCode)
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(accentColor)
                
                Button(action: {
                    UIPasteboard.general.string = inviteCode
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(terracotta)
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(accentColor.opacity(0.3), lineWidth: 1)
            )
            
            Text("Share this code with family members to invite them")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }
    
    private var canSendInvite: Bool {
        !inviteName.isEmpty && !inviteEmail.isEmpty && inviteEmail.contains("@")
    }
    
    private func sendInvite() {
        familyManager.inviteFamilyMember(email: inviteEmail, name: inviteName, role: selectedRole)
        showInviteSent = true
    }
}

// MARK: - Family Members View

struct FamilyMembersView: View {
    @EnvironmentObject var familyManager: FamilyManager
    
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let backgroundColor = Color(red: 0.98, green: 0.94, blue: 0.86)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(familyManager.familyMembers) { member in
                    FamilyMemberCard(member: member)
                }
                
                if !familyManager.pendingInvitations.isEmpty {
                    pendingInvitationsSection
                }
            }
            .padding()
        }
        .background(backgroundColor)
    }
    
    private var pendingInvitationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pending Invitations")
                .font(.headline)
                .foregroundColor(accentColor)
                .padding(.horizontal)
            
            ForEach(familyManager.pendingInvitations.filter { $0.status == .pending }) { invitation in
                PendingInvitationCard(invitation: invitation)
            }
        }
    }
}

struct FamilyMemberCard: View {
    let member: FamilyMember
    
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    
    var body: some View {
        HStack(spacing: 16) {
            // Profile image
            Circle()
                .fill(terracotta.opacity(0.3))
                .frame(width: 60, height: 60)
                .overlay(
                    Group {
                        if let imageData = member.profileImage,
                           let image = UIImage(data: imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Text(String(member.name.prefix(1)))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(accentColor)
                        }
                    }
                )
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.name)
                        .font(.headline)
                        .foregroundColor(accentColor)
                    
                    if member.role == .admin {
                        Text("ADMIN")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(terracotta)
                            .cornerRadius(4)
                    }
                }
                
                Text(member.role.displayName)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text("Joined \(member.joinedDate, style: .date)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack {
                Circle()
                    .fill(member.isActive ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text(member.isActive ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct PendingInvitationCard: View {
    let invitation: FamilyInvitation
    
    private let backgroundColor = Color.yellow.opacity(0.1)
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(invitation.invitedEmail)
                    .font(.headline)
                    .foregroundColor(accentColor)
                
                Text("Invited by \(invitation.invitedBy)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text("Expires \(invitation.expirationDate, style: .date)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack {
                Image(systemName: "clock")
                    .foregroundColor(.orange)
                
                Text("Pending")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Family Settings View

struct FamilySettingsView: View {
    @EnvironmentObject var familyManager: FamilyManager
    @State private var showDeleteConfirmation = false
    
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let backgroundColor = Color(red: 0.98, green: 0.94, blue: 0.86)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Family Info Section
                familyInfoSection
                
                // Admin Controls
                if familyManager.isUserFamilyAdmin() {
                    adminControlsSection
                }
                
                // General Settings
                generalSettingsSection
            }
            .padding()
        }
        .background(backgroundColor)
    }
    
    private var familyInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Family Information")
                .font(.headline)
                .foregroundColor(accentColor)
            
            VStack(spacing: 8) {
                HStack {
                    Text("Family Name")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(familyManager.currentFamily?.name ?? "")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Created")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(familyManager.currentFamily?.createdDate ?? Date(), style: .date)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Members")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(familyManager.familyMembers.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Invite Code")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(familyManager.currentFamily?.inviteCode ?? "")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.medium)
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
        }
    }
    
    private var adminControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Admin Controls")
                .font(.headline)
                .foregroundColor(accentColor)
            
            VStack(spacing: 1) {
                settingsRow(
                    icon: "person.badge.plus",
                    title: "Invite Members",
                    subtitle: "Add new family members"
                ) {
                    // Action handled by parent view
                }
                
                settingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Generate New Code",
                    subtitle: "Create a new invite code"
                ) {
                    // Generate new code
                }
                
                settingsRow(
                    icon: "trash",
                    title: "Delete Family",
                    subtitle: "Permanently delete this family",
                    isDestructive: true
                ) {
                    showDeleteConfirmation = true
                }
            }
            .background(Color.white)
            .cornerRadius(12)
        }
    }
    
    private var generalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
                .foregroundColor(accentColor)
            
            VStack(spacing: 1) {
                settingsRow(
                    icon: "bell",
                    title: "Family Notifications",
                    subtitle: "Get notified of new stories"
                ) {
                    // Toggle notifications
                }
                
                settingsRow(
                    icon: "square.and.arrow.up",
                    title: "Share Family Code",
                    subtitle: "Invite others to join"
                ) {
                    // Share invite code
                }
                
                settingsRow(
                    icon: "questionmark.circle",
                    title: "Help & Support",
                    subtitle: "Get help with family features"
                ) {
                    // Open help
                }
            }
            .background(Color.white)
            .cornerRadius(12)
        }
    }
    
    private func settingsRow(
        icon: String,
        title: String,
        subtitle: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isDestructive ? .red : terracotta)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isDestructive ? .red : accentColor)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    CreateFamilyView()
        .environmentObject(FamilyManager.shared)
        .environmentObject(ProfileViewModel())
}

// MARK: - Keyboard Adaptive Extension

extension View {
    func keyboardAdaptive() -> some View {
        self.modifier(KeyboardAdaptive())
    }
}

struct KeyboardAdaptive: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                    let keyboardRectangle = keyboardFrame.cgRectValue
                    let keyboardHeight = keyboardRectangle.height
                    
                    // Get animation duration from notification
                    let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3
                    
                    withAnimation(.easeInOut(duration: duration)) {
                        self.keyboardHeight = keyboardHeight * 0.4 // Reduced padding for better spacing
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                // Get animation duration from notification
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3
                
                withAnimation(.easeInOut(duration: duration)) {
                    self.keyboardHeight = 0
                }
            }
    }
} 