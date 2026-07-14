//
//  WelcomeAuthView.swift
//  MemoirAI
//
//  Shown exactly once, on the very first app launch, before onboarding. Offers to attach
//  an account (Apple / Google / Email) to the auto-created anonymous session so the
//  person's stories survive reinstalls — or skip and continue as a guest.
//

import SwiftUI
import AuthenticationServices

struct WelcomeAuthView: View {
    @EnvironmentObject private var iCloudManager: iCloudManager
    @ObservedObject private var authService = AuthenticationService.shared

    @State private var showEmailSheet = false
    @State private var displayedError: String?

    /// Called once — after any successful auth outcome, or when the user taps Skip — so the
    /// caller can flip the "seen welcome" gate and continue into onboarding/main flow.
    let onFinished: () -> Void

    private let colors = OnboardingColorTheme()

    var body: some View {
        ZStack {
            colors.beige.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 48)

                VStack(spacing: 14) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 44))
                        .foregroundColor(colors.orange)

                    Text("Welcome to Memoir")
                        .font(.customSerifFallback(size: 30))
                        .fontWeight(.bold)
                        .foregroundColor(colors.deepGreen)
                        .multilineTextAlignment(.center)

                    Text("Save your family's stories to an account so they're never lost.")
                        .font(.body)
                        .foregroundColor(colors.deepGreen.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }

                Spacer(minLength: 48)

                VStack(spacing: 14) {
                    if let displayedError {
                        Text(displayedError)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }

                    SignInWithAppleButton(.signIn) { request in
                        let hashed = authService.prepareAppleSignIn()
                        request.nonce = hashed
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                                return
                            }
                            Task { await handleApple(credential) }
                        case .failure(let error):
                            handle(error)
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button(action: handleGoogle) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 22, height: 22)
                                Text("G")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                            Text("Continue with Google")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .foregroundColor(.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        displayedError = nil
                        showEmailSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                            Text("Continue with Email")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(colors.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if authService.isLoading {
                        ProgressView()
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 20)

                Button("Skip for now") {
                    onFinished()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(colors.deepGreen.opacity(0.6))
                .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showEmailSheet) {
            EmailAuthSheet { outcome in
                complete(outcome: outcome)
            }
        }
    }

    @MainActor
    private func handleApple(_ credential: ASAuthorizationAppleIDCredential) async {
        displayedError = nil
        do {
            let outcome = try await authService.linkAppleAccount(credential: credential)
            complete(outcome: outcome)
        } catch {
            displayedError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func handleGoogle() {
        Task {
            displayedError = nil
            do {
                let outcome = try await authService.linkGoogleAccount()
                complete(outcome: outcome)
            } catch {
                handle(error)
            }
        }
    }

    /// Apple/Google cancellation is a normal, expected user action — never shown as an error.
    private func handle(_ error: Error) {
        if isUserCancelled(error) { return }
        displayedError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationErrorDomain, nsError.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        // GIDSignInErrorCode.canceled == -5, domain "com.google.GIDSignIn" (GoogleSignIn SDK).
        if nsError.domain == "com.google.GIDSignIn", nsError.code == -5 {
            return true
        }
        return false
    }

    /// A `.signedInExistingAccount` outcome means this is a returning user whose account
    /// already has history — mark onboarding complete so they aren't forced through it again.
    /// `.linkedNewAccount` means a first-time user — leave onboarding untouched.
    private func complete(outcome: AuthenticationService.AccountLinkOutcome) {
        if outcome == .signedInExistingAccount {
            iCloudManager.completeOnboarding()
        }
        onFinished()
    }
}

#Preview {
    WelcomeAuthView(onFinished: {})
        .environmentObject(iCloudManager.shared)
}
