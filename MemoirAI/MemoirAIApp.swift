//
//  MemoirAIApp.swift
//  MemoirAI
//

import SwiftUI
import RevenueCat
import Mixpanel
import FBSDKCoreKit            // ← 1. add import

// MARK: - UIKit delegate wrapper
final class FBAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        // 2. Boot the Facebook SDK
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )

        // 3. Enable tracking if you have ATT consent
        Settings.shared.isAdvertiserTrackingEnabled = true   // or gate behind ATT prompt
        Settings.shared.isAutoLogAppEventsEnabled   = true   // optional auto events

        print("✅ FBSDK version:", Settings.shared.sdkVersion)
        return true
    }

    // Needed only if you use FB Login / App Links
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        return ApplicationDelegate.shared.application(app, open: url, options: options)
    }
}

@main
struct MemoirAIApp: App {

    // 4. Tell SwiftUI to install the delegate
    @UIApplicationDelegateAdaptor(FBAppDelegate.self) var fbDelegate

    init() {
        // ─ RevenueCat ─────────────────────────────────────────────
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "appl_HTtNKyhVPddJOKrcqGCnWtvZcto") as? String,
           !apiKey.isEmpty {
            Purchases.configure(withAPIKey: apiKey)
            Purchases.logLevel = .debug
        }

        // ─ Mixpanel ───────────────────────────────────────────────
        Mixpanel.initialize(token: "6437139af64d0541c2a8a8e5157ae72f",
                            trackAutomaticEvents: true)
        Mixpanel.mainInstance().track(event: "App Launched")

        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            Mixpanel.mainInstance().track(event: "First Launch")
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(RCSubscriptionManager.shared)
                .environment(\.managedObjectContext,
                              PersistenceController.shared.container.viewContext)
        }
    }
}
