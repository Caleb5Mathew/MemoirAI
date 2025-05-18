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
    // Replace with your RevenueCat public API key
    Purchases.configure(withAPIKey: "APIKEY")
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(RCSubscriptionManager.shared)
    }
  }
}
