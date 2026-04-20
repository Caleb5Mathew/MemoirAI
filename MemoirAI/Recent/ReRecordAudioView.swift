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

    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioURL: URL?
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var isSaving = false

    private let terracotta = Color(red: 210/255, green: 112/255, blue: 45/255)
    private let softCream = Color(red: 253/255, green: 234/255, blue: 198/255)
    private let headerColor = Color(red: 0.12, green: 0.22, blue: 0.18)
    private let backgroundColor = Color(red: 0.98, green: 0.96, blue: 0.89)

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 28) {
                        if let prompt = promptText, !prompt.isEmpty {
                            Text(prompt)
                                .font(.system(size: 20, weight: .semibold, design: .serif))
                                .foregroundColor(headerColor)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        Text("Record a new voice answer for this memory.")
                            .font(.system(size: 15, weight: .regular, design: .serif))
                            .foregroundColor(headerColor.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if !isRecording && !isPaused && audioURL == nil {
                            Button(action: startRecording) {
                                VStack(spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(terracotta)
                                            .frame(width: 80, height: 80)
                                            .shadow(color: .orange.opacity(0.25), radius: 8, x: 0, y: 4)
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.white)
                                    }
                                    Text("Tap to record")
                                        .font(.subheadline.weight(.semibold))
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
                                .font(.body)
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
                                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                                    .foregroundColor(headerColor)
                                Text(isPaused ? "Paused" : "Recording…")
                                    .font(.caption)
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
                                .tint(terracotta)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("New recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        cleanupSession()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            checkMicrophonePermission()
        }
        .onDisappear {
            cleanupSession()
        }
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(18)
                    .background(terracotta)
                    .clipShape(Circle())
            }
            Text(label)
                .foregroundColor(headerColor.opacity(0.8))
                .font(.caption)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func checkMicrophonePermission() {
        if !permissionManager.isMicrophoneAuthorized {
            permissionManager.requestMicrophonePermission()
        }
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setMode(.measurement)
            try session.setActive(true)
        } catch {
            print("ReRecord audio session error: \(error)")
        }
    }

    private func startRecordingTimer() {
        recordingTime = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingTime += 1
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func startRecording() {
        guard permissionManager.isMicrophoneAuthorized else {
            permissionManager.requestMicrophonePermission()
            return
        }
        setupAudioSession()
        let filename = UUID().uuidString + ".caf"
        let fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
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
            isPaused = false
            if let recorder = audioRecorder {
                audioMonitor.startMonitoring(recorder: recorder)
            }
            realTimeTranscription.startTranscription()
            startRecordingTimer()
        } catch {
            print("ReRecord start error: \(error)")
        }
    }

    private func pauseRecording() {
        audioRecorder?.pause()
        isPaused = true
        stopRecordingTimer()
        realTimeTranscription.pauseTranscription()
    }

    private func resumeRecording() {
        audioRecorder?.record()
        isPaused = false
        realTimeTranscription.resumeTranscription()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingTime += 1
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
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

    private func saveToExistingMemory() {
        guard let url = audioURL else { return }
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

            let data = try? Data(contentsOf: capturedURL)
            entry.audioData = data
            entry.audioFileURL = capturedURL.absoluteString

            do {
                try bgContext.save()
                FirestoreSyncService.shared.queueMemorySyncWithProfile(entry, profile: profile)
            } catch {
                print("ReRecord save failed: \(error)")
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .memorySaved, object: nil)
            }

            if let urlString = entry.audioFileURL, let fileURL = URL(string: urlString) {
                SpeechTranscriber.shared.transcribe(url: fileURL) { result in
                    switch result {
                    case .success(let transcript):
                        bgContext.perform {
                            entry.text = transcript
                            try? bgContext.save()
                            if let memoryId = entry.id {
                                Task {
                                    await FirestoreSyncService.shared.updateMemoryTranscription(
                                        memoryId: memoryId,
                                        transcription: transcript
                                    )
                                }
                            }
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: .memorySaved, object: nil)
                            }
                        }
                    case .failure(let err):
                        print("ReRecord transcription failed: \(err.localizedDescription)")
                    }
                }
            }

            Task { @MainActor in
                isSaving = false
                dismiss()
            }
        }
    }
}
