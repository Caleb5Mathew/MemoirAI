import SwiftUI
import AVFoundation
import CoreData
import PhotosUI
import Speech
import UIKit

enum RecordingLayoutPolicy {
    static func contentWidth(
        availableWidth: CGFloat,
        maximumWidth: CGFloat = AdaptiveLayoutPolicy.readableMaxWidth
    ) -> CGFloat {
        guard availableWidth.isFinite, maximumWidth.isFinite,
              availableWidth > 0, maximumWidth > 0 else { return 0 }
        return min(availableWidth, maximumWidth)
    }

    static func showsVoiceControls(isTextFocused: Bool) -> Bool {
        !isTextFocused
    }

    static func minimumTopSpacing(safeAreaTop: CGFloat) -> CGFloat {
        guard safeAreaTop.isFinite else { return 72 }
        return max(72, safeAreaTop + 44)
    }

    static func backButtonTopPadding(safeAreaTop: CGFloat) -> CGFloat {
        guard safeAreaTop.isFinite else { return 16 }
        return max(16, safeAreaTop + 12)
    }
}

struct RecordingExitConfirmationOverlay: View {
    let discard: () -> Void
    let keepEditing: () -> Void

    private let cream = LinenTheme.paper
    private let deepGreen = LinenTheme.ink
    private let terracotta = LinenTheme.accent

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture(perform: keepEditing)

