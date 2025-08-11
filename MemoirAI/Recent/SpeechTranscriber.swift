//
//  SpeechTranscriber.swift
//  MemoirAI
//
//  Created by user941803 on 5/3/25.
//

import Foundation
import Speech
import AVFoundation

/// Enhanced speech transcriber implementing Apple's accuracy checklist
final class SpeechTranscriber {
    static let shared = SpeechTranscriber()
    
    // Force server recognition with explicit locale
    private let recognizer: SFSpeechRecognizer?
    
    // Contextual hints for memoir-specific terms
    private let contextualHints = [
        "MemoirAI", "life story", "memory", "memories", "childhood", "family",
        "grandparent", "grandmother", "grandfather", "parents", "siblings",
        "school", "college", "university", "career", "job", "work", "marriage",
        "wedding", "children", "kids", "birthday", "holiday", "vacation",
        "travel", "home", "house", "neighborhood", "friends", "community",
        "faith", "religion", "church", "temple", "prayer", "meditation",
        "hobby", "passion", "interest", "sport", "music", "art", "cooking",
        "garden", "pet", "dog", "cat", "pet", "animal", "love", "romance",
        "dating", "relationship", "divorce", "loss", "grief", "death",
        "illness", "health", "hospital", "doctor", "nurse", "medicine",
        "war", "military", "service", "veteran", "immigration", "immigrant",
        "culture", "tradition", "heritage", "ancestry", "genealogy",
        "photograph", "photo", "picture", "album", "scrapbook", "diary",
        "journal", "letter", "postcard", "telegram", "phone", "television",
        "radio", "computer", "internet", "social media", "Facebook",
        "Instagram", "technology", "innovation", "change", "progress",
        "history", "historical", "era", "decade", "century", "generation",
        "legacy", "heritage", "tradition", "custom", "ritual", "ceremony",
        "celebration", "party", "festival", "holiday", "anniversary",
        "milestone", "achievement", "accomplishment", "success", "failure",
        "challenge", "obstacle", "struggle", "triumph", "victory", "defeat",
        "lesson", "wisdom", "knowledge", "experience", "adventure",
        "journey", "path", "road", "destination", "goal", "dream", "hope",
        "faith", "belief", "value", "principle", "moral", "ethics",
        "character", "personality", "identity", "self", "soul", "spirit",
        "heart", "mind", "body", "soul", "emotion", "feeling", "mood",
        "happiness", "joy", "sadness", "anger", "fear", "anxiety",
        "peace", "calm", "excitement", "enthusiasm", "passion", "love",
        "hate", "forgiveness", "reconciliation", "healing", "growth",
        "transformation", "change", "evolution", "development", "progress"
    ]
    
    private init() {
        // Force server recognition with explicit locale
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        // Request authorization
        SFSpeechRecognizer.requestAuthorization { _ in }
    }
    
    /// Transcribe the given file URL with enhanced accuracy settings
    func transcribe(url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard let recognizer = recognizer else {
            completion(.failure(SpeechTranscriberError.recognizerNotAvailable))
            return
        }
        
        // Check authorization
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            completion(.failure(SpeechTranscriberError.notAuthorized))
            return
        }
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        
        // Force server recognition (not on-device)
        request.requiresOnDeviceRecognition = false
        
        // Set task hint for long-form dictation
        request.taskHint = .dictation
        
        // Add contextual hints for better accuracy
        request.contextualStrings = contextualHints
        
        // Enable partial results for better handling
        request.shouldReportPartialResults = true
        
        var finalTranscript = ""
        var isFinal = false
        
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                // Clean shutdown on errors
                task.cancel()
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let result = result else { return }
            
            // Handle partial results
            if result.isFinal {
                finalTranscript = result.bestTranscription.formattedString
                isFinal = true
                
                // Clean shutdown on completion
                task.cancel()
                DispatchQueue.main.async {
                    completion(.success(finalTranscript))
                }
            } else {
                // Update partial transcript
                finalTranscript = result.bestTranscription.formattedString
            }
        }
        
        // Set a timeout for the recognition task
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            if !isFinal {
                task.cancel()
                completion(.failure(SpeechTranscriberError.timeout))
            }
        }
    }
    
    /// Real-time transcription during recording
    func startRealTimeTranscription(
        audioEngine: AVAudioEngine,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> SFSpeechAudioBufferRecognitionRequest? {
        guard let recognizer = recognizer else {
            completion(.failure(SpeechTranscriberError.recognizerNotAvailable))
            return nil
        }
        
        // Check authorization
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            completion(.failure(SpeechTranscriberError.notAuthorized))
            return nil
        }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        
        // Force server recognition
        request.requiresOnDeviceRecognition = false
        
        // Set task hint for dictation
        request.taskHint = .dictation
        
        // Add contextual hints
        request.contextualStrings = contextualHints
        
        // Enable partial results
        request.shouldReportPartialResults = true
        
        var finalTranscript = ""
        
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                task.cancel()
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let result = result else { return }
            
            if result.isFinal {
                finalTranscript = result.bestTranscription.formattedString
                task.cancel()
                DispatchQueue.main.async {
                    completion(.success(finalTranscript))
                }
            } else {
                finalTranscript = result.bestTranscription.formattedString
            }
        }
        
        // Install tap on input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        return request
    }
    
    /// Stop real-time transcription
    func stopRealTimeTranscription(request: SFSpeechAudioBufferRecognitionRequest?) {
        request?.endAudio()
    }
}

// MARK: - Error Types
enum SpeechTranscriberError: Error, LocalizedError {
    case recognizerNotAvailable
    case notAuthorized
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available for this locale"
        case .notAuthorized:
            return "Speech recognition permission not granted"
        case .timeout:
            return "Transcription timed out"
        }
    }
}
