import Foundation
import Speech
import AVFoundation
import SwiftUI

/// Manages speech recognition and microphone permissions with professional UI
@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var showSpeechPermissionAlert = false
    @Published var showMicrophonePermissionAlert = false
    @Published var showSettingsAlert = false
    @Published var hasUntranscribedMemories = false
    
    private let transcriptionManager = BatchTranscriptionManager.shared
    
    private init() {
        checkForUntranscribedMemories()
    }
    
    // MARK: - Speech Recognition Permission
    
    /// Check if speech recognition is authorized
    var isSpeechRecognitionAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    /// Request speech recognition permission with professional popup
    func requestSpeechRecognitionPermission() {
        let status = SFSpeechRecognizer.authorizationStatus()
        
        switch status {
        case .authorized:
            // Already authorized - check for untranscribed memories
            checkAndTranscribeIfNeeded()
            
        case .notDetermined:
            // First time request
            SFSpeechRecognizer.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        self?.checkAndTranscribeIfNeeded()
                    } else {
                        self?.showSpeechPermissionAlert = true
                    }
                }
            }
            
        case .denied, .restricted:
            // Permission denied - show settings alert
            showSpeechPermissionAlert = true
        @unknown default:
            showSpeechPermissionAlert = true
        }
    }
    
    /// Check for untranscribed memories and transcribe if permission is available
    func checkAndTranscribeIfNeeded() {
        guard isSpeechRecognitionAuthorized else { return }
        
        if transcriptionManager.hasUntranscribed {
            // Start automatic transcription
            transcriptionManager.start { [weak self] in
                DispatchQueue.main.async {
                    self?.checkForUntranscribedMemories()
                }
            }
        }
    }
    
    // MARK: - Microphone Permission
    
    /// Check if microphone permission is granted
    var isMicrophoneAuthorized: Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted
    }
    
    /// Request microphone permission
    func requestMicrophonePermission() {
        let status = AVAudioSession.sharedInstance().recordPermission
        
        switch status {
        case .granted:
            // Already granted
            break
            
        case .denied:
            // Permission denied - show settings alert
            showMicrophonePermissionAlert = true
            
        case .undetermined:
            // First time request
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if !granted {
                        self?.showMicrophonePermissionAlert = true
                    }
                }
            }
        @unknown default:
            showMicrophonePermissionAlert = true
        }
    }
    
    // MARK: - Settings Navigation
    
    /// Open app settings
    func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    // MARK: - Memory Checking
    
    /// Check if there are untranscribed memories
    private func checkForUntranscribedMemories() {
        hasUntranscribedMemories = transcriptionManager.hasUntranscribed
    }
    
    /// Public method to refresh untranscribed memory count
    func refreshUntranscribedCount() {
        checkForUntranscribedMemories()
    }
    
    /// Check and transcribe when app becomes active
    func handleAppDidBecomeActive() {
        // Check if we have untranscribed memories and speech recognition is authorized
        if hasUntranscribedMemories && isSpeechRecognitionAuthorized {
            // Small delay to ensure UI is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.checkAndTranscribeIfNeeded()
            }
        }
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let permissionStatusChanged = Notification.Name("permissionStatusChanged")
    static let transcriptionCompleted = Notification.Name("transcriptionCompleted")
} 