            VStack(spacing: 18) {
                Text("Exit without saving?")
                    .font(LinenTheme.heading(24))
                    .foregroundColor(deepGreen)
                    .multilineTextAlignment(.center)

                Text("Your current recording and text will be lost.")
                    .font(.system(size: 16, design: .serif))
                    .foregroundColor(deepGreen.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    Button(action: discard) {
                        Text("Discard and Exit")
                            .font(LinenTheme.heading(17))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(terracotta)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: keepEditing) {
                        Text("Keep Editing")
                            .font(LinenTheme.heading(17))
                            .foregroundColor(deepGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(deepGreen.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(26)
            .background(cream)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(deepGreen.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
            .padding(.horizontal, 28)
            .frame(maxWidth: 440)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Exit without saving")
        .transition(.opacity)
        .zIndex(1_000)
    }
}

struct RecordingView: View {
    @State private var debugBanner: String?
    let prompt: MemoryPrompt
    let chapterTitle: String
    var memoirMode: MemoirMode? = nil
    /// Called first on `onDisappear` so the chapter map can clear selection before the full-screen dismiss animation ends (avoids hidden prompt node / stale border).
    var onRecordingDismiss: (() -> Void)? = nil
    /// When set, runs after a successful save instead of the default `dismiss()`. Used by the per-child queue wrapper to advance between child variants without tearing the cover down.
    var onSaveComplete: (() -> Void)? = nil
    /// Optional header label for sub-prompt flows, e.g., "1 of 3".
    var progressLabel: String? = nil
    @State private var isSaving = false
    @State private var showCloudTranscriptionDisclosure = false
    @State private var recordingStartErrorMessage: String?
    @State private var saveErrorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @StateObject private var audioMonitor = AudioLevelMonitor()
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var realTimeTranscription = RealTimeTranscriptionManager.shared
    @StateObject private var interruptionObserver = AudioSessionInterruptionObserver()

    @State private var typedText: String = ""
    @FocusState private var isTextFocused: Bool
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioURL: URL?
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var showExitConfirm = false
    @State private var showSaveToast = false
    @State private var activePromptText: String = ""
    @State private var showCustomQuestionSheet = false
    @State private var isUsingCustomQuestion = false
    @State private var powerLevel: Float = 0.0
    @State private var timer: Timer?
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?

    // Interruption / backgrounding — set when the system (not the user) paused
    // an in-progress recording, so the UI can explain why it's paused.
    @State private var interruptionBannerMessage: String? = nil

    // Recording safety-net parity with RecordMemoryView: hard cap, warning,
    // and auto-stop-and-save.
    @State private var showTimeoutWarning = false
    @State private var finalCountdown: Int? = nil
    private let maxRecordingDuration = RecordingDurationPolicy.maximumRecordingDuration
    private let warningThreshold = RecordingDurationPolicy.warningThreshold
    private let countdownStart = RecordingDurationPolicy.countdownStart

    @State private var photoItems: [PhotosPickerItem] = []

    // Colors
    let terracotta = LinenTheme.accent
    let softCream = LinenTheme.paper
    let overlayBlack = LinenTheme.paper.opacity(0.92)
    let accent = LinenTheme.forest

    // Grid layout for up to 8 images (4 columns)
    private var columns: [GridItem] {
        Array(repeating: .init(.flexible(), spacing: 8), count: 4)
    }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = RecordingLayoutPolicy.contentWidth(
                availableWidth: geo.size.width
            )
            let showsVoiceControls = RecordingLayoutPolicy.showsVoiceControls(
                isTextFocused: isTextFocused
            )
            ZStack {
                // Background: use the same chapter artwork people saw before opening this prompt.
                Group {
                    let chapterAsset = chapterImageAssetName(for: chapterTitle)
                    if let relationshipAsset = relationshipChapterImageAssetName(forChapterTitle: chapterTitle) {
                        Image(relationshipAsset)
                            .resizable()
                            .scaledToFill()
                    } else if UIImage(named: chapterAsset) != nil {
                        Image(chapterAsset)
                            .resizable()
                            .scaledToFill()
                    } else if let relationshipGradient = relationshipChapterGradient(forChapterTitle: chapterTitle) {
                        relationshipGradient
                    } else {
                        Color(red: 0.22, green: 0.22, blue: 0.24)
                    }
                }
                .frame(
                    width: geo.size.width,
                    height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
                )
                .ignoresSafeArea()
                overlayBlack.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        Spacer(minLength: RecordingLayoutPolicy.minimumTopSpacing(
                            safeAreaTop: geo.safeAreaInsets.top
                        ))
                            .accessibilityHidden(true)

                    // Prompt & audio controls
                    VStack(spacing: 12) {
                        // Interruption / backgrounding banner — only shown when the
                        // system (not the user) paused an in-progress recording.
                        if let message = interruptionBannerMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "pause.circle.fill")
                                    .font(LinenTheme.body(15, weight: .semibold))
                                Text(message)
                                    .font(LinenTheme.body(13, weight: .semibold))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .foregroundColor(LinenTheme.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(terracotta)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        VStack(spacing: 6) {
                            if let progressLabel = progressLabel {
                                Text(progressLabel)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(LinenTheme.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(LinenTheme.surface)
                                    .clipShape(Capsule())
                            }
                            Text("YOUR MEMORY")
                                .font(LinenTheme.body(11, weight: .semibold))
                                .tracking(1.6)
                                .foregroundStyle(LinenTheme.accent)
                            Text(activePromptText.isEmpty ? prompt.text : activePromptText)
                                .font(LinenTheme.heading(25))
                                .foregroundColor(LinenTheme.ink)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(nil)
                                .accessibilityIdentifier("recordingQuestionText")
                                .padding(.horizontal, 24)
                                .padding(.vertical, 18)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(LinenTheme.paper)
                                .cornerRadius(20)

                            if isUsingCustomQuestion {
                                Text("You're answering your own question")
                                    .font(LinenTheme.body(11))
                                    .fontWeight(.medium)
                                    .foregroundColor(LinenTheme.secondary)
                            }
                        }

                        if showsVoiceControls {
                            Button {
                                triggerHaptic(.selection)
                                showCustomQuestionSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(LinenTheme.body(12, weight: .medium))
                                    Text("Try a different question")
                                        .font(LinenTheme.body(13, weight: .medium))
                                }
                                .foregroundColor(LinenTheme.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(LinenTheme.surface)
                                .cornerRadius(20)
                            }
                        }

                        // Main Recording Button
                        if showsVoiceControls && !isRecording && !isPaused && audioURL == nil {
                            Button(action: startRecording) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(terracotta)
                                            .frame(width: 72, height: 72)
                                            .shadow(color: LinenTheme.accent.opacity(0.16), radius: 8, x: 0, y: 4)
                                        
                                        Image(systemName: "mic.fill")
                                            .font(LinenTheme.body(28))
                                            .foregroundColor(LinenTheme.onAccent)
                                    }
                                    
                                    Text("Tap to Record")
                                        .font(LinenTheme.body(12))
                                        .foregroundColor(LinenTheme.ink)
                                }
                            }
                        }

                        // Real-time Waveform Visualization
                        if showsVoiceControls {
                            RealTimeWaveformView(
                                audioMonitor: audioMonitor,
                                isRecording: isRecording,
                                isPaused: isPaused
                            )
                            .frame(maxWidth: contentWidth * 0.8)
                        }
                        
                        // Real-time transcription display
                        if realTimeTranscription.isTranscribing && !realTimeTranscription.currentTranscript.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "text.bubble.fill")
                                        .foregroundColor(LinenTheme.ink)
                                    Text("Live Transcription:")
                                        .font(LinenTheme.body(12))
                                        .foregroundColor(LinenTheme.secondary)
                                    Spacer()
                                }
                                Text(realTimeTranscription.currentTranscript)
                                    .font(LinenTheme.body(16))
                                    .foregroundColor(LinenTheme.ink)
                                    .padding(12)
                                    .background(LinenTheme.card)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(LinenTheme.line, lineWidth: 1)
                                    )
                            }
                            .frame(maxWidth: contentWidth * 0.8)
                        }

