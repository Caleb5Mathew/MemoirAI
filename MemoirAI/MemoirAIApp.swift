///
//  MemoirAIApp.swift
//  MemoirAI
//
//  Created by user941803 on 4/6/25.
//

import SwiftUI
import RevenueCat
import Mixpanel

@main
struct MemoirAIApp: App {
  init() {
    // RevenueCat configuration from Info.plist
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
       !apiKey.isEmpty {
      Purchases.configure(withAPIKey: apiKey)
      Purchases.logLevel = .debug
      print("✅ RevenueCat configured successfully")
    } else {
      print("⚠️ RevenueCat not configured - API key not found in Info.plist")
    }

    // Mixpanel configuration
    Mixpanel.initialize(token: "6437139af64d0541c2a8a8e5157ae72f", trackAutomaticEvents: true)
    
    // Track app launch
    Mixpanel.mainInstance().track(event: "App Launched")
    
    // Check for first launch
    let isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    if isFirstLaunch {
        // Track first launch
        Mixpanel.mainInstance().track(event: "First Launch")
        
        // Mark as launched
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(RCSubscriptionManager.shared)
        // ← Here is the crucial line:
        .environment(
          \.managedObjectContext,
          PersistenceController.shared.container.viewContext
        )
    }
  }
}
