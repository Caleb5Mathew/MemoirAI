import SwiftUI

// MARK: - Speech Recognition Permission Alert
struct SpeechRecognitionPermissionAlert: View {
    @Binding var isPresented: Bool
    let onSettingsTap: () -> Void
    
    // App color theme
    private let backgroundColor = Color(red: 1.0, green: 0.96, blue: 0.89)
    private let cardColor = Color(red: 0.98, green: 0.93, blue: 0.80)
    private let accentColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let headerColor = Color(red: 0.07, green: 0.21, blue: 0.13)
    private let softGreen = Color(red: 0.15, green: 0.35, blue: 0.25)
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            // Main alert card
            VStack(spacing: 24) {
                // Header with icon
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(accentColor)
                    }
                    
                    Text("Enable Speech Recognition")
                        .font(.custom("Georgia-Bold", size: 24))
                        .foregroundColor(headerColor)
                        .multilineTextAlignment(.center)
                }
                
                // Description
                VStack(spacing: 12) {
                    Text("To transcribe your voice memories into text, we need permission to access speech recognition.")
                        .font(.custom("Georgia", size: 16))
                        .foregroundColor(.black.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    
                    Text("This helps you read and search through your memories later.")
                        .font(.custom("Georgia", size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to enable:")
                        .font(.custom("Georgia-Bold", size: 16))
                        .foregroundColor(headerColor)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        instructionRow(number: "1", text: "Tap 'Open Settings' below")
                        instructionRow(number: "2", text: "Find MemoirAI in the list")
                        instructionRow(number: "3", text: "Toggle 'Speech Recognition' to ON")
                        instructionRow(number: "4", text: "Return to the app")
                    }
                }
                .padding(.horizontal, 8)
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        onSettingsTap()
                        isPresented = false
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "gear")
                                .font(.system(size: 16, weight: .medium))
                            Text("Open Settings")
                                .font(.custom("Georgia-Bold", size: 16))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(accentColor)
                        )
                    }
                    
                    Button(action: { isPresented = false }) {
                        Text("Maybe Later")
                            .font(.custom("Georgia", size: 16))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColor)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPresented)
    }
    
    private func instructionRow(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(softGreen.opacity(0.2))
                    .frame(width: 24, height: 24)
                
                Text(number)
                    .font(.custom("Georgia-Bold", size: 12))
                    .foregroundColor(softGreen)
            }
            
            Text(text)
                .font(.custom("Georgia", size: 14))
                .foregroundColor(.black.opacity(0.8))
            
            Spacer()
        }
    }
}

// MARK: - Microphone Permission Alert
struct MicrophonePermissionAlert: View {
    @Binding var isPresented: Bool
    let onSettingsTap: () -> Void
    
    // App color theme
    private let backgroundColor = Color(red: 1.0, green: 0.96, blue: 0.89)
    private let cardColor = Color(red: 0.98, green: 0.93, blue: 0.80)
    private let accentColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let headerColor = Color(red: 0.07, green: 0.21, blue: 0.13)
    private let softGreen = Color(red: 0.15, green: 0.35, blue: 0.25)
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            // Main alert card
            VStack(spacing: 24) {
                // Header with icon
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "mic.circle")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(accentColor)
                    }
                    
                    Text("Enable Microphone Access")
                        .font(.custom("Georgia-Bold", size: 24))
                        .foregroundColor(headerColor)
                        .multilineTextAlignment(.center)
                }
                
                // Description
                VStack(spacing: 12) {
                    Text("To record your voice memories, we need permission to access your microphone.")
                        .font(.custom("Georgia", size: 16))
                        .foregroundColor(.black.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    
                    Text("Your recordings are stored locally and never shared without your permission.")
                        .font(.custom("Georgia", size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to enable:")
                        .font(.custom("Georgia-Bold", size: 16))
                        .foregroundColor(headerColor)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        instructionRow(number: "1", text: "Tap 'Open Settings' below")
                        instructionRow(number: "2", text: "Find MemoirAI in the list")
                        instructionRow(number: "3", text: "Toggle 'Microphone' to ON")
                        instructionRow(number: "4", text: "Return to the app")
                    }
                }
                .padding(.horizontal, 8)
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        onSettingsTap()
                        isPresented = false
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "gear")
                                .font(.system(size: 16, weight: .medium))
                            Text("Open Settings")
                                .font(.custom("Georgia-Bold", size: 16))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(accentColor)
                        )
                    }
                    
                    Button(action: { isPresented = false }) {
                        Text("Maybe Later")
                            .font(.custom("Georgia", size: 16))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColor)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPresented)
    }
    
    private func instructionRow(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(softGreen.opacity(0.2))
                    .frame(width: 24, height: 24)
                
                Text(number)
                    .font(.custom("Georgia-Bold", size: 12))
                    .foregroundColor(softGreen)
            }
            
            Text(text)
                .font(.custom("Georgia", size: 14))
                .foregroundColor(.black.opacity(0.8))
            
            Spacer()
        }
    }
}

// MARK: - Transcription Progress Alert
struct TranscriptionProgressAlert: View {
    @Binding var isPresented: Bool
    let processed: Int
    let total: Int
    let onDismiss: () -> Void
    
    // App color theme
    private let backgroundColor = Color(red: 1.0, green: 0.96, blue: 0.89)
    private let cardColor = Color(red: 0.98, green: 0.93, blue: 0.80)
    private let accentColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let headerColor = Color(red: 0.07, green: 0.21, blue: 0.13)
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            // Main alert card
            VStack(spacing: 24) {
                // Header with icon
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: accentColor))
                            .scaleEffect(1.5)
                    }
                    
                    Text("Transcribing Your Memories")
                        .font(.custom("Georgia-Bold", size: 24))
                        .foregroundColor(headerColor)
                        .multilineTextAlignment(.center)
                }
                
                // Progress info
                VStack(spacing: 16) {
                    Text("Converting your voice recordings to text...")
                        .font(.custom("Georgia", size: 16))
                        .foregroundColor(.black.opacity(0.8))
                        .multilineTextAlignment(.center)
                    
                    Text("\(processed) of \(total) completed")
                        .font(.custom("Georgia-Bold", size: 18))
                        .foregroundColor(accentColor)
                }
                
                // Progress bar
                VStack(spacing: 8) {
                    ProgressView(value: Double(processed), total: Double(max(total, 1)))
                        .progressViewStyle(LinearProgressViewStyle(tint: accentColor))
                        .scaleEffect(y: 2)
                    
                    Text("Please wait...")
                        .font(.custom("Georgia", size: 14))
                        .foregroundColor(.gray)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColor)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPresented)
    }
}

// MARK: - Preview
struct PermissionAlertViews_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            SpeechRecognitionPermissionAlert(
                isPresented: .constant(true),
                onSettingsTap: {}
            )
            
            MicrophonePermissionAlert(
                isPresented: .constant(true),
                onSettingsTap: {}
            )
            
            TranscriptionProgressAlert(
                isPresented: .constant(true),
                processed: 3,
                total: 10,
                onDismiss: {}
            )
        }
        .background(Color(red: 1.0, green: 0.96, blue: 0.89))
    }
} 