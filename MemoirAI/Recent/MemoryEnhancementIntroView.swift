import SwiftUI

struct MemoryEnhancementIntroView: View {
    let onStartVoice: () -> Void
    let onEnhanceByTyping: () -> Void
    let onClose: () -> Void
    /// Guided enhancement requires its cloud service; both buttons disable when false.
    let voiceGuideAvailable: Bool

    private var accent: Color { LinenTheme.accent }
    private var header: Color { LinenTheme.ink }

    var body: some View {
        ZStack {
            LinenTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(LinenTheme.body(28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(header.opacity(0.55))
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer(minLength: 8)

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.12))
                            .frame(width: 72, height: 72)
                        Image(systemName: "sparkles")
                            .font(LinenTheme.body(30, weight: .medium))
                            .foregroundStyle(accent)
                    }

                    Text("Enhance for better images")
                        .font(LinenTheme.heading(25))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(header)

                    Text(
                        "Answer a few short questions, by voice or typing, so we can fill in who was there and what they looked like. " +
                        "That helps illustrated pages match your story without typing every field."
                    )
                    .font(LinenTheme.body(16))
                    .foregroundStyle(LinenTheme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                    if !voiceGuideAvailable {
                        Text("Guided enhancement is temporarily unavailable. Try again later.")
                            .font(LinenTheme.body(13))
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
                            Text("Answer by voice")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(LinenTheme.onAccent)
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
                            Text("Answer by typing")
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
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
        .font(LinenTheme.body(16))
    }
}
