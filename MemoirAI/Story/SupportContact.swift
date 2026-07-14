//
//  SupportContact.swift
//  MemoirAI
//
//  Single source of truth for "Contact Support" mailto handling, so every
//  support entry point (Settings, Order Details, StoryPage alerts) shares
//  the same email, subject formatting, and no-Mail-app fallback.
//

import Foundation
import UIKit

enum SupportContact {
    static let email = "memoirstorybook@gmail.com"

    /// Builds a `mailto:` URL for the support address with a percent-encoded subject.
    /// Pure and side-effect free so it can be unit tested without touching `UIApplication`.
    static func mailtoURL(subject: String = "MemoirAI Support") -> URL? {
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        return URL(string: "mailto:\(email)?subject=\(encodedSubject)")
    }

    /// Opens Mail (or another mail client) addressed to support with the given subject.
    /// Falls back to copying the support address to the pasteboard — and invoking `onFallback`
    /// so the caller can surface a brief confirmation — when no mail client can handle `mailto:`
    /// (e.g. Simulator or a device with no Mail accounts configured).
    @MainActor
    static func contact(subject: String = "MemoirAI Support", onFallback: @escaping () -> Void = {}) {
        guard let url = mailtoURL(subject: subject), UIApplication.shared.canOpenURL(url) else {
            UIPasteboard.general.string = email
            onFallback()
            return
        }
        UIApplication.shared.open(url)
    }
}