                        // Recording Timer Display
                        if isRecording || isPaused {
                            VStack(spacing: 4) {
                                Text(formatTime(recordingTime))
                                    .font(LinenTheme.heading(44)).monospacedDigit()
                                    .foregroundColor(LinenTheme.ink)
                                
                                Text(isPaused ? "Recording paused" : "Recording in progress")
                                    .font(LinenTheme.body(12))
                                    .foregroundColor(isPaused ? LinenTheme.secondary : terracotta)
                            }
                        }

                        // Recording Controls (only show when recording or paused or has audio)
                        if isRecording || isPaused || audioURL != nil {
                            ViewThatFits(in: .horizontal) {
                                recordingControls(spacing: 40)
                                recordingControls(spacing: 14)
                            }
                        }
                    }
                    .frame(maxWidth: contentWidth - 48)
                    .multilineTextAlignment(.center)

                    // Text entry
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $typedText)
                            .font(LinenTheme.body(16))
                            .foregroundColor(LinenTheme.ink)
                            .frame(minHeight: 180, maxHeight: 260)
                            .padding(.top, 8)
                            .padding(.leading, 32)
                            .scrollContentBackground(.hidden)
                            .background(softCream)
                            .focused($isTextFocused)
                            .accessibilityIdentifier("recordingTextEditor")
                            .onTapGesture {
                                triggerHaptic(.selection)
                            }
                        if typedText.isEmpty {
                            Text("Type your answer...")
                                .font(LinenTheme.body(16))
                                .foregroundColor(LinenTheme.secondary)
                                .padding(.top, 16)
                                .padding(.leading, 37)
                                .allowsHitTesting(false)
                        }
                        Image(systemName: "pencil")
                            .foregroundColor(LinenTheme.secondary)
                            .padding(.top, 14)
                            .padding(.leading, 10)
                    }
                    .background(softCream)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, 24)
                    
                    // Typed memories use the same full-width save action as recorded memories.
                    if !isRecording && !isPaused && audioURL == nil {
                        HStack {
                            Button(action: {
                                triggerHaptic(.impact(.heavy))
                                saveMemory()
                            }) {
                                Text("Save Memory")
                                    .font(LinenTheme.body(14, weight: .semibold))
                                    .foregroundColor(LinenTheme.onAccent)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(terracotta)
                                    .clipShape(RoundedRectangle(cornerRadius: 22))
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .transition(.opacity)
                    }

                        Spacer(minLength: 24)
                    }
                    .frame(width: contentWidth)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height)
                    .tutorialAnchor(.recordingSaveMemory)
                    .background(
                        GeometryReader { inner in
                            Color.clear
                                .onAppear { tutorialCoordinator.reportAnchor(.recordingSaveMemory, rect: inner.frame(in: .global)) }
                                .onChange(of: inner.frame(in: .global)) { _, f in tutorialCoordinator.reportAnchor(.recordingSaveMemory, rect: f) }
                        }
                    )
                }
                .frame(width: geo.size.width)
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .animation(.easeInOut(duration: 0.2), value: isTextFocused)

                // Back button
                VStack {
                    HStack {
                        Button(action: {
                            triggerHaptic(.impact(.light))
                            if hasUnsavedData() {
                                showExitConfirm = true
                            } else {
                                dismiss()
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(LinenTheme.body(18, weight: .medium))
                                .foregroundColor(LinenTheme.ink)
                                .padding(12)
                                .background(LinenTheme.surface)
                                .clipShape(Circle())
                        }
                        .accessibilityIdentifier("recordingBackButton")
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, RecordingLayoutPolicy.backButtonTopPadding(
                    safeAreaTop: geo.safeAreaInsets.top
                ))

                // Save toast — full-screen frame + HStack so the pill stays horizontally centered
                if showSaveToast {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer(minLength: 0)
                            Text("Memory Saved!")
                                .font(LinenTheme.body(15, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(LinenTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundColor(LinenTheme.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 60)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                // Hard-cap warning overlay (shared with RecordMemoryView) —
                // fires ~30s before the 60-minute recording limit.
                if showTimeoutWarning {
                    TimeoutWarningOverlay(
                        countdown: finalCountdown,
                        message: "Recording will save soon to protect your memory"
                    )
                }

                if showExitConfirm {
                    RecordingExitConfirmationOverlay(
                        discard: {
                            clearRecording()
                            dismiss()
                        },
                        keepEditing: { showExitConfirm = false }
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .allowsHitTesting(!isSaving)
            .alert(CloudTranscriptionDisclosure.title, isPresented: $showCloudTranscriptionDisclosure) {
                Button("Not Now", role: .cancel) { }
                Button("Continue") {
                    CloudTranscriptionDisclosure.accept()
                    startRecording()
                }
            } message: {
                Text(CloudTranscriptionDisclosure.message)
            }
            .alert(
                "Recording Unavailable",
                isPresented: Binding(
                    get: { recordingStartErrorMessage != nil },
                    set: { if !$0 { recordingStartErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { recordingStartErrorMessage = nil }
            } message: {
                Text(recordingStartErrorMessage ?? "Please check your connection and try again.")
            }
            .alert(
                "Memory Not Saved",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "Please try again.")
            }
            .sheet(isPresented: $showCustomQuestionSheet) {
                QuestionGeneratorSheet(
                    chapterTitle: chapterTitle,
                    memoirMode: memoirMode ?? MemoirModeClassifier.mode(forCurrentChapterTitle: chapterTitle) ?? currentMemoirMode()
                ) { newQuestion in
                    activePromptText = newQuestion
                    isUsingCustomQuestion = newQuestion.caseInsensitiveCompare(prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .analyticsScreen("memory_recording")
            .onAppear {
                activePromptText = prompt.text
                isUsingCustomQuestion = false
                setupAudioSession()
                tutorialCoordinator.setVisibleScreen(.recording)
                tutorialCoordinator.onRecordingViewAppeared(profileID: profileVM.selectedProfile.id)
                configureInterruptionObserver()
            }
            .onDisappear {
                tutorialCoordinator.clearAnchor(.recordingSaveMemory)
                if tutorialCoordinator.visibleScreen == .recording {
                    tutorialCoordinator.setVisibleScreen(.unknown)
                }
                onRecordingDismiss?()
                cleanup()
                if !isSaving, let audioURL, audioURL.isFileURL {
                    try? FileManager.default.removeItem(at: audioURL)
                    self.audioURL = nil
                }
            }
            // Permission alerts
            .fullScreenCover(isPresented: $permissionManager.showMicrophonePermissionAlert) {
                MicrophonePermissionAlert(
                    isPresented: $permissionManager.showMicrophonePermissionAlert,
                    onSettingsTap: permissionManager.openSettings
                )
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Control Button Helper
    @ViewBuilder
    private func recordingControls(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            controlButton(icon: "arrow.counterclockwise", label: "Clear") {
                triggerHaptic(.impact(.medium))
                clearRecording()
            }

            if isRecording || isPaused {
                controlButton(
                    icon: isPaused ? "play.fill" : "pause.fill",
                    label: isPaused ? "Resume" : "Pause"
                ) {
                    triggerHaptic(.impact(.light))
                    isPaused ? resumeRecording() : pauseRecording()
                }
            }

            controlButton(icon: "checkmark.circle.fill", label: "Save") {
                triggerHaptic(.impact(.heavy))
                stopRecording()
                saveMemory()
            }
        }
    }

    func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(LinenTheme.body(20, weight: .bold))
                    .foregroundColor(LinenTheme.onAccent)
                    .padding(20)
                    .background(terracotta)
                    .clipShape(Circle())
                    .scaleEffect(1.0)
                    .animation(.easeInOut(duration: 0.1), value: isRecording)
            }
            Text(label)
                .foregroundColor(LinenTheme.ink)
                .font(LinenTheme.body(12))
        }
    }

    // MARK: - Haptic Feedback
    enum HapticType {
        case impact(UIImpactFeedbackGenerator.FeedbackStyle)
        case selection
    }
    
    func triggerHaptic(_ type: HapticType) {
        switch type {
        case .impact(let style):
            Haptics.impact(style)
        case .selection:
            Haptics.selection()
        }
    }

    // MARK: - Time Formatting
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Recording Timer
    func startRecordingTimer(resetElapsedTime: Bool = true) {
        if resetElapsedTime {
            recordingTime = 0
        }
        stopRecordingTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard let recorder = audioRecorder else { return }
            recordingTime = recorder.currentTime

            // Check for timeout warnings (mirrors RecordMemoryView's safety net).
            if recordingTime >= countdownStart && recordingTime < maxRecordingDuration {
                let remaining = Int(ceil(maxRecordingDuration - recordingTime))
                finalCountdown = remaining
            } else if recordingTime >= warningThreshold && recordingTime < countdownStart {
                showTimeoutWarning = true
            } else if recordingTime >= maxRecordingDuration || !recorder.isRecording {
                // Auto-stop and save to protect the memory once the hard cap is hit.
                stopRecording()
                saveMemory()
            }
        }
    }

    func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    // MARK: - Interruption / Backgrounding

    /// Wires the shared observer so a phone call, Siri, unplugged headphones, or
    /// the app moving to the background pauses recording the same way tapping
    /// Pause does, instead of silently letting the timer/UI drift out of sync
    /// with reality.
    private func configureInterruptionObserver() {
        interruptionObserver.onInterruptionBegan = {
            guard isRecording, !isPaused else { return }
            pauseRecording()
            interruptionBannerMessage = "Recording paused. Audio was interrupted"
        }
        interruptionObserver.onInterruptionEnded = { _ in
            // Do not auto-resume: keep the existing paused UI and Resume button
            // so the user makes the call themselves.
            guard isPaused else { return }
            interruptionBannerMessage = "Recording paused. Tap Resume to continue"
        }
        interruptionObserver.onRouteChangeDeviceUnavailable = {
            guard isRecording, !isPaused else { return }
            pauseRecording()
            interruptionBannerMessage = "Recording paused. Audio device disconnected"
        }
        interruptionObserver.onAppBackgrounded = {
            guard isRecording, !isPaused else { return }
            pauseRecording()
            interruptionBannerMessage = "Recording paused while MemoirAI was in the background"
        }
    }

    // MARK: - Recorder Lifecycle
    func setupAudioSession() {
        // Configure audio session for optimal speech recognition
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setMode(.measurement)
            try session.setActive(true)
            if session.isInputGainSettable {
                try session.setInputGain(1.0)
            }
        } catch {
            print("⚠️ Enhanced audio session setup error: \(error)")
            recordingStartErrorMessage = RecordingStartErrorPolicy.message(
                detail: "Check that your microphone is available, then try again."
            )
        }
    }

    func startRecording() {
        isTextFocused = false
        if let failureMessage = MemoryUserScope.recordingStartFailureMessage(
            firebaseUserID: MemoryUserScope.currentFirebaseUserId
        ) {
            recordingStartErrorMessage = failureMessage
            ProductAnalytics.shared.track("Recording Start Failed", ["failure_stage": "auth", "diagnostic_reason": "auth_unavailable"])
            return
        }
        guard CloudTranscriptionDisclosure.isAccepted() else {
            showCloudTranscriptionDisclosure = true
            return
        }
        // Check microphone permission before starting
        guard permissionManager.isMicrophoneAuthorized else {
            permissionManager.requestMicrophonePermission {
                startRecording()
            }
            return
        }
        
        triggerHaptic(.impact(.medium))
        
        // Generate a unique M4A filename for finalized AAC audio.
        let filename = UUID().uuidString + ".m4a"
        let fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        
        // Use optimal recording format for speech recognition
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
                recordingStartErrorMessage = RecordingStartErrorPolicy.message()
                ProductAnalytics.shared.track("Recording Start Failed", ["failure_stage": "recording", "diagnostic_reason": "recorder_start_rejected"])
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            audioRecorder = recorder
            
            audioURL = fileURL
            isRecording = true
            isPaused = false
            
            // Track recording started
            ProductAnalytics.shared.track("Started Recording", [
                "has_custom_prompt": !activePromptText.isEmpty
            ])
            
            // Start audio level monitoring
            if let recorder = audioRecorder {
                audioMonitor.startMonitoring(recorder: recorder)
            }
            
            // Start real-time transcription for better accuracy
            realTimeTranscription.startTranscription()
            
            startRecordingTimer()
            debugBanner = "Recording started with AAC format"
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            ProductAnalytics.shared.track("Recording Start Failed", ["failure_stage": "recording", "diagnostic_reason": "recorder_creation_failed"])
            print("⚠️ Error starting recorder: \(error.localizedDescription)")
            recordingStartErrorMessage = RecordingStartErrorPolicy.message(
                detail: "Check that another app is not using the microphone, then try again."
            )
        }
    }

    func pauseRecording() {
        Haptics.selection()
        audioRecorder?.pause()
        isPaused = true
        recordingTimer?.invalidate()
        
        // Pause real-time transcription
        realTimeTranscription.pauseTranscription()
    }

    func resumeRecording() {
        Haptics.selection()
        guard let recorder = audioRecorder else { return }
        let remaining = RecordingDurationPolicy.remainingDuration(after: recorder.currentTime)
        guard remaining > 0, recorder.record(forDuration: remaining) else {
            stopRecording()
            saveMemory()
            return
        }
        isPaused = false
        interruptionBannerMessage = nil

        // Resume real-time transcription
        realTimeTranscription.resumeTranscription()

        startRecordingTimer(resetElapsedTime: false)
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        interruptionBannerMessage = nil
        stopRecordingTimer()

        // Hide the hard-cap warning if it was showing.
        showTimeoutWarning = false
        finalCountdown = nil

        audioMonitor.stopMonitoring()

        // Live text is only a recording aid. The saved memoir is transcribed
        // from the complete audio file after it has uploaded.
        realTimeTranscription.stopTranscription()
        _ = realTimeTranscription.getFinalTranscript()
    }

    func clearRecording() {
        stopRecording()
        if let audioURL, audioURL.isFileURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        audioURL = nil
        recordingTime = 0
        typedText = ""
        photoItems.removeAll()
    }
    // MARK: – Save & Transcribe (background + disk photos)
    // MARK: – Save & Transcribe (background + external-storage blobs)
    func saveMemory() {
        // 0️⃣ Don't do anything if there's nothing to save
        guard hasUnsavedData(), !isSaving else { return }
        guard let firebaseUserId = MemoryUserScope.currentFirebaseUserId else {
            ProductAnalytics.shared.track("Memory Save Failed", ["failure_stage": "auth"])
            saveErrorMessage = "MemoirAI is still connecting to your private account. Your recording is unchanged; check your connection and try saving again."
            return
        }
        isSaving = true       // you can overlay a ProgressView if desired

        // Capture current values before we mutate UI state
        let recordingDurationToSave = recordingTime
        let promptToSave      = activePromptText.isEmpty ? prompt.text : activePromptText
        let textToSave        = MemoryDraftPolicy.normalizedText(typedText)
        let audioURLToSave    = audioURL
        let profile = profileVM.selectedProfile
        let memoirModeToSave = memoirMode ?? MemoirModeClassifier.mode(forCurrentChapterTitle: chapterTitle)

        // 1️⃣ Spin up a private background context so we never block the UI
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.perform {
            let audioFileSize = audioURLToSave.flatMap {
                (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? NSNumber)?.int64Value
            }
            guard audioURLToSave == nil || (audioFileSize ?? 0) > 0 else {
                print("❌ Could not read the completed recording; memory was not saved")
                DispatchQueue.main.async {
                    isSaving = false
                    ProductAnalytics.shared.track("Memory Save Failed", ["failure_stage": "audio_file"])
                    saveErrorMessage = "The completed recording could not be read. Your recording was not deleted; try saving again."
                }
                return
            }

            // 2️⃣ Create the MemoryEntry in the background
            let entry = MemoryEntry(context: bgContext)
            entry.id           = UUID()
            entry.prompt       = promptToSave
            entry.text         = textToSave
            entry.audioData    = nil
            entry.audioFileURL = audioURLToSave?.absoluteString
            entry.transcriptionEditedText = audioURLToSave == nil ? nil : textToSave
            entry.transcriptionStatus = audioURLToSave == nil ? nil : "queued"
            entry.transcriptionLanguage = "en"
            entry.createdAt    = Date()
            entry.chapter      = chapterTitle
            entry.memoirModeRaw = memoirModeToSave?.rawValue
            entry.profileID    = profile.id
            entry.firebaseUserId = firebaseUserId

            // 4️⃣ Save the background context
            do {
                try bgContext.save()
                let hasAudio = entry.hasAudio
                let hasText = !(entry.text?.isEmpty ?? true)
                let hasPhotos = !(entry.photos?.allObjects.isEmpty ?? true)
                Task { @MainActor in
                    ProductAnalytics.shared.track("Saved Memory", [
                        "has_audio": hasAudio, "has_text": hasText,
                        "has_photos": hasPhotos, "save_scope": "local",
                        "recording_duration": recordingDurationToSave
                    ])
                }
                
                // 4.5️⃣ Sync to Firebase with profile info (fire and forget)
                FirestoreSyncService.shared.queueMemorySyncWithProfile(entry, profile: profile)
            } catch {
                print("❌ BG save failed:", error)
                DispatchQueue.main.async {
                    isSaving = false
                    ProductAnalytics.shared.track("Memory Save Failed", ["failure_stage": "local_save"])
                    saveErrorMessage = "This memory could not be saved on your device. Your draft is unchanged; free some storage and try again."
                }
                return
            }

            // 5️⃣ Back on the main thread: show toast, then dismiss (or advance the per-child queue)
            DispatchQueue.main.async {
                showSaveToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showSaveToast = false
                    if let onSaveComplete = onSaveComplete {
                        onSaveComplete()
                    } else {
                        dismiss()
                    }
                    // Notify after dismiss so listeners don't trigger view rebuilds
                    // while the fullScreenCover is still animating out
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NotificationCenter.default.post(name: .memorySaved, object: nil)
                    }
                }
            }
        }
    }
    
    // Helper – writes image data to disk, returns URL
    func writeImageDataToDisk(data: Data) -> URL? {
        let fileName = UUID().uuidString + ".jpg"
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("❌ Could not write image: \(error)")
            return nil
        }
    }


    // MARK: - Unsaved Data Check & Cleanup
    func hasUnsavedData() -> Bool {
        MemoryDraftPolicy.hasContent(text: typedText, audioURL: audioURL)
    }

    func cleanup() {
        stopRecording()
        interruptionObserver.onInterruptionBegan = nil
        interruptionObserver.onInterruptionEnded = nil
        interruptionObserver.onRouteChangeDeviceUnavailable = nil
        interruptionObserver.onAppBackgrounded = nil
    }
}
enum MemoryDraftPolicy {
    static func normalizedText(_ text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func hasContent(text: String, audioURL: URL?) -> Bool {
        normalizedText(text) != nil || audioURL != nil
    }
}
