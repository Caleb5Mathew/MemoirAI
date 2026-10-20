import SwiftUI
import AVFoundation
import CoreData

struct MemoryEnhancementGuidedSessionView: View {
    let memory: MemoryEntry
    let service: MemoryEnhancementService
    let profileDisplayName: String?
    let transcriptionGlossary: [String]
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
    @State private var recordingTimer: Timer?

    /// After Stop: review transcript before submitting to the session.
    @State private var showReviewSheet = false
    @State private var pendingTranscript: String = ""
    @State private var isAwaitingFileTranscription = false
    @State private var pendingTranscriptionError: String?
    @State private var showCloudTranscriptionDisclosure = false
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var transcriptionRequestID = UUID()

    @State private var isMemoryTextExpanded = false
    @State private var memoryAudioPlayer: AVAudioPlayer?
    @State private var remoteMemoryAudioPlayer: AVPlayer?
    @State private var remoteMemoryPlaybackObserver: NSObjectProtocol?
    @State private var isMemoryAudioPlaying = false

    @Environment(\.scenePhase) private var scenePhase

    private var terracotta: Color { LinenTheme.accent }
    private var header: Color { LinenTheme.ink }
    private var cream: Color { LinenTheme.paper }
    private var surfaceStroke: Color { LinenTheme.line }
    private var textSecondary: Color { LinenTheme.secondary }
    private var softCream: Color { LinenTheme.surface }

