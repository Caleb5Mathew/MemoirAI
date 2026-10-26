import SwiftUI
import FirebaseAuth
import AuthenticationServices

enum AccountProviderPresentation {
    static func name(for providerID: String?) -> String {
        switch providerID {
        case "apple.com": return "Apple"
        case "google.com": return "Google"
        case "password": return "Email"
        default: return "account"
        }
    }
}

struct AccountBackupView: View {
    @ObservedObject private var auth = AuthenticationService.shared
    @State private var showEmail = false

    private var isGuest: Bool {
        guard let user = auth.user else { return true }
        return AuthenticationService.shared.isGuestUser(user)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: isGuest ? "icloud" : "checkmark.icloud.fill")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(isGuest ? LinenTheme.accent : LinenTheme.forest)
                        .frame(width: 44, height: 44)
                        .background(LinenTheme.surface, in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isGuest ? "Back up your memoir" : "Account connected")
                            .font(LinenTheme.body(17, weight: .semibold))
                        Text(isGuest ? "Sign in once to use it on another device." : (auth.user?.email ?? "Signed in"))
                            .font(LinenTheme.body(14))
                            .foregroundStyle(LinenTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LinkedAccountsView()

                if auth.user != nil && isGuest {
                    Button {
                        showEmail = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope")
                                .frame(width: 24)
                            Text("Continue with email")
                                .font(LinenTheme.body(16, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LinenTheme.secondary)
                        }
                        .foregroundStyle(LinenTheme.ink)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("accountBackupEmail")
                }
            }
            .padding(24)
            .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
        }
        .linenScreen()
        .analyticsScreen("account_backup")
        .navigationTitle("Account & backup")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEmail) { EmailAuthSheet() }
    }
}

/// Login methods belong to the account shared by all memoir profiles.
struct LinkedAccountsView: View {
    @ObservedObject private var auth = AuthenticationService.shared
    @State private var selectedProvider: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var isBusy: Bool { isWorking || auth.isLoading || auth.isDeletingAccount }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in methods")
                .font(LinenTheme.body(15, weight: .semibold))

            ForEach(["apple.com", "google.com", "password"], id: \.self) { providerID in
                if let provider = auth.user?.providerData.first(where: { $0.providerID == providerID }) {
                    linkedProviderRow(providerID: providerID, email: provider.email)
                } else if providerID == "apple.com" {
                    appleSignInButton
                } else if providerID == "google.com" {
                    googleSignInButton
                }
            }

            if isBusy {
                ProgressView("Updating…")
                    .font(LinenTheme.body(13))
            }
        }
        .foregroundStyle(LinenTheme.ink)
        .disabled(isBusy || auth.user == nil)
        .confirmationDialog(
            "Manage \(AccountProviderPresentation.name(for: selectedProvider))",
            isPresented: Binding(get: { selectedProvider != nil }, set: { if !$0 { selectedProvider = nil } }),
            titleVisibility: .visible
        ) {
            if let providerID = selectedProvider,
               LinkedAccountPolicy.canDisconnect(
                   providerID: providerID,
                   linkedProviderIDs: auth.user?.providerData.map(\.providerID) ?? []
               ) {
                Button("Disconnect", role: .destructive) {
                    isWorking = true
                    Task { @MainActor in
                        defer { isWorking = false }
                        do { try await auth.disconnectAccount(providerID: providerID) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            }
            Button("Cancel", role: .cancel) { selectedProvider = nil }
        } message: {
            Text("Link another method before disconnecting this one.")
        }
        .alert("Account update failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func linkedProviderRow(providerID: String, email: String?) -> some View {
        Button {
            selectedProvider = providerID
        } label: {
            HStack(spacing: 12) {
                providerIcon(providerID)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AccountProviderPresentation.name(for: providerID))
                        .font(LinenTheme.body(16, weight: .medium))
                    Text(email ?? "Connected")
                        .font(LinenTheme.body(13))
                        .foregroundStyle(LinenTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("Manage")
                    .font(LinenTheme.body(13, weight: .medium))
                    .foregroundStyle(LinenTheme.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LinenTheme.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(AccountProviderPresentation.name(for: providerID)), connected")
        .accessibilityHint("Opens account options")
    }

    private var appleSignInButton: some View {
        SignInWithAppleButton(.continue) { request in
            isWorking = true
            request.nonce = auth.prepareAppleSignIn()
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            Task { @MainActor in
                defer { isWorking = false }
                do {
                    let authorization = try result.get()
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                        throw AuthenticationService.AuthError.invalidCredential
                    }
                    try await auth.linkAppleAccount(credential: credential, preserveCurrentAccount: true)
                } catch {
                    let nsError = error as NSError
                    if !(nsError.domain == ASAuthorizationError.errorDomain && nsError.code == ASAuthorizationError.canceled.rawValue) {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var googleSignInButton: some View {
        Button {
            isWorking = true
            Task { @MainActor in
                defer { isWorking = false }
                do {
                    try await auth.linkGoogleAccount(preserveCurrentAccount: true)
                } catch {
                    let nsError = error as NSError
                    if !(nsError.domain == "com.google.GIDSignIn" && nsError.code == -5) {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image("GoogleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text("Continue with Google")
                    .font(LinenTheme.body(16, weight: .semibold))
            }
            .foregroundStyle(LinenTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(LinenTheme.line))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func providerIcon(_ providerID: String) -> some View {
        if providerID == "apple.com" {
            Image(systemName: "apple.logo")
                .font(.system(size: 21))
                .frame(width: 28, height: 28)
        } else if providerID == "google.com" {
            Image("GoogleLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "envelope")
                .font(.system(size: 19))
                .frame(width: 28, height: 28)
        }
    }

}
