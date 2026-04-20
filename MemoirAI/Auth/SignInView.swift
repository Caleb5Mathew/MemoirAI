//
//  SignInView.swift
//  MemoirAI
//
//  Sign in screen with Google authentication
//

import SwiftUI

struct SignInView: View {
    @StateObject private var authService = AuthenticationService.shared
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Colors matching app theme
    private let backgroundColor = Color(red: 0.98, green: 0.94, blue: 0.86)
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo / Branding
                VStack(spacing: 16) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 60))
                        .foregroundColor(terracotta)
                    
                    Text("MemoirAI")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                        .foregroundColor(accentColor)
                    
                    Text("Preserve your stories for generations")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 60)
                
                Spacer()
                
                // Sign In Buttons
                VStack(spacing: 16) {
                    Text("Sign in to sync your memories")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.5))
                        .padding(.bottom, 8)
                    
                    // Sign in with Google
                    Button(action: signInWithGoogle) {
                        HStack(spacing: 12) {
                            // Google "G" logo
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 24, height: 24)
                                Text("G")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                            
                            Text("Sign in with Google")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .foregroundColor(.black.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    }
                    .disabled(authService.isLoading)
                }
                .padding(.horizontal, 32)
                
                // Loading indicator
                if authService.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: terracotta))
                        .padding(.top, 24)
                }
                
                Spacer()
                
                // Privacy note
                VStack(spacing: 8) {
                    Text("By signing in, you agree to our")
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.4))
                    
                    HStack(spacing: 4) {
                        Link("Terms of Service", destination: URL(string: "https://memoirai.app/terms")!)
                        Text("and")
                        Link("Privacy Policy", destination: URL(string: "https://memoirai.app/privacy")!)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(terracotta)
                }
                .padding(.bottom, 32)
            }
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Google Sign In
    
    private func signInWithGoogle() {
        Task {
            do {
                try await authService.signInWithGoogle()
            } catch {
                showError(error)
            }
        }
    }
    
    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// MARK: - Skip Sign In Button (Optional)

struct SkipSignInButton: View {
    let onSkip: () -> Void
    
    var body: some View {
        Button(action: onSkip) {
            Text("Continue without signing in")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)
                .underline()
        }
    }
}

#Preview {
    SignInView()
}
