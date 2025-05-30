//
//  ImageGalleryViewModel.swift
//  MemoirAI
//
//  Created by user941803 on 5/10/25.
//

import SwiftUI
// For a more structured logging approach in a production app, consider using OSLog.
// import os.log // Uncomment if you want to use OSLog

@MainActor
class ImageGalleryViewModel: ObservableObject {
    // private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ImageGalleryViewModel") // Example for OSLog

    /// The array of AI-generated images to display
    @Published var images: [UIImage]
    /// The image currently selected for full-screen preview
    @Published var selectedImage: UIImage?

    init(images: [UIImage]) {
        self.images = images
    }

    /// Show a given image in the full-screen overlay
    func select(_ image: UIImage) {
        selectedImage = image
    }

    /// Dismiss the full-screen overlay
    func deselect() {
        selectedImage = nil
    }

    // If you add methods to modify the 'images' array, add debugging there too.
    // For example:
    // func updateImages(_ newImages: [UIImage]) {
    //     print("[ImageGalleryViewModel DEBUG] updateImages called with \(newImages.count) new images.")
    //     print("[ImageGalleryViewModel DEBUG] updateImages - 'images' count BEFORE update: \(self.images.count).")
    //     self.images = newImages
    //     print("[ImageGalleryViewModel DEBUG] updateImages - 'images' count AFTER update: \(self.images.count).")
    // }
    //
    // func addImage(_ image: UIImage) {
    //     print("[ImageGalleryViewModel DEBUG] addImage called for image with size: \(image.size).")
    //     print("[ImageGalleryViewModel DEBUG] addImage - 'images' count BEFORE adding: \(self.images.count).")
    //     self.images.append(image)
    //     print("[ImageGalleryViewModel DEBUG] addImage - 'images' count AFTER adding: \(self.images.count).")
    // }
}
