import SwiftUI
import AVFoundation
import CoreData
import PhotosUI
import Speech
import Mixpanel
import UIKit

struct RecordingView: View {
    @State private var debugBanner: String?
    let prompt: MemoryPrompt
    let chapterTitle: String
    var namespace: Namespace.ID
    /// Called first on `onDisappear` so the chapter map can clear selection before the full-screen dismiss animation ends (avoids hidden prompt node / stale border).
    var onRecordingDismiss: (() -> Void)? = nil
    /// When set, runs after a successful save instead of the default `dismiss()`. Used by the per-child queue wrapper to advance between child variants without tearing the cover down.
    var onSaveComplete: (() -> Void)? = nil
    /// Optional header label for sub-prompt flows, e.g., "1 of 3".
    var progressLabel: String? = nil
    @State private var isSaving = false
    @State private var showCloudTranscriptionDisclosure = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @StateObject private var audioMonitor = AudioLevelMonitor()
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var realTimeTranscription = RealTimeTranscriptionManager.shared
    @StateObject private var interruptionObserver = AudioSessionInterruptionObserver()

    @State private var typedText: String = ""
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
    @State private var selectedImagesData: [Data] = []

    // Colors
    let terracotta = Color(red: 210/255, green: 112/255, blue: 45/255)
    let softCream = Color(red: 253/255, green: 234/255, blue: 198/255)
    let overlayBlack = Color.black.opacity(0.4)
    let accent = Color(red: 0.10, green: 0.22, blue: 0.14)

