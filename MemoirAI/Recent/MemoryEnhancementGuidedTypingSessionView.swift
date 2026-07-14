import SwiftUI
import AVFoundation
import CoreData

/// Typing variant of the guided enhancement session. Reuses
/// `MemoryEnhancementGuidedSessionViewModel` so the same preflight, tiered
/// rubric, turn-analysis, and structured extraction logic runs end-to-end —
/// the only difference vs the voice flow is that answers come from a text
/// editor instead of a recorded transcript.
struct MemoryEnhancementGuidedTypingSessionView: View {
    let memory: MemoryEntry
    let service: MemoryEnhancementService
    let profileDisplayName: String?
    let relationshipStyleProfileName: Bool
    let onComplete: (CharacterDetails) -> Void
    let onBack: () -> Void
    let onPartialSave: ((CharacterDetails) async -> Void)?

    @StateObject private var vm: MemoryEnhancementGuidedSessionViewModel

    @State private var typedAnswer: String = ""
    @FocusState private var isAnswerFocused: Bool

    @State private var isMemoryTextExpanded = false
    @State private var memoryAudioPlayer: AVAudioPlayer?
    @State private var isMemoryAudioPlaying = false

    @Environment(\.scenePhase) private var scenePhase

    private var terracotta: Color { Color(red: 0.82, green: 0.45, blue: 0.32) }
    private var header: Color { Color(red: 0.07, green: 0.21, blue: 0.13) }
    private var cream: Color { Color(red: 0.98, green: 0.96, blue: 0.90) }
    private var surfaceStroke: Color { Color.black.opacity(0.08) }
    private var textSecondary: Color { Color(red: 0.5, green: 0.5, blue: 0.5) }
    private var softCream: Color { Color(red: 253 / 255, green: 234 / 255, blue: 198 / 255) }

    private var trimmedAnswer: String {
        typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedAnswer.isEmpty
            && !vm.currentQuestion.isEmpty
            && !vm.isAnalyzing
            && !vm.isBootstrapping
    }

