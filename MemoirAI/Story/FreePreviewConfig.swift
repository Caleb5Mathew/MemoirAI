//
//  FreePreviewConfig.swift
//  MemoirAI
//
//  Created by user941803 on 7/4/25.
//


import Foundation

/// Central place for free-preview limits so we only change one number.
struct FreePreviewConfig {
    /// Maximum pages (images) a non-subscriber can generate in their single free preview.
    static let maxPagesWithoutSubscription = 1
}
