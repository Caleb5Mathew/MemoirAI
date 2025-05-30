//
//  MemoirAIApp.swift
//  MemoirAI
//
//  Created by user941803 on 4/6/25.
//



import SwiftUI
import RevenueCat

@main
struct MemoirAIApp: App {
  init() {
    // RevenueCat configuration
    // TODO: Add your RevenueCat API key to Info.plist with key "REVENUECAT_API_KEY"
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String,
       !apiKey.isEmpty,
       !apiKey.contains("YOUR_API") {
        Purchases.configure(withAPIKey: apiKey)
    } else {
        print("⚠️ RevenueCat not configured - using development mode")
        // For development/testing without RevenueCat
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(RCSubscriptionManager.shared)
    }
  }
}
