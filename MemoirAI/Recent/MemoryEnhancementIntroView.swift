import SwiftUI

struct MemoryEnhancementIntroView: View {
    let onStartVoice: () -> Void
    let onEnhanceByTyping: () -> Void
    let onClose: () -> Void
    /// Guided enhancement (voice or typing) requires OpenAI; both buttons disable when false.
    let voiceGuideAvailable: Bool

    private var accent: Color { Color(red: 0.88, green: 0.52, blue: 0.28) }
    private var header: Color { Color(red: 0.07, green: 0.21, blue: 0.13) }

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.96, blue: 0.90).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(header.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer(minLength: 8)

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.12))
                            .frame(width: 100, height: 100)
                        Image(systemName: "sparkles")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(accent)
                    }

                    Text("Enhance for better images")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(header)

                    Text(
                        "Answer a few short questions, by voice or typing, so we can fill in who was there and what they looked like. " +
                        "That helps illustrated pages match your story without typing every field."
                    )
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                    if !voiceGuideAvailable {
                        Text("Guided enhancement needs an OpenAI key in Info.plist. Add one to enable voice or typing enhancement.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        onStartVoice()
                    } label: {
                        HStack {
                            Image(systemName: "mic.fill")
                            Text("Enhance with Voice (Recommended)")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(voiceGuideAvailable ? accent : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(!voiceGuideAvailable)
                    .accessibilityIdentifier("enhancementIntroVoiceButton")

                    Button {
                        onEnhanceByTyping()
                    } label: {
                        HStack {
                            Image(systemName: "keyboard")
                            Text("Enhance by Typing")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(voiceGuideAvailable ? header : Color.gray)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    (voiceGuideAvailable ? header : Color.gray).opacity(0.35),
                                    lineWidth: 1.5
                                )
                        )
                    }
                    .disabled(!voiceGuideAvailable)
                    .accessibilityIdentifier("enhancementIntroTypingButton")
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 36)
            }
        }
    }
}
