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
                Task { @MainActor in
                    OrderCartStore.shared.clear()
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
    static let bookCoverBackfillComplete = Notification.Name("bookCoverBackfillComplete")
    static let memoriesHydratedFromFirestore = Notification.Name("memoriesHydratedFromFirestore")
    /// iOS is about to suspend; flush partial generation state to disk (see `StorybookGenerationBackgroundTask`).
    static let storybookGenerationBackgroundExpiring = Notification.Name("storybookGenerationBackgroundExpiring")
    /// `userInfo["bookSyncCountDelta"]` as `Int` (+1 / -1) — refcount for concurrent `queueBookSync` (legacy `isUploading` still accepted).
    static let storybookCloudUploadActivity = Notification.Name("storybookCloudUploadActivity")
    /// `userInfo["profileId"]` as `String` (UUID) when a generation resume marker is cleared.
    static let generationProgressMarkerChanged = Notification.Name("generationProgressMarkerChanged")
    /// Navigate to `StoryPage` for cloud storybook generation (banner tap / secondary affordance).
    static let navigateToCloudStorybookGeneration = Notification.Name("memoirai.navigateToCloudStorybookGeneration")
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

            // Restore receipt-backed entitlements, then refresh RCSubscriptionManager so UI gates update
            // (RCManager’s own init Task may race; this sequence runs on the main actor after configure).
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard Purchases.isConfigured else { return }
                do {
                    _ = try await Purchases.shared.restorePurchases()
                    print("✅ RevenueCat restorePurchases completed on launch")
                } catch {
                    print("⚠️ RevenueCat restorePurchases on launch failed: \(error.localizedDescription)")
                }
                await RCSubscriptionManager.shared.refreshCustomerInfo()
            }
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
                .environmentObject(TutorialCoordinator.shared)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                // Our custom UI uses light backgrounds; force a light appearance so dynamic text stays dark
                .preferredColorScheme(.light)
                .onAppear {
                    GenerationProgressMarker.clearStaleOnLaunchIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    PermissionManager.shared.handleAppDidBecomeActive()
                    Task { @MainActor in
                        guard Purchases.isConfigured else { return }
                        await RCSubscriptionManager.shared.refreshCustomerInfo()
                    }
                    Task {
                        await FirestoreSyncService.shared.retryPendingSyncs(for: profileVM.selectedProfile.id)
                    }
                }
        }
    }
}
