import Foundation
import AVFoundation
import Speech

/// Manages real-time transcription during audio recording
final class RealTimeTranscriptionManager: ObservableObject {
    static let shared = RealTimeTranscriptionManager()
    
    @Published var currentTranscript: String = ""
    @Published var isTranscribing: Bool = false
    @Published var transcriptionError: String?
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    private init() {
        // Defensively tear down our own audio engine on system interruptions /
        // route changes even if a caller forgets to. Recording views still own
        // pausing their `AVAudioRecorder` and any resume UI via their own
        // `AudioSessionInterruptionObserver` — this is a safety net for the
        // engine this class manages internally, not a substitute for that.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        }
    }

    deinit {
        stopTranscription()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
    }

    // MARK: - Interruption / Route Change Handling

    private func handleInterruption(_ note: Notification) {
        guard isTranscribing,
              let info = note.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: typeValue) == .began else { return }
        print("🔄 Audio interrupted - pausing real-time transcription engine")
        pauseTranscription()
    }

    private func handleRouteChange(_ note: Notification) {
        guard isTranscribing,
              let info = note.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: reasonValue) == .oldDeviceUnavailable else { return }
        print("🔄 Route change (device unavailable) - pausing real-time transcription engine")
        pauseTranscription()
    }
    
    // MARK: - Transcription Control
    
    /// Start real-time transcription
    func startTranscription() {
        guard !isTranscribing else { return }
        
        // Check speech recognition permission
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            transcriptionError = "Speech recognition permission not granted"
            return
        }
        
        // Configure audio session for clean recording
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            if session.isInputGainSettable {
                try session.setInputGain(1.0)
            }
        } catch {
            transcriptionError = "Failed to configure audio session: \(error.localizedDescription)"
            return
        }
        
        // Initialize audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            transcriptionError = "Failed to initialize audio engine"
            return
        }
        
        // Start real-time transcription using enhanced transcriber
        recognitionRequest = SpeechTranscriber.shared.startRealTimeTranscription(
            audioEngine: audioEngine
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let transcript):
                    self?.currentTranscript = transcript
                    self?.transcriptionError = nil
                case .failure(let error):
                    self?.transcriptionError = error.localizedDescription
                }
            }
        }
        
        guard let recognitionRequest = recognitionRequest else {
            transcriptionError = "Failed to create recognition request"
            return
        }
        
        // Start audio engine
        do {
            try audioEngine.start()
            isTranscribing = true
            currentTranscript = ""
            transcriptionError = nil
            print("✅ Real-time transcription started")
        } catch {
            transcriptionError = "Failed to start audio engine: \(error.localizedDescription)"
            stopTranscription()
        }
    }
    
    /// Stop real-time transcription
    func stopTranscription() {
        guard isTranscribing else { return }
        
        // Stop audio engine
        audioEngine?.stop()
        
        // Stop recognition request
        SpeechTranscriber.shared.stopRealTimeTranscription(request: recognitionRequest)
        
        // Clean up
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isTranscribing = false
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
        
        print("✅ Real-time transcription stopped")
    }
    
    /// Pause transcription - saves current transcript and stops
    func pauseTranscription() {
        // Save current transcript before stopping
        let savedTranscript = currentTranscript
        
        // Fully stop transcription (SFSpeechAudioBufferRecognitionRequest cannot be reused)
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        // Clean up
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isTranscribing = false
        
        // Restore saved transcript
        currentTranscript = savedTranscript
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
        
        print("⏸️ Transcription paused (saved: \(savedTranscript.prefix(30))...)")
    }
    
    /// Resume transcription - restarts with saved transcript
    func resumeTranscription() {
        // Save current transcript to append to
        let savedTranscript = currentTranscript
        
        // Restart transcription fresh
        startTranscription()
        
        // Prepend saved transcript
        if !savedTranscript.isEmpty {
            currentTranscript = savedTranscript + " "
        }
        
        print("▶️ Transcription resumed (prepending: \(savedTranscript.prefix(30))...)")
    }
    
    /// Get final transcript and reset
    func getFinalTranscript() -> String {
        let final = currentTranscript
        currentTranscript = ""
        return final
    }
    
    // MARK: - Error Handling
    
    /// Clear transcription error
    func clearError() {
        transcriptionError = nil
    }
    
    /// Check if transcription is in error state
    var hasError: Bool {
        transcriptionError != nil
    }
    
    // MARK: - Audio Quality Monitoring
    
    /// Check if current audio setup is optimal for transcription
    func isAudioSetupOptimal() -> Bool {
        let inputNode = AVAudioEngine().inputNode
        let format = inputNode.outputFormat(forBus: 0)
        return format.channelCount == 1 && format.sampleRate >= 16000
    }
    
    /// Get current audio format information
    func getAudioFormatInfo() -> String {
        let inputNode = AVAudioEngine().inputNode
        let format = inputNode.outputFormat(forBus: 0)
        return """
        Audio Format:
        - Sample Rate: \(format.sampleRate) Hz
        - Channels: \(format.channelCount)
        - Format: \(format.commonFormat.rawValue)
        - Interleaved: \(format.isInterleaved)
        """
    }
} 