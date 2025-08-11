//
//  UsageTracker.swift
//  MemoirAI
//
//  Created by user941803 on 5/9/25.
//


import Foundation
import StoreKit

class UsageTracker: ObservableObject {
    static let shared = UsageTracker()
    
    @Published var recordingCount: Int {
        didSet {
            UserDefaults.standard.set(recordingCount, forKey: "recordingCount")
        }
    }
    
    @Published var hasRequestedReview: Bool {
        didSet {
            UserDefaults.standard.set(hasRequestedReview, forKey: "hasRequestedReview")
        }
    }
    
    // Track when the first recording was completed for better timing
    private var firstRecordingDate: Date? {
        get {
            UserDefaults.standard.object(forKey: "firstRecordingDate") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "firstRecordingDate")
        }
    }
    
    private init() {
        self.recordingCount = UserDefaults.standard.integer(forKey: "recordingCount")
        self.hasRequestedReview = UserDefaults.standard.bool(forKey: "hasRequestedReview")
    }
    
    func recordingCompleted() {
        recordingCount += 1
        
        // Track the first recording date for better timing
        if recordingCount == 1 {
            firstRecordingDate = Date()
        }
        
        // Request review after 1st recording, but only once and with good timing
        if recordingCount == 1 && !hasRequestedReview {
            requestReviewWithDelay()
        }
    }
    
    private func requestReviewWithDelay() {
        guard !hasRequestedReview else { return }
        
        // Wait a moment to let the user appreciate their first recording
        // This gives them time to see the success state and feel accomplished
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.requestReview()
        }
    }
    
    func requestReview() {
        guard !hasRequestedReview else { return }
        
        // Additional check: Don't request review if app just launched
        // This ensures user has had a chance to use the app meaningfully
        guard let firstRecording = firstRecordingDate,
              Date().timeIntervalSince(firstRecording) > 30 else {
            print("📱 Review request skipped - too soon after first recording")
            return
        }
        
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            print("📱 Requesting App Store review after first recording")
            SKStoreReviewController.requestReview(in: scene)
            hasRequestedReview = true
        }
    }
    
    // Method to manually trigger review (e.g., from settings)
    func requestReviewManually() {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
    
    // Reset review request capability (useful for testing or major app updates)
    func resetReviewRequest() {
        hasRequestedReview = false
        UserDefaults.standard.set(false, forKey: "hasRequestedReview")
        print("📱 Review request capability reset")
    }
}