    // Grid layout for up to 8 images (4 columns)
    private var columns: [GridItem] {
        Array(repeating: .init(.flexible(), spacing: 8), count: 4)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background: chapter art when available; Relationships chapters use same gradient as journey map
                Group {
                    let chapterAsset = chapterImageAssetName(for: chapterTitle)
                    if UIImage(named: chapterAsset) != nil {
                        Image(chapterAsset)
                            .resizable()
                            .scaledToFill()
                    } else if let relationshipGradient = relationshipChapterGradient(forChapterTitle: chapterTitle) {
                        relationshipGradient
                    } else {
                        Color(red: 0.22, green: 0.22, blue: 0.24)
                    }
                }
                .ignoresSafeArea()
                overlayBlack.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer(minLength: geo.size.height * 0.08)

                    // Prompt & audio controls
                    VStack(spacing: 12) {
                        // Interruption / backgrounding banner — only shown when the
                        // system (not the user) paused an in-progress recording.
                        if let message = interruptionBannerMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(message)
                                    .font(.system(size: 13, weight: .semibold))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .foregroundColor(.white)
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
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.35))
                                    .clipShape(Capsule())
                            }
                            Text(activePromptText.isEmpty ? prompt.text : activePromptText)
                                .matchedGeometryEffect(id: prompt.id, in: namespace)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(nil)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(terracotta)
                                .cornerRadius(16)

                            if isUsingCustomQuestion {
                                Text("You're answering your own question")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }

                        Button {
                            triggerHaptic(.selection)
                            showCustomQuestionSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Try a different question")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(20)
                        }

                        // Main Recording Button
                        if !isRecording && !isPaused && audioURL == nil {
                            Button(action: startRecording) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(terracotta)
                                            .frame(width: 80, height: 80)
                                            .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                                        
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text("Tap to Record")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                        }

                        // Real-time Waveform Visualization
                        RealTimeWaveformView(
                            audioMonitor: audioMonitor,
                            isRecording: isRecording,
                            isPaused: isPaused
                        )
                        .frame(maxWidth: geo.size.width * 0.8)
                        
                        // Real-time transcription display
                        if realTimeTranscription.isTranscribing && !realTimeTranscription.currentTranscript.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "text.bubble.fill")
                                        .foregroundColor(.white)
                                    Text("Live Transcription:")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                    Spacer()
                                }
                                Text(realTimeTranscription.currentTranscript)
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .frame(maxWidth: geo.size.width * 0.8)
                        }

                        // Recording Timer Display
                        if isRecording || isPaused {
                            VStack(spacing: 4) {
                                Text(formatTime(recordingTime))
                                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                Text(isPaused ? "Recording paused" : "Recording in progress")
                                    .font(.caption)
                                    .foregroundColor(isPaused ? .white.opacity(0.7) : terracotta)
                            }
                        }

                        // Recording Controls (only show when recording or paused or has audio)
                        if isRecording || isPaused || audioURL != nil {
                            HStack(spacing: 40) {
                                controlButton(icon: "arrow.counterclockwise", label: "Clear") {
                                    triggerHaptic(.impact(.medium))
                                    clearRecording()
                                }
                                
                                if isRecording || isPaused {
                                    controlButton(icon: isPaused ? "play.fill" : "pause.fill",
                                                  label: isPaused ? "Resume" : "Pause") {
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
                    }
                    .frame(maxWidth: geo.size.width * 0.9)
                    .multilineTextAlignment(.center)

                    // Text entry
                    ZStack(alignment: .topLeading) {
                        if typedText.isEmpty {
                            Text("Type your answer...")
                                .foregroundColor(.gray)
                                .padding(.top, 12)
                                .padding(.leading, 36)
                        }
                        TextEditor(text: $typedText)
                            .font(.system(size: 14))
                            .foregroundColor(.black)
                            .frame(minHeight: 60, maxHeight: 120)
                            .padding(.top, 8)
                            .padding(.leading, 32)
                            .scrollContentBackground(.hidden)
                            .background(softCream)
                            .onTapGesture {
                                triggerHaptic(.selection)
                            }
                        Image(systemName: "pencil")
                            .foregroundColor(.gray)
                            .padding(.top, 14)
                            .padding(.leading, 10)
                    }
                    .background(softCream)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, geo.size.width * 0.05)
                    
                    // Save Memory button - right-aligned, only shows when recording controls are NOT visible
                    if !isRecording && !isPaused && audioURL == nil {
                        HStack {
                            Spacer()
                            Button(action: {
                                triggerHaptic(.impact(.heavy))
                                saveMemory()
                            }) {
                                Text("Save Memory")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 20)
                                    .background(terracotta)
                                    .cornerRadius(12)
                                    .shadow(color: terracotta.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                        }
                        .padding(.horizontal, geo.size.width * 0.05)
                        .padding(.top, 8)
                        .transition(.opacity)
                    }

                    Spacer()
                }
                .tutorialAnchor(.recordingSaveMemory)
                .background(
                    GeometryReader { inner in
                        Color.clear
                            .onAppear { tutorialCoordinator.reportAnchor(.recordingSaveMemory, rect: inner.frame(in: .global)) }
                            .onChange(of: inner.frame(in: .global)) { _, f in tutorialCoordinator.reportAnchor(.recordingSaveMemory, rect: f) }
                    }
                )
                .frame(maxWidth: geo.size.width)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)

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
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.25))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)

                // Save toast — full-screen frame + HStack so the pill stays horizontally centered
                if showSaveToast {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer(minLength: 0)
                            Text("Memory Saved!")
                                .font(.system(size: 15, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundColor(.white)
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
            }
            .allowsHitTesting(!isSaving)
            .confirmationDialog("Exit without saving?", isPresented: $showExitConfirm) {
                Button("Discard and Exit", role: .destructive) {
                    clearRecording()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Private Cloud Transcription", isPresented: $showCloudTranscriptionDisclosure) {
                Button("Not Now", role: .cancel) { }
                Button("Continue") {
                    CloudTranscriptionDisclosure.accept()
                    startRecording()
                }
            } message: {
                Text("Saved recordings are uploaded to your private MemoirAI account and sent to OpenAI to create a transcript. You can delete the recording and transcript at any time.")
            }
            .sheet(isPresented: $showCustomQuestionSheet) {
                QuestionGeneratorSheet(chapterTitle: chapterTitle) { newQuestion in
                    activePromptText = newQuestion
                    isUsingCustomQuestion = newQuestion.caseInsensitiveCompare(prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
            }
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
            }
            // Permission alerts
            .fullScreenCover(isPresented: $permissionManager.showMicrophonePermissionAlert) {
                MicrophonePermissionAlert(
                    isPresented: $permissionManager.showMicrophonePermissionAlert,
                    onSettingsTap: permissionManager.openSettings
                )
            }
        }
    }

    // MARK: - Control Button Helper
    func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(20)
                    .background(terracotta)
                    .clipShape(Circle())
                    .scaleEffect(1.0)
                    .animation(.easeInOut(duration: 0.1), value: isRecording)
            }
            Text(label)
                .foregroundColor(.white)
                .font(.caption)
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
        }
    }

    func startRecording() {
        guard CloudTranscriptionDisclosure.isAccepted() else {
            showCloudTranscriptionDisclosure = true
            return
        }
        // Check microphone permission before starting
        guard permissionManager.isMicrophoneAuthorized else {
            permissionManager.requestMicrophonePermission()
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
                debugBanner = "Recorder could not start"
                return
            }
            audioRecorder = recorder
            
            audioURL = fileURL
            isRecording = true
            isPaused = false
            
            // Track recording started
            Mixpanel.mainInstance().track(event: "Started Recording", properties: [
                "chapter_title": chapterTitle,
                "prompt_text": activePromptText.isEmpty ? prompt.text : activePromptText
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
            print("⚠️ Error starting recorder: \(error.localizedDescription)")
            debugBanner = "Recorder error: \(error.localizedDescription)"
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
        selectedImagesData.removeAll()
        photoItems.removeAll()
    }
    // MARK: – Save & Transcribe (background + disk photos)
    // MARK: – Save & Transcribe (background + external-storage blobs)
    func saveMemory() {
        // 0️⃣ Don't do anything if there's nothing to save
        guard hasUnsavedData(), !isSaving else { return }
        isSaving = true       // you can overlay a ProgressView if desired

        // Track memory saved
        let savedPrompt = activePromptText.isEmpty ? prompt.text : activePromptText
        Mixpanel.mainInstance().track(event: "Saved Memory", properties: [
            "chapter_title": chapterTitle,
            "prompt_text": savedPrompt,
            "has_audio": audioURL != nil,
            "has_text": !typedText.isEmpty,
            "has_photos": !selectedImagesData.isEmpty,
            "recording_duration": recordingTime
        ])

        // Capture current values before we mutate UI state
        let promptToSave      = activePromptText.isEmpty ? prompt.text : activePromptText
        let textToSave        = typedText
        let audioURLToSave    = audioURL
        let imagesToSave      = selectedImagesData
        let profile = profileVM.selectedProfile
        let firebaseUserId = MemoryUserScope.currentFirebaseUserId

        // 1️⃣ Spin up a private background context so we never block the UI
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.perform {
            let audioDataToSave = audioURLToSave.flatMap { try? Data(contentsOf: $0) }
            guard audioURLToSave == nil || audioDataToSave?.isEmpty == false else {
                print("❌ Could not read the completed recording; memory was not saved")
                DispatchQueue.main.async { isSaving = false }
                return
            }

            // 2️⃣ Create the MemoryEntry in the background
            let entry = MemoryEntry(context: bgContext)
            entry.id           = UUID()
            entry.prompt       = promptToSave
            entry.text         = textToSave.isEmpty ? nil : textToSave
            entry.audioData    = audioDataToSave
            entry.audioFileURL = audioURLToSave?.absoluteString
            entry.transcriptionEditedText = audioURLToSave == nil || textToSave.isEmpty ? nil : textToSave
            entry.transcriptionStatus = audioURLToSave == nil ? nil : "queued"
            entry.transcriptionLanguage = "en"
            entry.createdAt    = Date()
            entry.chapter      = chapterTitle
            entry.profileID    = profile.id
            entry.firebaseUserId = firebaseUserId
            if entry.firebaseUserId == nil {
                print("⚠️ Saving memory without firebaseUserId in RecordingView")
            }

            // 3️⃣ Photo saving disabled - uncomment below to re-enable
            /*
            // Persist each selected image—Core Data will externalize large blobs
            for data in imagesToSave {
                let photo = Photo(context: bgContext)
                photo.id           = UUID()
                photo.data         = data
                photo.memoryEntry  = entry
            }
            */

            // 4️⃣ Save the background context
            do {
                try bgContext.save()
                
                // 4.5️⃣ Sync to Firebase with profile info (fire and forget)
                FirestoreSyncService.shared.queueMemorySyncWithProfile(entry, profile: profile)
            } catch {
                print("❌ BG save failed:", error)
                DispatchQueue.main.async { isSaving = false }
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
    
    // MARK: - Permission Management
    
    private func checkMicrophonePermission() {
        if !permissionManager.isMicrophoneAuthorized {
            permissionManager.requestMicrophonePermission()
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
        !typedText.isEmpty || audioURL != nil || !selectedImagesData.isEmpty
    }

    func cleanup() {
        recordingTimer?.invalidate()
        audioMonitor.stopMonitoring()
    }
}
