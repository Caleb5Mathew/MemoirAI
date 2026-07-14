//
//  EmailAuthSheet.swift
//  MemoirAI
//
//  Segmented email/password auth sheet (Create Account / Sign In). Reused from
//  WelcomeAuthView (first-launch) and, separately, Settings (account linking).
//

import SwiftUI

/// Presents email/password create-account and sign-in forms in one sheet.
///
/// - Create Account: if the current Firebase user is anonymous, links the credential so
///   existing local/Firestore data is preserved (see `AuthenticationService.createEmailAccount`).
/// - Sign In: always signs into an existing account (never links) — used by returning users.
struct EmailAuthSheet: View {
    enum Mode: String, CaseIterable {
        case createAccount = "Create Account"
        case signIn = "Sign In"
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authService = AuthenticationService.shared

    @State private var mode: Mode
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var displayedError: String?
    @State private var resetConfirmation: String?
    @State private var isSubmitting = false

    /// Called after a successful create/sign-in with the resulting account outcome, right
    /// before the sheet dismisses itself.
    private let onSuccess: (AuthenticationService.AccountLinkOutcome) -> Void

    private let colors = OnboardingColorTheme()

    init(
        initialMode: Mode = .createAccount,
        onSuccess: @escaping (AuthenticationService.AccountLinkOutcome) -> Void = { _ in }
    ) {
        _mode = State(initialValue: initialMode)
        self.onSuccess = onSuccess
    }

    private var isEmailValid: Bool { AuthenticationService.isValidEmail(email) }
    private var isPasswordValid: Bool { AuthenticationService.isValidPassword(password) }
    private var canSubmit: Bool { isEmailValid && isPasswordValid && !isSubmitting }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.beige.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(.caption)
                            .foregroundColor(colors.deepGreen.opacity(0.7))
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(.caption)
                            .foregroundColor(colors.deepGreen.opacity(0.7))
                        SecureField(mode == .createAccount ? "At least 8 characters" : "Password", text: $password)
                            .textContentType(mode == .createAccount ? .newPassword : .password)
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if mode == .signIn {
                        Button {
                            Task { await sendReset() }
                        } label: {
                            Text("Forgot password?")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(colors.orange)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if let resetConfirmation {
                        Text(resetConfirmation)
                            .font(.footnote)
                            .foregroundColor(colors.deepGreen)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let displayedError {
                        Text(displayedError)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(mode == .createAccount ? "Create Account" : "Sign In")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(canSubmit ? colors.orange : colors.fadedGray)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle(mode == .createAccount ? "Create Account" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: mode) { _, _ in
            displayedError = nil
            resetConfirmation = nil
        }
    }

    private func submit() {
        guard canSubmit else { return }
        Task {
            displayedError = nil
            resetConfirmation = nil
            isSubmitting = true
            defer { isSubmitting = false }

            do {
                switch mode {
                case .createAccount:
                    try await authService.createEmailAccount(email: email, password: password)
                    onSuccess(.linkedNewAccount)
                case .signIn:
                    try await authService.signInWithEmail(email: email, password: password)
                    onSuccess(.signedInExistingAccount)
                }
                dismiss()
            } catch {
                displayedError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func sendReset() async {
        guard isEmailValid else {
            displayedError = AuthenticationService.AuthError.invalidEmail.errorDescription
            return
        }
        displayedError = nil
        do {
            try await authService.sendPasswordReset(email: email)
            resetConfirmation = "If an account exists for \(email), we've sent a password reset link."
        } catch {
            displayedError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    EmailAuthSheet()
}
