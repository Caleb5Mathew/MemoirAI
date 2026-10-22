// ReRecordAudioView.swift
// MemoirAI — lightweight in-place recording for an existing MemoryEntry.

import SwiftUI
import AVFoundation
import CoreData
import UIKit

struct ReRecordAudioView: View {
    let memoryObjectID: NSManagedObjectID
    let promptText: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileVM: ProfileViewModel

    @StateObject private var audioMonitor = AudioLevelMonitor()
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var realTimeTranscription = RealTimeTranscriptionManager.shared
    @StateObject private var interruptionObserver = AudioSessionInterruptionObserver()

    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioURL: URL?
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var isSaving = false
    @State private var didSaveRecording = false
    @State private var showCloudTranscriptionDisclosure = false
    @State private var recordingStartErrorMessage: String?

    // Interruption / backgrounding — set when the system (not the user) paused
    // an in-progress recording, so the UI can explain why.
    @State private var interruptionBannerMessage: String? = nil

    private let terracotta = LinenTheme.accent
    private let softCream = LinenTheme.surface
    private let headerColor = LinenTheme.ink
    private let backgroundColor = LinenTheme.paper

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let maxRecordingDuration = RecordingDurationPolicy.maximumRecordingDuration

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 28) {
                        if let prompt = promptText, !prompt.isEmpty {
                            Text(prompt)
                                .font(LinenTheme.heading(20))
                                .foregroundColor(headerColor)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        Text("Record a new voice answer for this memory.")
                            .font(LinenTheme.body(15))
                            .foregroundColor(LinenTheme.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if let message = interruptionBannerMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
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
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if !isRecording && !isPaused && audioURL == nil {
                            Button(action: startRecording) {
                                VStack(spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(terracotta)
                                            .frame(width: 80, height: 80)
                                            .shadow(color: LinenTheme.accent.opacity(0.25), radius: 8, x: 0, y: 4)
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(LinenTheme.onAccent)
                                    }
                                    Text("Tap to record")
                                        .font(LinenTheme.body(15, weight: .semibold))
                                        .foregroundColor(headerColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        RealTimeWaveformView(
                            audioMonitor: audioMonitor,
                            isRecording: isRecording,
                            isPaused: isPaused
                        )
                        .frame(maxWidth: min(geo.size.width * 0.85, 400))

                        if realTimeTranscription.isTranscribing && !realTimeTranscription.currentTranscript.isEmpty {
                            Text(realTimeTranscription.currentTranscript)
                                .font(LinenTheme.body(16))
                                .foregroundColor(headerColor)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(softCream)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(.horizontal, 20)
                        }

                        if isRecording || isPaused {
                            VStack(spacing: 6) {
                                Text(formatTime(recordingTime))
                                    .font(LinenTheme.body(22, weight: .medium).monospacedDigit())
                                    .foregroundColor(headerColor)
                                Text(isPaused ? "Paused" : "Recording…")
                                    .font(LinenTheme.body(12, weight: .medium))
                                    .foregroundColor(terracotta)
                            }
                        }

                        if isRecording || isPaused || audioURL != nil {
                            HStack(spacing: 28) {
                                controlButton(icon: "arrow.counterclockwise", label: "Clear") {
                                    impactFeedback.impactOccurred()
                                    clearRecording()
                                }
                                if isRecording || isPaused {
                                    controlButton(
                                        icon: isPaused ? "play.fill" : "pause.fill",
                                        label: isPaused ? "Resume" : "Pause"
                                    ) {
                                        impactFeedback.impactOccurred()
                                        if isPaused { resumeRecording() } else { pauseRecording() }
                                    }
                                }
                                controlButton(icon: "checkmark.circle.fill", label: "Save") {
                                    impactFeedback.impactOccurred()
                                    stopRecording()
                                    saveToExistingMemory()
                                }
                                .disabled(audioURL == nil || isSaving)
                                .opacity(audioURL == nil ? 0.45 : 1)
                            }
                            .padding(.bottom, 8)
                        }

                        if isSaving {
                            ProgressView("Saving…")
                                .font(LinenTheme.body(14, weight: .medium))
                                .tint(terracotta)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
            .background(backgroundColor.ignoresSafeArea())
            .tint(LinenTheme.accent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New recording")
                        .font(LinenTheme.heading(20))
                        .foregroundStyle(LinenTheme.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        clearRecording()
                        dismiss()
                    }
                    .font(LinenTheme.body(16, weight: .medium))
                    .foregroundStyle(LinenTheme.ink)
                    .disabled(isSaving)
                }
            }
        }
        .analyticsScreen("memory_rerecord")
        .onAppear {
            configureInterruptionObserver()
        }
        .onDisappear {
            if didSaveRecording {
                cleanupSession()
            } else {
                clearRecording()
            }
        }
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
            "Recording unavailable",
            isPresented: Binding(
                get: { recordingStartErrorMessage != nil },
                set: { if !$0 { recordingStartErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { recordingStartErrorMessage = nil }
        } message: {
            Text(recordingStartErrorMessage ?? RecordingStartErrorPolicy.message())
        }
        .fullScreenCover(isPresented: $permissionManager.showMicrophonePermissionAlert) {
            MicrophonePermissionAlert(
                isPresented: $permissionManager.showMicrophonePermissionAlert,
                onSettingsTap: permissionManager.openSettings
            )
        }
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(LinenTheme.onAccent)
                    .padding(18)
                    .background(terracotta)
                    .clipShape(Circle())
            }
            Text(label)
                .foregroundColor(LinenTheme.secondary)
                .font(LinenTheme.body(12, weight: .medium))
        }
        .disabled(isSaving)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func setupAudioSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setMode(.measurement)
            try session.setActive(true)
            return true
        } catch {
            print("ReRecord audio session error: \(error)")
            recordingStartErrorMessage = RecordingStartErrorPolicy.message(
                detail: "Check that your microphone is available, then try again."
            )
            return false
        }
    }

    private func startRecordingTimer(resetElapsedTime: Bool = true) {
        if resetElapsedTime {
            recordingTime = 0
        }
        stopRecordingTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard let recorder = audioRecorder else { return }
            recordingTime = recorder.currentTime
            if recordingTime >= maxRecordingDuration || !recorder.isRecording {
                stopRecording()
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func startRecording() {
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
        guard setupAudioSession() else { return }
        let filename = UUID().uuidString + ".m4a"
        let fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
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
                print("ReRecord recorder refused to start")
                recordingStartErrorMessage = RecordingStartErrorPolicy.message()
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            audioRecorder = recorder
            audioURL = fileURL
            isRecording = true
            isPaused = false
            if let recorder = audioRecorder {
                audioMonitor.startMonitoring(recorder: recorder)
            }
            realTimeTranscription.startTranscription()
            startRecordingTimer()
        } catch {
            print("ReRecord start error: \(error)")
            recordingStartErrorMessage = RecordingStartErrorPolicy.message(
                detail: "Check that another app is not using the microphone, then try again."
            )
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func pauseRecording() {
        audioRecorder?.pause()
        isPaused = true
        stopRecordingTimer()
        realTimeTranscription.pauseTranscription()
    }

    private func resumeRecording() {
        guard let recorder = audioRecorder else { return }
        let remaining = RecordingDurationPolicy.remainingDuration(after: recorder.currentTime)
        guard remaining > 0, recorder.record(forDuration: remaining) else {
            stopRecording()
            return
        }
        isPaused = false
        interruptionBannerMessage = nil
        realTimeTranscription.resumeTranscription()
        startRecordingTimer(resetElapsedTime: false)
    }

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        interruptionBannerMessage = nil
        stopRecordingTimer()
        audioMonitor.stopMonitoring()
        realTimeTranscription.stopTranscription()
    }

    private func clearRecording() {
        stopRecording()
        if let url = audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioURL = nil
        recordingTime = 0
    }

    private func cleanupSession() {
        stopRecording()
        realTimeTranscription.stopTranscription()
        audioMonitor.stopMonitoring()
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

    private func saveToExistingMemory() {
        guard !isSaving, let url = audioURL else { return }
        isSaving = true
        let capturedURL = url
        let objectID = memoryObjectID
        let profile = profileVM.selectedProfile

        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.perform {
            guard let entry = try? bgContext.existingObject(with: objectID) as? MemoryEntry else {
                Task { @MainActor in
                    isSaving = false
                }
                return
            }

            let audioFileSize = (try? FileManager.default.attributesOfItem(
                atPath: capturedURL.path
            )[.size] as? NSNumber)?.int64Value
            guard (audioFileSize ?? 0) > 0 else {
                Task { @MainActor in
                    isSaving = false
                }
                return
            }
            let previousAudioURL = entry.audioFileURL.flatMap(URL.init(string:))
            entry.audioData = nil
            entry.audioFileURL = capturedURL.absoluteString
            entry.text = nil
            entry.transcriptionRawText = nil
            entry.transcriptionEditedText = nil
            entry.transcriptionStatus = "queued"
            entry.transcriptionLanguage = "en"

            do {
                try bgContext.save()
                if let previousAudioURL,
                   previousAudioURL.isFileURL,
                   previousAudioURL != capturedURL,
                   FileManager.default.fileExists(atPath: previousAudioURL.path) {
                    try? FileManager.default.removeItem(at: previousAudioURL)
                }
                FirestoreSyncService.shared.queueMemorySyncWithProfile(entry, profile: profile)
            } catch {
                print("ReRecord save failed: \(error)")
                Task { @MainActor in
                    isSaving = false
                }
                return
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .memorySaved, object: nil)
            }

            Task { @MainActor in
                isSaving = false
                didSaveRecording = true
                dismiss()
            }
        }
    }
}
