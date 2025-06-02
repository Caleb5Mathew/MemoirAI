//
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
    // RevenueCat configuration …
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "") as? String,
       !apiKey.isEmpty,
       !apiKey.contains("YOUR_API") {
      Purchases.configure(withAPIKey: apiKey)
    } else {
      print("⚠️ RevenueCat not configured ‒ using development mode")
    }

    // Mixpanel configuration
      Mixpanel.initialize(token: "6437139af64d0541c2a8a8e5157ae72f", trackAutomaticEvents: true)
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
