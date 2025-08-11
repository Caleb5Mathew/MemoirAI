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
    
    private init() {
        // Simplified initialization without complex audio session management
    }
    
    deinit {
        stopTranscription()
    }
    
    // MARK: - Route Change Handling
    
    private func handleRouteChange() {
        // Simplified route change handling
        if isTranscribing {
            print("🔄 Route change detected - restarting transcription")
            stopTranscription()
            startTranscription()
        }
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
    
    /// Pause transcription (keep audio tap but stop processing)
    func pauseTranscription() {
        recognitionTask?.cancel()
        recognitionTask = nil
        print("⏸️ Transcription paused")
    }
    
    /// Resume transcription
    func resumeTranscription() {
        guard isTranscribing, let recognitionRequest = recognitionRequest else { return }
        
        // Recreate recognition task
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            transcriptionError = "Speech recognizer not available"
            return
        }
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.transcriptionError = error.localizedDescription
                    return
                }
                
                guard let result = result else { return }
                
                if result.isFinal {
                    self?.currentTranscript = result.bestTranscription.formattedString
                } else {
                    self?.currentTranscript = result.bestTranscription.formattedString
                }
            }
        }
        
        print("▶️ Transcription resumed")
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