    init(
        memory: MemoryEntry,
        service: MemoryEnhancementService,
        profileDisplayName: String?,
        transcriptionGlossary: [String],
        relationshipStyleProfileName: Bool,
        onComplete: @escaping (CharacterDetails) -> Void,
        onBack: @escaping () -> Void,
        onPartialSave: ((CharacterDetails) async -> Void)? = nil
    ) {
        self.memory = memory
        self.service = service
        self.profileDisplayName = profileDisplayName
        self.transcriptionGlossary = transcriptionGlossary
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
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Answer by voice. Tap Record, then Stop to review and send.")
                                    .font(LinenTheme.body(14, weight: .medium))
                                    .foregroundStyle(LinenTheme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                memoryPreviewCard

                                if !vm.currentQuestion.isEmpty {
                                    progressRow
                                }

                                questionCard

                                if let err = vm.errorMessage {
                                    Text(err)
                                        .font(LinenTheme.body(13))
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
                                        .font(LinenTheme.body(14))
                                        .foregroundStyle(LinenTheme.secondary)
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(LinenTheme.surface)
                                        )
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                            .padding(.bottom, 16)
                        }

                        VStack(spacing: 0) {
                            Divider()
                                .opacity(0.12)
                            recordPrimaryButton
                                .padding(.horizontal, 24)
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
                                .font(LinenTheme.body(15, weight: .semibold))
                                .foregroundStyle(header)
                        }
                        .padding(28)
                        .background(LinenTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .alert(CloudTranscriptionDisclosure.title, isPresented: $showCloudTranscriptionDisclosure) {
            Button("Not Now", role: .cancel) {}
            Button("Continue") {
                CloudTranscriptionDisclosure.accept()
                startRecording()
            }
        } message: {
            Text(CloudTranscriptionDisclosure.message)
        }
    }

    private var progressRow: some View {
        let answered = vm.turns.count
        let current = min(answered + 1, MemoryEnhancementSessionRules.maxSessionTurns)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Question \(current)")
                .font(LinenTheme.body(13, weight: .semibold))
                .foregroundStyle(textSecondary)
            if !vm.rubricTierCaption.isEmpty {
                Text(vm.rubricTierCaption)
                    .font(LinenTheme.body(11, weight: .medium))
                    .foregroundStyle(textSecondary.opacity(0.75))
            }
            Text("Usually 2 to 3 short answers · up to \(MemoryEnhancementSessionRules.maxSessionTurns)")
                .font(LinenTheme.body(12, weight: .medium))
                .foregroundStyle(textSecondary.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memoryPreviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(memory.prompt ?? "Memory")
                .font(LinenTheme.heading(20))
                .foregroundStyle(header)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let url = memory.availableAudioURL {
                compactMemoryAudioRow(url: url)
            }

            if let saved = memory.text, !saved.isEmpty {
                Text(saved)
                    .font(LinenTheme.body(16))
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
                            .font(LinenTheme.body(15, weight: .semibold))
                            .foregroundStyle(terracotta)
                    }
                    .buttonStyle(.plain)
                }
            } else if !memory.hasAudio {
                Text("No transcription yet. Use the recording below to add details.")
                    .font(LinenTheme.body(14))
                    .foregroundStyle(LinenTheme.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinenTheme.card)
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
                        .font(LinenTheme.body(16, weight: .semibold))
                        .foregroundStyle(terracotta)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Original recording")
                        .font(LinenTheme.body(12, weight: .semibold))
                        .foregroundStyle(textSecondary)
                    Text(isMemoryAudioPlaying ? "Playing…" : "Listen to this memory")
                        .font(LinenTheme.body(14, weight: .medium))
                        .foregroundStyle(header)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinenTheme.surface)
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
                    .font(LinenTheme.body(16, weight: .semibold))
                    .foregroundStyle(header)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(LinenTheme.surface)
                    )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Text("Enhance this memory")
                .font(LinenTheme.heading(22))
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
                    .font(LinenTheme.heading(18))
                    .foregroundStyle(header.opacity(0.55))
            } else {
                Text(vm.currentQuestion)
                    .font(LinenTheme.heading(20))
                    .foregroundStyle(header)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineSpacing(4)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinenTheme.card)
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
                            .font(LinenTheme.body(16, weight: .semibold))
                        Text("Record")
                            .font(LinenTheme.body(16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(LinenTheme.onAccent)
                    .background(
                        LinearGradient(
                            colors: [terracotta, terracotta],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                }
                .buttonStyle(.plain)
                .disabled(vm.isAnalyzing || vm.isBootstrapping || vm.currentQuestion.isEmpty)
            } else {
                Button {
                    stopRecordingAndPresentReview()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.fill")
                            .font(LinenTheme.body(16, weight: .semibold))
                        Text("Stop")
                            .font(LinenTheme.body(16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(LinenTheme.onAccent)
                    .background(Color.red.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reviewTranscriptSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review what we heard")
                    .font(LinenTheme.heading(20))
                    .foregroundStyle(header)

                if isAwaitingFileTranscription {
                    ProgressView("Transcribing…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else if pendingTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(pendingTranscriptionError ?? "We didn’t catch speech. Try recording again in a quieter spot.")
                        .font(LinenTheme.body(14))
                        .foregroundStyle(pendingTranscriptionError == nil ? Color.secondary : Color.red)
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
                        Text("Record Again")
                            .font(LinenTheme.body(16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(header)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(LinenTheme.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(header.opacity(0.25), lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        if pendingTranscriptionError != nil {
                            transcribePendingRecording()
                        } else {
                            Task {
                                let text = pendingTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                                showReviewSheet = false
                                await vm.submitAnswer(text)
                                discardPendingRecording()
                            }
                        }
                    } label: {
                        Text(pendingTranscriptionError == nil ? "Submit" : "Try Again")
                            .font(LinenTheme.body(16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(LinenTheme.onAccent)
                            .background(
                                LinearGradient(
                                    colors: [terracotta, terracotta],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        vm.isAnalyzing ||
                        isAwaitingFileTranscription ||
                        (pendingTranscriptionError == nil && pendingTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                }
            }
            .padding(24)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func discardPendingRecording() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcriptionRequestID = UUID()
        pendingTranscript = ""
        pendingTranscriptionError = nil
        isAwaitingFileTranscription = false
        if let url = audioURL {
            try? FileManager.default.removeItem(at: url)
            audioURL = nil
        }
    }

    private func stopRecordingAndPresentReview() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioRecorder?.stop()
        isRecording = false
        audioMonitor.stopMonitoring()
        realTimeTranscription.stopTranscription()
        _ = realTimeTranscription.getFinalTranscript()
        pendingTranscript = ""
        pendingTranscriptionError = nil
        showReviewSheet = true
        transcribePendingRecording()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func transcribePendingRecording() {
        guard let url = audioURL else {
            pendingTranscriptionError = EnhancementVoiceTranscriptionError.invalidRecording.localizedDescription
            return
        }
        isAwaitingFileTranscription = true
        pendingTranscriptionError = nil
        transcriptionTask?.cancel()
        let requestID = UUID()
        transcriptionRequestID = requestID
        transcriptionTask = Task {
            do {
                let text = try await EnhancementVoiceTranscriptionService.shared.transcribe(
                    url: url,
                    glossary: transcriptionGlossary
                )
                guard !Task.isCancelled,
                      transcriptionRequestID == requestID,
                      audioURL == url else { return }
                pendingTranscript = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                guard !Task.isCancelled,
                      transcriptionRequestID == requestID,
                      audioURL == url else { return }
                pendingTranscript = ""
                pendingTranscriptionError = error.localizedDescription
            }
            guard transcriptionRequestID == requestID, audioURL == url else { return }
            isAwaitingFileTranscription = false
            transcriptionTask = nil
        }
    }

    // MARK: - Memory playback

    private func toggleMemoryPlayback(url: URL) {
        if !url.isFileURL {
            if isMemoryAudioPlaying {
                stopMemoryPlayback()
                return
            }
            let player = AVPlayer(url: url)
            remoteMemoryAudioPlayer = player
            remoteMemoryPlaybackObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    stopMemoryPlayback()
                }
            }
            player.play()
            isMemoryAudioPlaying = true
            return
        }
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
        remoteMemoryAudioPlayer?.pause()
        remoteMemoryAudioPlayer = nil
        if let remoteMemoryPlaybackObserver {
            NotificationCenter.default.removeObserver(remoteMemoryPlaybackObserver)
            self.remoteMemoryPlaybackObserver = nil
        }
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
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcriptionRequestID = UUID()
        recordingTimer?.invalidate()
        recordingTimer = nil
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
        guard CloudTranscriptionDisclosure.isAccepted() else {
            showCloudTranscriptionDisclosure = true
            return
        }
        guard permissionManager.isMicrophoneAuthorized else {
            permissionManager.requestMicrophonePermission {
                startRecording()
            }
            return
        }
        pendingTranscript = ""
        let filename = UUID().uuidString + ".m4a"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record(forDuration: RecordingDurationPolicy.maximumRecordingDuration) else {
                print("Guided session recorder refused to start")
                return
            }
            audioRecorder = recorder
            audioURL = fileURL
            isRecording = true
            audioMonitor.startMonitoring(recorder: recorder)
            realTimeTranscription.startTranscription()
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                if RecordingDurationPolicy.shouldStop(elapsed: recorder.currentTime) || !recorder.isRecording {
                    stopRecordingAndPresentReview()
                }
            }
            try? AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Guided session recorder: \(error)")
        }
    }
}
