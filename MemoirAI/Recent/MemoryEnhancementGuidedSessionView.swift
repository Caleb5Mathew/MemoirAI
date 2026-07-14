import SwiftUI
import AVFoundation
import CoreData

struct MemoryEnhancementGuidedSessionView: View {
    let memory: MemoryEntry
    let service: MemoryEnhancementService
    let profileDisplayName: String?
    let relationshipStyleProfileName: Bool
    let onComplete: (CharacterDetails) -> Void
    let onBack: () -> Void
    let onPartialSave: ((CharacterDetails) async -> Void)?

    @StateObject private var vm: MemoryEnhancementGuidedSessionViewModel
    @StateObject private var audioMonitor = AudioLevelMonitor()
    @StateObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var realTimeTranscription = RealTimeTranscriptionManager.shared

    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioURL: URL?
    @State private var isRecording = false

    /// After Stop: review transcript before submitting to the session.
    @State private var showReviewSheet = false
    @State private var pendingTranscript: String = ""
    @State private var isAwaitingFileTranscription = false

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
                                Text("Answer by voice. Tap Record, then Stop to review and send.")
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

                                RealTimeWaveformView(
                                    audioMonitor: audioMonitor,
                                    isRecording: isRecording,
                                    isPaused: false
                                )
                                .frame(maxWidth: .infinity)

                                if realTimeTranscription.isTranscribing && !realTimeTranscription.currentTranscript.isEmpty {
                                    Text(realTimeTranscription.currentTranscript)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color.black.opacity(0.05))
                                        )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 16)
                        }

                        VStack(spacing: 0) {
                            Divider()
                                .opacity(0.12)
                            recordPrimaryButton
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
            Task { await vm.bootstrapIfNeeded() }
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
            cleanupRecording()
        }
        .fullScreenCover(isPresented: $permissionManager.showMicrophonePermissionAlert) {
            MicrophonePermissionAlert(
                isPresented: $permissionManager.showMicrophonePermissionAlert,
                onSettingsTap: permissionManager.openSettings
            )
        }
        .sheet(isPresented: $showReviewSheet) {
            reviewTranscriptSheet
        }
    }

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
                Text("No transcription yet — use the recording below to add details.")
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

    private var topBar: some View {
        HStack(alignment: .center) {
            Button {
                if showReviewSheet {
                    showReviewSheet = false
                    discardPendingRecording()
                } else {
                    cleanupRecording()
                    vm.persistDraft()
                    Task.detached { [vm] in
                        await vm.persistPartialProgress()
                    }
                    onBack()
                }
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

    private var recordPrimaryButton: some View {
        Group {
            if !isRecording {
                Button {
                    startRecording()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Record")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [terracotta, terracotta.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: terracotta.opacity(0.35), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(vm.isAnalyzing || vm.isBootstrapping || vm.currentQuestion.isEmpty)
            } else {
                Button {
                    stopRecordingAndPresentReview()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Stop")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .foregroundStyle(.white)
                    .background(Color.red.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reviewTranscriptSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Review what we heard")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(header)

                if isAwaitingFileTranscription {
                    ProgressView("Transcribing…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else if pendingTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("We didn’t catch speech. Try recording again in a quieter spot.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(pendingTranscript)
                            .font(.body)
                            .foregroundStyle(header.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120)
                }

                HStack(spacing: 12) {
                    Button {
                        showReviewSheet = false
                        discardPendingRecording()
                    } label: {
                        Text("Re-record")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(header)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(header.opacity(0.25), lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            let text = pendingTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                            showReviewSheet = false
                            await vm.submitAnswer(text)
                            discardPendingRecording()
                        }
                    } label: {
                        Text("Submit")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(
                                LinearGradient(
                                    colors: [terracotta, terracotta.opacity(0.9)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isAnalyzing || isAwaitingFileTranscription || pendingTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func discardPendingRecording() {
        pendingTranscript = ""
        isAwaitingFileTranscription = false
        if let url = audioURL {
            try? FileManager.default.removeItem(at: url)
            audioURL = nil
        }
    }

    private func stopRecordingAndPresentReview() {
        audioRecorder?.stop()
        isRecording = false
        audioMonitor.stopMonitoring()
        realTimeTranscription.stopTranscription()

        let spoken = realTimeTranscription.getFinalTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
        if !spoken.isEmpty {
            pendingTranscript = spoken
            isAwaitingFileTranscription = false
            showReviewSheet = true
        } else if let url = audioURL {
            isAwaitingFileTranscription = true
            pendingTranscript = ""
            showReviewSheet = true
            SpeechTranscriber.shared.transcribe(url: url) { result in
                DispatchQueue.main.async {
                    isAwaitingFileTranscription = false
                    switch result {
                    case .success(let t):
                        pendingTranscript = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    case .failure:
                        pendingTranscript = ""
                    }
                }
            }
        } else {
            pendingTranscript = ""
            isAwaitingFileTranscription = false
            showReviewSheet = true
        }
        try? AVAudioSession.sharedInstance().setActive(false)
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
            try setupAudioSession()
            memoryAudioPlayer = try AVAudioPlayer(contentsOf: url)
            memoryAudioPlayer?.prepareToPlay()
            memoryAudioPlayer?.play()
            isMemoryAudioPlaying = true
        } catch {
            print("Memory enhancement playback: \(error)")
            isMemoryAudioPlaying = false
        }
    }

    private func stopMemoryPlayback() {
        memoryAudioPlayer?.stop()
        memoryAudioPlayer = nil
        isMemoryAudioPlaying = false
    }

    // MARK: - Recording audio

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setMode(.measurement)
        try? session.setActive(true)
    }

    private func cleanupRecording() {
        if isRecording {
            audioRecorder?.stop()
        }
        audioMonitor.stopMonitoring()
        realTimeTranscription.stopTranscription()
        isRecording = false
        if let url = audioURL {
            try? FileManager.default.removeItem(at: url)
            audioURL = nil
        }
        audioRecorder = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func startRecording() {
        stopMemoryPlayback()
        guard permissionManager.isMicrophoneAuthorized else {
            permissionManager.requestMicrophonePermission()
            return
        }
        pendingTranscript = ""
        let filename = UUID().uuidString + ".caf"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            audioURL = fileURL
            isRecording = true
            if let recorder = audioRecorder {
                audioMonitor.startMonitoring(recorder: recorder)
            }
            realTimeTranscription.startTranscription()
            try? AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Guided session recorder: \(error)")
        }
    }
}
