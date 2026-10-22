//
//  WelcomeAuthView.swift
//  MemoirAI
//
//  Shown exactly once after onboarding and its paywall. Offers to attach
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

    @ScaledMetric(relativeTo: .body) private var authButtonHeight: CGFloat = 50

    var body: some View {
        ZStack {
            LinenTheme.paper.ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                    Spacer(minLength: 48)

                VStack(spacing: 14) {
                    Image("MemoirBrandIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .accessibilityHidden(true)

                    Text("Welcome to Memoir")
                        .font(LinenTheme.heading(25))
                        .fontWeight(.bold)
                        .foregroundColor(LinenTheme.ink)
                        .multilineTextAlignment(.center)

                    Text("Save your family's stories to an account so they're never lost.")
                        .font(LinenTheme.body(16))
                        .foregroundColor(LinenTheme.ink.opacity(0.75))
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
                    .frame(maxWidth: .infinity)
                    .frame(height: authButtonHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button(action: handleGoogle) {
                        HStack(spacing: 10) {
                            Image("GoogleLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Continue with Google")
                                .font(LinenTheme.body(16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: authButtonHeight)
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
                                .font(LinenTheme.body(16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: authButtonHeight)
                        .background(LinenTheme.accent)
                        .foregroundColor(LinenTheme.onAccent)
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
                    .font(LinenTheme.body(15, weight: .medium))
                    .foregroundColor(LinenTheme.ink.opacity(0.6))
                    .frame(minHeight: 44)
                    .padding(.bottom, 28)
                    }
                    .frame(minHeight: geometry.size.height)
                    .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .linenScreen()
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
