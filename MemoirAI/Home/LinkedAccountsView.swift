import SwiftUI
import FirebaseAuth
import AuthenticationServices

/// Login methods belong to the account shared by all memoir profiles.
struct LinkedAccountsView: View {
    @ObservedObject private var auth = AuthenticationService.shared
    @State private var selectedProvider: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var isBusy: Bool { isWorking || auth.isLoading || auth.isDeletingAccount }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Linked Accounts")
                .font(LinenTheme.body(16, weight: .semibold))
            Text("Use Apple or Google to access all your profiles and memories on another device.")
                .font(LinenTheme.body(13))
                .foregroundStyle(.secondary)

            ForEach(["apple.com", "google.com"], id: \.self) { providerID in
                let provider = auth.user?.providerData.first { $0.providerID == providerID }
                let name = providerID == "apple.com" ? "Apple" : "Google"
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Group {
                            if providerID == "apple.com" {
                                Image(systemName: "apple.logo")
                                    .font(LinenTheme.body(24))
                            } else {
                                Image("GoogleLogo")
                                    .resizable()
                                    .scaledToFit()
                            }
                        }
                        .frame(width: 26, height: 26)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name).font(LinenTheme.body(15, weight: .medium))
                            Text(provider?.email ?? (provider == nil ? "Not linked" : "Linked"))
                                .fixedSize(horizontal: false, vertical: true)
                                .font(LinenTheme.body(12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if provider != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Linked")
                            Button("Manage") { selectedProvider = providerID }
                                .font(LinenTheme.body(13, weight: .medium))
                                .frame(minHeight: 44)
                        }
                    }
                    if provider == nil {
                        if providerID == "apple.com" {
                            SignInWithAppleButton(.signIn) { request in
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
                            .frame(height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
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
                                Text("Sign in with Google")
                                    .font(LinenTheme.body(15, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if providerID == "apple.com" { Divider() }
            }
            if isBusy { ProgressView("Updating account…").font(.footnote) }
        }
        .foregroundStyle(LinenTheme.ink)
        .disabled(isBusy || auth.user == nil)
        .confirmationDialog(
            "Manage \(selectedProvider == "apple.com" ? "Apple" : "Google")",
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
            Text("To change this login, link another method first, then disconnect this one and sign in with the account you want. Your profiles and memories stay here.")
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
}
