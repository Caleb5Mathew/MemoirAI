//
//  FirebaseConfig.swift
//  MemoirAI
//
//  Firebase initialization and configuration
//

import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

/// Handles Firebase SDK initialization and configuration
final class FirebaseConfig {
    
    static let shared = FirebaseConfig()
    
    private(set) var isConfigured = false
    
    private init() {}
    
    /// Initialize Firebase SDK - call this in App's init()
    func configure() {
        guard !isConfigured else {
            print("⚠️ Firebase already configured")
            return
        }

        #if canImport(FirebaseAppCheck)
        #if targetEnvironment(simulator)
        // Simulator: DeviceCheck is unavailable. Debug App Check triggers token exchange to
        // firebaseappcheck.googleapis.com — if that API is disabled, Xcode spams 403 + fetcher errors.
        // Opt in with UserDefaults `MemoirAI_EnableAppCheckDebug` = true when your project has
        // App Check properly enabled and you need enforced tokens in Simulator.
        let appCheckDebug = UserDefaults.standard.bool(forKey: "MemoirAI_EnableAppCheckDebug")
        if appCheckDebug {
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
            print("🔐 App Check (Simulator): Debug provider enabled — register this device’s debug token in Firebase Console if enforcement is on.")
        } else {
            print(
                "🔐 App Check (Simulator): no provider configured (default). " +
                "Firestore console logs about DeviceCheck are often benign; " +
                "set UserDefaults key MemoirAI_EnableAppCheckDebug=true only when you need App Check tokens in Simulator."
            )
        }
        #else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        print("🔐 App Check (Device): DeviceCheck provider configured.")
        #endif
        #endif
        
        FirebaseApp.configure()
        isConfigured = true
        
        // Configure Firestore settings
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
        
        print("✅ Firebase configured successfully")
        print("✅ Firestore offline persistence enabled")
    }
    
    /// Get the current Firebase Auth user ID
    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    /// Check if user is signed in
    var isSignedIn: Bool {
        Auth.auth().currentUser != nil
    }
}