    init(
        memory: MemoryEntry,
        service: MemoryEnhancementService,
        profileDisplayName: String?,
        relationshipStyleProfileName: Bool,
        onComplete: @escaping (CharacterDetails) -> Void,
        onBack: @escaping () -> Void,
        onPartialSave: ((CharacterDetails) async -> Void)? = nil
    ) {
        self.memory = memory
        self.service = service
        self.profileDisplayName = profileDisplayName
        self.relationshipStyleProfileName = relationshipStyleProfileName
        self.onComplete = onComplete
        self.onBack = onBack
        self.onPartialSave = onPartialSave
        _vm = StateObject(
            wrappedValue: MemoryEnhancementGuidedSessionViewModel(
                memory: memory,
                service: service,
                profileDisplayName: profileDisplayName,
                relationshipStyleProfileName: relationshipStyleProfileName,
                onFinished: { details in
                    onComplete(details)
                },
                onPartialSave: onPartialSave
            )
        )
    }

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ZStack {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                Text("Type your answer below. We’ll ask a few short questions and use them to enhance your characters.")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                memoryPreviewCard

                                if !vm.currentQuestion.isEmpty {
                                    progressRow
                                }

                                questionCard

                                if let err = vm.errorMessage {
                                    Text(err)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }

                                answerEditor
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 16)
                        }

                        VStack(spacing: 0) {
                            Divider()
                                .opacity(0.12)
                            submitPrimaryButton
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .padding(.bottom, 8)
                        }
                        .background(cream)
                    }

                    if vm.isAnalyzing || vm.isBootstrapping {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.1)
                                .tint(terracotta)
                            Text(vm.isBootstrapping ? "Preparing your question…" : "Thinking…")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(header)
                        }
                        .padding(28)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                    }
                }
            }
        }
        .onAppear {
            setupAudioSession()
            // Resume-from-draft: question already loaded before bootstrap; onChange may not fire.
            if !vm.currentQuestion.isEmpty {
                isAnswerFocused = true
            }
            Task { await vm.bootstrapIfNeeded() }
        }
        .onChange(of: vm.currentQuestion) { _, newValue in
            // Each new question loaded → clear text input and refocus.
            typedAnswer = ""
            if !newValue.isEmpty {
                isAnswerFocused = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                vm.persistDraft()
                Task { await vm.persistPartialProgress() }
            }
        }
        .onDisappear {
            stopMemoryPlayback()
            vm.persistDraft()
            if !vm.hasCompletedFullSession {
                Task { await vm.persistPartialProgress() }
            }
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            Button {
                vm.persistDraft()
                Task.detached { [vm] in
                    await vm.persistPartialProgress()
                }
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(header)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Text("Enhance this memory")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(header)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 8)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Memory preview

    private var memoryPreviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(memory.prompt ?? "Memory")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(header)
                .frame(maxWidth: .infinity, alignment: .leading)

            if memory.hasAudio, let url = memory.playbackURL {
                compactMemoryAudioRow(url: url)
            }

            if let saved = memory.text, !saved.isEmpty {
                Text(saved)
                    .font(.custom("Georgia", size: 17))
                    .multilineTextAlignment(.leading)
                    .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.13))
                    .lineSpacing(5)
                    .lineLimit(isMemoryTextExpanded ? nil : 3)
                    .padding(.vertical, 2)

                if saved.count > 150 || saved.filter({ $0 == "\n" }).count > 2 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isMemoryTextExpanded.toggle()
                        }
                    } label: {
                        Text(isMemoryTextExpanded ? "Show less" : "Read more")
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(terracotta)
                    }
                    .buttonStyle(.plain)
                }
            } else if !memory.hasAudio {
                Text("No transcription yet — answer the questions below to add details.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(surfaceStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func compactMemoryAudioRow(url: URL) -> some View {
        Button {
            toggleMemoryPlayback(url: url)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(terracotta.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: isMemoryAudioPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(terracotta)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Original recording")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(textSecondary)
                    Text(isMemoryAudioPlaying ? "Playing…" : "Listen to this memory")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(header)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(softCream.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(surfaceStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Question / progress

    private var progressRow: some View {
        let answered = vm.turns.count
        let current = min(answered + 1, MemoryEnhancementSessionRules.maxSessionTurns)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Question \(current)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textSecondary)
            if !vm.rubricTierCaption.isEmpty {
                Text(vm.rubricTierCaption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textSecondary.opacity(0.75))
            }
            Text("Usually 2–3 short answers · up to \(MemoryEnhancementSessionRules.maxSessionTurns)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(textSecondary.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var questionCard: some View {
        Group {
            if vm.currentQuestion.isEmpty {
                Text("Loading your first question…")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(header.opacity(0.55))
            } else {
                Text(vm.currentQuestion)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(header)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineSpacing(4)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(surfaceStroke, lineWidth: 1)
        )
    }

    // MARK: - Answer editor

    private var answerEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "Type your answer here…",
                text: $typedAnswer,
                axis: .vertical
            )
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled(false)
            .focused($isAnswerFocused)
            .lineLimit(4...10)
            .font(.system(size: 17))
            .foregroundStyle(header)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isAnswerFocused ? terracotta.opacity(0.55) : surfaceStroke,
                        lineWidth: isAnswerFocused ? 1.5 : 1
                    )
            )
            .disabled(vm.currentQuestion.isEmpty || vm.isAnalyzing || vm.isBootstrapping)
            .accessibilityIdentifier("enhancementTypingAnswerField")

            HStack(spacing: 8) {
                Spacer()
                Text("\(trimmedAnswer.count) characters")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textSecondary.opacity(0.85))
            }
        }
    }

    // MARK: - Submit

    private var submitPrimaryButton: some View {
        Button {
            submitTypedAnswer()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Submit Answer")
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: canSubmit
                        ? [terracotta, terracotta.opacity(0.92)]
                        : [Color.gray.opacity(0.55), Color.gray.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(
                color: canSubmit ? terracotta.opacity(0.35) : .clear,
                radius: 12,
                y: 6
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityIdentifier("enhancementTypingSubmitButton")
    }

    private func submitTypedAnswer() {
        let answer = trimmedAnswer
        guard !answer.isEmpty else { return }
        isAnswerFocused = false
        Task {
            await vm.submitAnswer(answer)
        }
    }

    // MARK: - Memory playback

    private func toggleMemoryPlayback(url: URL) {
        if isMemoryAudioPlaying {
            memoryAudioPlayer?.pause()
            isMemoryAudioPlaying = false
            return
        }
        if memoryAudioPlayer?.url == url, memoryAudioPlayer != nil {
            memoryAudioPlayer?.play()
            isMemoryAudioPlaying = true
            return
        }
        memoryAudioPlayer?.stop()
        do {
            setupAudioSession()
            memoryAudioPlayer = try AVAudioPlayer(contentsOf: url)
            memoryAudioPlayer?.prepareToPlay()
            memoryAudioPlayer?.play()
            isMemoryAudioPlaying = true
        } catch {
            print("Memory enhancement (typing) playback: \(error)")
            isMemoryAudioPlaying = false
        }
    }

    private func stopMemoryPlayback() {
        memoryAudioPlayer?.stop()
        memoryAudioPlayer = nil
        isMemoryAudioPlaying = false
    }

    private func setupAudioSession() {
        // Playback-only category — the typing flow never records.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [])
        try? session.setActive(true)
    }
}
