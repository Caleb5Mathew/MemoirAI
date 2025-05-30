import Foundation
import AVFoundation
import Combine

class AudioLevelMonitor: ObservableObject {
    @Published var averagePower: Float = -160.0
    @Published var peakPower: Float = -160.0
    @Published var normalizedLevel: Double = 0.0
    @Published var isVoiceActive: Bool = false
    @Published var waveformLevels: [Double] = Array(repeating: 0.0, count: 50)
    
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var voiceActivityBuffer: [Bool] = []
    private let voiceThreshold: Float = -40.0 // dB threshold for voice activity
    private let bufferSize = 10 // Number of samples to average for voice activity
    
    func startMonitoring(recorder: AVAudioRecorder) {
        self.audioRecorder = recorder
        
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            self.updateAudioLevels()
        }
    }
    
    func stopMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder = nil
        
        // Reset values
        averagePower = -160.0
        peakPower = -160.0
        normalizedLevel = 0.0
        isVoiceActive = false
        waveformLevels = Array(repeating: 0.0, count: 50)
        voiceActivityBuffer.removeAll()
    }
    
    private func updateAudioLevels() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        
        recorder.updateMeters()
        averagePower = recorder.averagePower(forChannel: 0)
        peakPower = recorder.peakPower(forChannel: 0)
        
        // Normalize the level (convert from dB to 0-1 range)
        // dB range is typically -160 to 0, we'll focus on -60 to 0 for better visualization
        let minDB: Float = -60.0
        let maxDB: Float = 0.0
        let clampedLevel = max(minDB, min(maxDB, averagePower))
        normalizedLevel = Double((clampedLevel - minDB) / (maxDB - minDB))
        
        // Update waveform levels array (shift left and add new value)
        waveformLevels.removeFirst()
        waveformLevels.append(normalizedLevel)
        
        // Voice activity detection
        updateVoiceActivity(level: averagePower)
    }
    
    private func updateVoiceActivity(level: Float) {
        // Add current level to buffer
        let isActiveNow = level > voiceThreshold
        voiceActivityBuffer.append(isActiveNow)
        
        // Keep buffer size manageable
        if voiceActivityBuffer.count > bufferSize {
            voiceActivityBuffer.removeFirst()
        }
        
        // Determine voice activity based on recent samples
        // Voice is considered active if at least 60% of recent samples are above threshold
        let activeCount = voiceActivityBuffer.filter { $0 }.count
        let activeRatio = Double(activeCount) / Double(voiceActivityBuffer.count)
        
        DispatchQueue.main.async {
            self.isVoiceActive = activeRatio > 0.6
        }
    }
    
    // Get smoothed level for animations
    func getSmoothedLevel() -> Double {
        // Use a combination of average and peak for more responsive visualization
        let avgNormalized = Double((max(-60.0, averagePower) + 60.0) / 60.0)
        let peakNormalized = Double((max(-60.0, peakPower) + 60.0) / 60.0)
        return (avgNormalized * 0.7 + peakNormalized * 0.3)
    }
} 