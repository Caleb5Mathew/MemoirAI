import Foundation
import AVFoundation
import Combine

/// Manages audio session configuration for optimal speech recognition accuracy
final class AudioSessionManager: ObservableObject {
    static let shared = AudioSessionManager()
    
    @Published var isInputRouteChanged = false
    
    private var routeChangeObserver: NSObjectProtocol?
    private let session = AVAudioSession.sharedInstance()
    
    private init() {
        setupRouteChangeObserver()
    }
    
    deinit {
        removeRouteChangeObserver()
    }
    
    // MARK: - Audio Session Configuration
    
    /// Configure audio session for clean recording (speech recognition optimized)
    func configureForRecording() throws {
        // Clean recording audio session: category record, mode measurement
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
        
        // Set input gain if available
        if session.isInputGainSettable {
            try session.setInputGain(1.0) // Optimal for speech recognition
        }
        
        print("✅ Audio session configured for clean recording")
        print("📊 Audio format info: \(getCurrentAudioFormatInfo())")
        print("🎯 Audio setup optimal: \(isAudioInputOptimal())")
    }
    
    /// Configure audio session for play and record (if needed for playback during recording)
    func configureForPlayAndRecord() throws {
        // If must play audio while recording, use playAndRecord with measurement mode
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        
        // Set input gain if available
        if session.isInputGainSettable {
            try session.setInputGain(1.0)
        }
        
        print("✅ Audio session configured for play and record")
        print("📊 Audio format info: \(getCurrentAudioFormatInfo())")
        print("🎯 Audio setup optimal: \(isAudioInputOptimal())")
    }
    
    /// Deactivate audio session
    func deactivate() throws {
        try session.setActive(false)
        print("✅ Audio session deactivated")
    }
    
    // MARK: - Route Change Handling
    
    private func setupRouteChangeObserver() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }
    
    private func removeRouteChangeObserver() {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
    }
    
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            // Input route changed - notify to re-establish audio tap
            DispatchQueue.main.async {
                self.isInputRouteChanged = true
            }
            print("🔄 Input route changed - audio tap should be re-established")
            
        default:
            break
        }
    }
    
    /// Reset route change flag
    func resetRouteChangeFlag() {
        isInputRouteChanged = false
    }
    
    // MARK: - Audio Format Optimization
    
    /// Get optimal recording format for speech recognition
    func getOptimalRecordingFormat() -> AVAudioFormat {
        // Use mic's native format (don't resample or force stereo)
        let inputNode = AVAudioEngine().inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        
        // Prefer mono for speech recognition if available
        if nativeFormat.channelCount > 1 {
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: nativeFormat.sampleRate,
                channels: 1,
                interleaved: false
            ) ?? nativeFormat
        }
        
        return nativeFormat
    }
    
    /// Get optimal buffer size for speech recognition
    func getOptimalBufferSize() -> AVAudioFrameCount {
        // Keep buffer size small and consistent for real-time processing
        return 1024
    }
    
    // MARK: - Audio Quality Monitoring
    
    /// Check if current audio input is optimal for speech recognition
    func isAudioInputOptimal() -> Bool {
        let inputNode = AVAudioEngine().inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // Check for optimal conditions
        let isMono = format.channelCount == 1
        let isHighSampleRate = format.sampleRate >= 16000
        let isFloatFormat = format.commonFormat == .pcmFormatFloat32
        
        return isMono && isHighSampleRate && isFloatFormat
    }
    
    /// Get current audio input format info
    func getCurrentAudioFormatInfo() -> String {
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