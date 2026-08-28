//
//  ATTHelper.swift
//  MemoirAI
//

import AppTrackingTransparency
import FBSDKCoreKit
import SwiftUI

final class ATTHelper: ObservableObject {
    @Published private(set) var trackingStatus: ATTrackingManager.AuthorizationStatus

    static let shared = ATTHelper()

    private init() {
        trackingStatus = ATTrackingManager.trackingAuthorizationStatus
    }

    static func advertiserTrackingEnabled(
        for status: ATTrackingManager.AuthorizationStatus
    ) -> Bool {
        status == .authorized
    }

    /// Applies the persisted ATT choice before Meta's SDK is initialized.
    static func applyCurrentAuthorizationToFacebook() {
        let status = ATTrackingManager.trackingAuthorizationStatus
        applyLegacyFacebookTrackingSetting(for: status)
    }

    /// Requests permission only while the choice is unresolved, then immediately
    /// applies the result to Meta's advertiser tracking switch.
    func requestTrackingPermission() {
        let currentStatus = ATTrackingManager.trackingAuthorizationStatus
        guard currentStatus == .notDetermined else {
            updateFacebookTracking(for: currentStatus)
            return
        }

        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.updateFacebookTracking(for: status)
            }
        }
    }

    private func updateFacebookTracking(for status: ATTrackingManager.AuthorizationStatus) {
        trackingStatus = status
        Self.applyLegacyFacebookTrackingSetting(for: status)

        #if DEBUG
        print("ATT status: \(status.rawValue), Meta advertiser tracking: \(Self.advertiserTrackingEnabled(for: status))")
        #endif
    }

    var shouldShowATTPrompt: Bool {
        trackingStatus == .notDetermined
    }

    private static func applyLegacyFacebookTrackingSetting(
        for status: ATTrackingManager.AuthorizationStatus
    ) {
        if #unavailable(iOS 17.0) {
            Settings.shared.isAdvertiserTrackingEnabled = advertiserTrackingEnabled(for: status)
        }
    }
}
