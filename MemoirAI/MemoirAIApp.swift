//
//  MemoirAIApp.swift
//  MemoirAI
//

import SwiftUI
import RevenueCat
import Mixpanel
import FBSDKCoreKit            // ← 1. add import
import FirebaseCore
import GoogleSignIn

// MARK: - UIKit delegate wrapper
final class FBAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        // Initialize Firebase FIRST
        FirebaseConfig.shared.configure()

        // 2. Boot the Facebook SDK
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )

        // 3. Initialize Facebook tracking (will be updated by ATT helper)
        Settings.shared.isAutoLogAppEventsEnabled = true
        // Note: isAdvertiserTrackingEnabled now managed by ATTHelper

        print("✅ FBSDK version:", Settings.shared.sdkVersion)
        return true
    }

    // Needed only if you use FB Login / App Links / Google Sign-In
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        if url.scheme == "memoirai" {
            if url.host == "order-complete" {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let sessionId = components?.queryItems?.first(where: { $0.name == "session_id" })?.value
                if let sessionId = sessionId {
                    print("[Order] Stripe return — session_id: \(sessionId)")
                    UserDefaults.standard.set(sessionId, forKey: "lastCompletedStripeSessionId")
                }
                NotificationCenter.default.post(name: .orderComplete, object: nil, userInfo: ["url": url, "sessionId": sessionId as Any])
            } else if url.host == "order-cancelled" {
                NotificationCenter.default.post(name: .orderCancelled, object: nil)
            }
            return true
        }
        if GIDSignIn.sharedInstance.handle(url) { return true }
        return ApplicationDelegate.shared.application(app, open: url, options: options)
    }
}

extension Notification.Name {
    static let orderComplete = Notification.Name("orderComplete")
    static let orderCancelled = Notification.Name("orderCancelled")
}

@main
struct MemoirAIApp: App {
    @StateObject private var profileVM = ProfileViewModel()
    
    let persistenceController = PersistenceController.shared

    // 4. Tell SwiftUI to install the delegate
    @UIApplicationDelegateAdaptor(FBAppDelegate.self) var fbDelegate

    init() {
        //  ❇️  Always give RevenueCat a stable user-ID so Meta gets `app_user_id`
        let rcUserDefaultsKey = "memoirai_rc_user_id"
        let uuid = UserDefaults.standard.string(forKey: rcUserDefaultsKey) ?? {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: rcUserDefaultsKey)
            return newID
        }()

        // Configure RevenueCat FIRST – before any subscription manager access
        Purchases.logLevel = .debug
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
           !apiKey.isEmpty {
            Purchases.configure(withAPIKey: apiKey, appUserID: uuid)
            print("✅ RevenueCat configured with API key: \(apiKey) • userID: \(uuid)")
        } else {
            print("❌ RevenueCat API key not found in Info.plist")
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
                .environmentObject(profileVM)
                .environmentObject(iCloudManager.shared)
                .environmentObject(RCSubscriptionManager.shared)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                // Our custom UI uses light backgrounds; force a light appearance so dynamic text stays dark
                .preferredColorScheme(.light)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Check for untranscribed memories when app becomes active
                    PermissionManager.shared.handleAppDidBecomeActive()
                }
        }
    }
}
