import SwiftUI

struct DownloadOptionsView: View {
    @Binding var isPresented: Bool
    let onSaveToPhotos: () -> Void
    let onSaveToFiles: () -> Void
    
    @State private var animationScale: CGFloat = 0.8
    @State private var animationOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissView()
                }
                .opacity(animationOpacity)
            
            // Content card
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Save Your Book")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundColor(Color(UIColor.label))
                    
                    Text("Choose how you'd like to save")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .padding(.top, 28)
                .padding(.bottom, 24)
                
                // Options
                VStack(spacing: 16) {
                    // Save to Photos option
                    Button(action: {
                        hapticFeedback()
                        dismissView()
                        onSaveToPhotos()
                    }) {
                        HStack(spacing: 16) {
                            // Icon with gradient background
                            ZStack {
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Save to Photos")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(Color(UIColor.label))
                                
                                Text("Save pages as images")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    // Save to Files option
                    Button(action: {
                        hapticFeedback()
                        dismissView()
                        onSaveToFiles()
                    }) {
                        HStack(spacing: 16) {
                            // Icon with gradient background
                            ZStack {
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.8), Color.red.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Save to Files")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(Color(UIColor.label))
                                
                                Text("Save as PDF document")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.horizontal, 20)
                
                // Cancel button
                Button(action: {
                    hapticFeedback()
                    dismissView()
                }) {
                    Text("Cancel")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(Color(UIColor.label))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(UIColor.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 32)
            .scaleEffect(animationScale)
            .opacity(animationOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                animationScale = 1.0
                animationOpacity = 1.0
            }
        }
    }
    
    private func dismissView() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            animationScale = 0.9
            animationOpacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isPresented = false
        }
    }
    
    private func hapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

// Custom button style with scale animation
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview
struct DownloadOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3)
                .ignoresSafeArea()
            
            DownloadOptionsView(
                isPresented: .constant(true),
                onSaveToPhotos: { print("Save to Photos") },
                onSaveToFiles: { print("Save to Files") }
            )
        }
        .preferredColorScheme(.light)
        
        ZStack {
            Color.gray.opacity(0.3)
                .ignoresSafeArea()
            
            DownloadOptionsView(
                isPresented: .constant(true),
                onSaveToPhotos: { print("Save to Photos") },
                onSaveToFiles: { print("Save to Files") }
            )
        }
        .preferredColorScheme(.dark)
    }
}