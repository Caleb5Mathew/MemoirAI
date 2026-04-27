//
//  StorageService.swift
//  MemoirAI
//
//  Handles uploading files to Firebase Storage
//

import Foundation
import FirebaseStorage
import FirebaseAuth
import UIKit
import CryptoKit

/// Service for uploading and managing files in Firebase Storage
final class StorageService {
    
    static let shared = StorageService()
    
    private let storage = Storage.storage()
    
    private init() {}

    struct UploadedBookPageArtifact {
        let storagePath: String
        let downloadURL: String
        let pixelWidth: Int
        let pixelHeight: Int
        let bytes: Int
        let checksum: String
    }

    struct UploadedBookPageArtifacts {
        let png: UploadedBookPageArtifact
        let jpeg: UploadedBookPageArtifact
    }

    struct UploadedBookPdfArtifact {
        let storagePath: String
        let downloadURL: String
        let bytes: Int
    }

    private func resizedForBookUpload(_ image: UIImage, isKidsBook: Bool) -> UIImage {
        // 300 DPI print dimensions:
        // - Kids book: 11 x 8.5 -> 3300 x 2550 (landscape)
        // - Regular book: 8.5 x 11 -> 2550 x 3300 (portrait)
        let targetSize = isKidsBook
            ? CGSize(width: 3300, height: 2550)
            : CGSize(width: 2550, height: 3300)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            // Keep full image content and fit into the exact page canvas.
            UIColor(red: 250.0/255.0, green: 248.0/255.0, blue: 243.0/255.0, alpha: 1.0).setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))

            let sourceSize = image.size
            guard sourceSize.width > 0, sourceSize.height > 0 else { return }
            let widthScale = targetSize.width / sourceSize.width
            let heightScale = targetSize.height / sourceSize.height
            let scale = min(widthScale, heightScale)

            let drawWidth = sourceSize.width * scale
            let drawHeight = sourceSize.height * scale
            let drawRect = CGRect(
                x: (targetSize.width - drawWidth) / 2.0,
                y: (targetSize.height - drawHeight) / 2.0,
                width: drawWidth,
                height: drawHeight
            )
            image.draw(in: drawRect)
        }
    }
    
    // MARK: - Audio Upload
    
    /// Upload audio data and return the download URL
    func uploadAudio(_ audioData: Data, memoryId: String) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw StorageError.notAuthenticated
        }
        
        let path = "users/\(userId)/audio/\(memoryId).caf"
        let ref = storage.reference().child(path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "audio/x-caf"
        
        _ = try await ref.putDataAsync(audioData, metadata: metadata)
        let downloadURL = try await ref.downloadURL()
        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .firebaseStorage,
                operation: .firebaseUpload,
                model: "firebase-storage-audio",
                statusCode: 200,
                success: true,
                durationMs: 0,
                promptCharacters: 0,
                inputTokens: 0,
                outputTokens: 0,
                inputImageCount: 0,
                outputImageCount: 0,
                uploadedBytes: audioData.count
            )
        )
        
        print("✅ Uploaded audio to: \(downloadURL.absoluteString)")
        return downloadURL.absoluteString
    }
    
    // MARK: - Image Upload
    
    /// Upload image data and return the download URL
    func uploadImage(_ imageData: Data, memoryId: String, imageIndex: Int) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw StorageError.notAuthenticated
        }
        
        let path = "users/\(userId)/images/\(memoryId)_\(imageIndex).jpg"
        let ref = storage.reference().child(path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await ref.downloadURL()
        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .firebaseStorage,
                operation: .firebaseUpload,
                model: "firebase-storage-image",
                statusCode: 200,
                success: true,
                durationMs: 0,
                promptCharacters: 0,
                inputTokens: 0,
                outputTokens: 0,
                inputImageCount: 0,
                outputImageCount: 1,
                uploadedBytes: imageData.count
            )
        )
        
        print("✅ Uploaded image to: \(downloadURL.absoluteString)")
        return downloadURL.absoluteString
    }
    
    /// Upload UIImage and return the download URL
    func uploadImage(_ image: UIImage, memoryId: String, imageIndex: Int, compressionQuality: CGFloat = 0.8) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: compressionQuality) else {
            throw StorageError.invalidImageData
        }
        return try await uploadImage(imageData, memoryId: memoryId, imageIndex: imageIndex)
    }
    
    // MARK: - Book PDF Upload
    
    /// Upload PDF data and return the download URL
    func uploadBookPDF(_ pdfData: Data, bookId: String) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw StorageError.notAuthenticated
        }
        
        let path = "users/\(userId)/books/\(bookId).pdf"
        let ref = storage.reference().child(path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "application/pdf"
        
        _ = try await ref.putDataAsync(pdfData, metadata: metadata)
        let downloadURL = try await ref.downloadURL()
        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .firebaseStorage,
                operation: .firebaseUpload,
                model: "firebase-storage-pdf",
                statusCode: 200,
                success: true,
                durationMs: 0,
                promptCharacters: 0,
                inputTokens: 0,
                outputTokens: 0,
                inputImageCount: 0,
                outputImageCount: 0,
                uploadedBytes: pdfData.count
            )
        )
        
        print("✅ Uploaded book PDF to: \(downloadURL.absoluteString)")
        return downloadURL.absoluteString
    }
    
    // MARK: - Book Page Image Upload
    
    /// Upload a book page image and return the download URL
    func uploadBookPageImage(_ image: UIImage, bookId: String, pageIndex: Int, isKidsBook: Bool) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw StorageError.notAuthenticated
        }
        
        let preparedImage = resizedForBookUpload(image, isKidsBook: isKidsBook)
        guard let imageData = preparedImage.jpegData(compressionQuality: 0.85) else {
            throw StorageError.invalidImageData
        }
        
        let path = "users/\(userId)/books/\(bookId)/page_\(pageIndex).jpg"
        let ref = storage.reference().child(path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await ref.downloadURL()

        let pixelWidth = Int(preparedImage.size.width * preparedImage.scale)
        let pixelHeight = Int(preparedImage.size.height * preparedImage.scale)
        print("✅ Uploaded book page image \(pageIndex) to Firebase: \(pixelWidth)x\(pixelHeight)px (\(isKidsBook ? "kids 11x8.5" : "regular 8.5x11"))")
        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .firebaseStorage,
                operation: .firebaseUpload,
                model: "firebase-storage-book-page",
                statusCode: 200,
                success: true,
                durationMs: 0,
                promptCharacters: 0,
                inputTokens: 0,
                outputTokens: 0,
                inputImageCount: 0,
                outputImageCount: 1,
                uploadedBytes: imageData.count
            )
        )
        
        return downloadURL.absoluteString
    }

    /// Upload a rendered book page as PNG master and return metadata.
    func uploadRenderedBookPagePNG(_ image: UIImage, bookId: String, pageIndex: Int, isKidsBook: Bool) async throws -> UploadedBookPageArtifact {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw StorageError.notAuthenticated
        }

        let preparedImage = resizedForBookUpload(image, isKidsBook: isKidsBook)
        guard let imageData = preparedImage.pngData() else {
            throw StorageError.invalidImageData
        }

        let path = String(format: "users/%@/bookVersions/%@/pages/page_%03d.png", userId, bookId, pageIndex)
        let ref = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = "image/png"

        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await ref.downloadURL()

        let pixelWidth = Int(preparedImage.size.width * preparedImage.scale)
        let pixelHeight = Int(preparedImage.size.height * preparedImage.scale)
        let checksum = sha256Hex(imageData)

        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .firebaseStorage,
                operation: .firebaseUpload,
                model: "firebase-storage-book-page-png",
                statusCode: 200,
                success: true,
                durationMs: 0,
                promptCharacters: 0,
                inputTokens: 0,
                outputTokens: 0,
                inputImageCount: 0,
                outputImageCount: 1,
                uploadedBytes: imageData.count
            )
        )

        return UploadedBookPageArtifact(
            storagePath: path,
            downloadURL: downloadURL.absoluteString,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            bytes: imageData.count,
            checksum: checksum
        )
    }

    /// Upload both print-master PNG and delivery JPEG for a rendered page.
    func uploadRenderedBookPageArtifacts(_ image: UIImage, bookId: String, pageIndex: Int, isKidsBook: Bool) async throws -> UploadedBookPageArtifacts {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw StorageError.notAuthenticated
        }
        return try await uploadRenderedBookPageArtifacts(
            image,
            bookId: bookId,
            pageIndex: pageIndex,
            isKidsBook: isKidsBook,
            asUserId: userId
        )
    }

    /// Same as `uploadRenderedBookPageArtifacts` but uses a fixed Storage owner id (avoids mid-flow `Auth` uid changes during long syncs).
    func uploadRenderedBookPageArtifacts(
        _ image: UIImage,
        bookId: String,
        pageIndex: Int,
        isKidsBook: Bool,
        asUserId userId: String
    ) async throws -> UploadedBookPageArtifacts {
        let preparedImage = resizedForBookUpload(image, isKidsBook: isKidsBook)
        guard let pngData = preparedImage.pngData(),
              let jpegData = preparedImage.jpegData(compressionQuality: 0.90) else {
            throw StorageError.invalidImageData
        }

        let pngPath = String(format: "users/%@/bookVersions/%@/pages/page_%03d.png", userId, bookId, pageIndex)
        let pngRef = storage.reference().child(pngPath)
        let pngMetadata = StorageMetadata()
        pngMetadata.contentType = "image/png"
        _ = try await pngRef.putDataAsync(pngData, metadata: pngMetadata)
        let pngURL = try await pngRef.downloadURL()

        let jpegPath = String(format: "users/%@/bookVersions/%@/pages/page_%03d.jpg", userId, bookId, pageIndex)
        let jpegRef = storage.reference().child(jpegPath)
        let jpegMetadata = StorageMetadata()
        jpegMetadata.contentType = "image/jpeg"
        _ = try await jpegRef.putDataAsync(jpegData, metadata: jpegMetadata)
        let jpegURL = try await jpegRef.downloadURL()

        let pixelWidth = Int(preparedImage.size.width)
        let pixelHeight = Int(preparedImage.size.height)
        let pngArtifact = UploadedBookPageArtifact(
            storagePath: pngPath,
            downloadURL: pngURL.absoluteString,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            bytes: pngData.count,
            checksum: sha256Hex(pngData)
        )
        let jpegArtifact = UploadedBookPageArtifact(
            storagePath: jpegPath,
            downloadURL: jpegURL.absoluteString,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            bytes: jpegData.count,
            checksum: sha256Hex(jpegData)
        )

        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .firebaseStorage,
                operation: .firebaseUpload,
                model: "firebase-storage-book-page-dual",
                statusCode: 200,
                success: true,
                durationMs: 0,
                promptCharacters: 0,
                inputTokens: 0,
                outputTokens: 0,
                inputImageCount: 0,
                outputImageCount: 2,
                uploadedBytes: pngData.count + jpegData.count
            )
        )

        return UploadedBookPageArtifacts(png: pngArtifact, jpeg: jpegArtifact)
    }

    /// Upload the cover PDF for a Kids Book (24×10.25" at 300 DPI).
    /// Path: users/{uid}/bookVersions/{bookId}/cover.pdf
    func uploadBookCoverPDF(_ pdfData: Data, bookId: String) async throws -> (storagePath: String, downloadURL: String) {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw StorageError.notAuthenticated
        }
        return try await uploadBookCoverPDF(pdfData, bookId: bookId, asUserId: userId)
    }

    func uploadBookCoverPDF(_ pdfData: Data, bookId: String, asUserId userId: String) async throws -> (storagePath: String, downloadURL: String) {
        let path = "users/\(userId)/bookVersions/\(bookId)/cover.pdf"
        let ref = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = "application/pdf"

        _ = try await ref.putDataAsync(pdfData, metadata: metadata)
        let downloadURL = try await ref.downloadURL()

        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .firebaseStorage,
                operation: .firebaseUpload,
                model: "firebase-storage-book-cover-pdf",
                statusCode: 200,
                success: true,
                durationMs: 0,
                promptCharacters: 0,
                inputTokens: 0,
                outputTokens: 0,
                inputImageCount: 0,
                outputImageCount: 0,
                uploadedBytes: pdfData.count
            )
        )

        print("✅ Uploaded book cover PDF to Firebase: \(path) (\(pdfData.count) bytes)")
        return (path, downloadURL.absoluteString)
    }

    /// Upload a canonical book PDF artifact for a book version.
    func uploadBookVersionPDF(_ pdfData: Data, bookId: String) async throws -> UploadedBookPdfArtifact {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw StorageError.notAuthenticated
        }

        let path = "users/\(userId)/bookVersions/\(bookId)/book.pdf"
        let ref = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = "application/pdf"

        _ = try await ref.putDataAsync(pdfData, metadata: metadata)
        let downloadURL = try await ref.downloadURL()

        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .firebaseStorage,
                operation: .firebaseUpload,
                model: "firebase-storage-book-version-pdf",
                statusCode: 200,
                success: true,
                durationMs: 0,
                promptCharacters: 0,
                inputTokens: 0,
                outputTokens: 0,
                inputImageCount: 0,
                outputImageCount: 0,
                uploadedBytes: pdfData.count
            )
        )

        return UploadedBookPdfArtifact(
            storagePath: path,
            downloadURL: downloadURL.absoluteString,
            bytes: pdfData.count
        )
    }
    
    // MARK: - Resolve fresh download URLs
    
    /// Returns a newly signed download URL for an object at `storagePath` (e.g. `users/{uid}/bookVersions/{bookId}/pages/page_000.jpg`).
    /// Use when Firestore-cached `imageURL` / `renderedPageURL` tokens have expired.
    func freshDownloadURL(forStoragePath storagePath: String) async throws -> URL {
        let trimmed = storagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StorageError.uploadFailed("Empty storage path")
        }
        let ref = storage.reference(withPath: trimmed)
        return try await ref.downloadURL()
    }
    
    // MARK: - Delete Files
    
    /// Delete a file at the given path
    func deleteFile(at path: String) async throws {
        let ref = storage.reference().child(path)
        try await ref.delete()
        print("✅ Deleted file at: \(path)")
    }

    /// Recursively deletes all files under `users/{uid}/bookVersions/{bookId}/` (including `pages/`, `cover.pdf`, `book.pdf`).
    func deleteBookVersionFolder(bookId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let ref = storage.reference().child("users/\(userId)/bookVersions/\(bookId)")
        await deleteStorageRefRecursively(ref)
    }

    private func deleteStorageRefRecursively(_ ref: StorageReference) async {
        do {
            let list = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<StorageListResult, Error>) in
                ref.listAll { result, error in
                    if let error = error { cont.resume(throwing: error) }
                    else if let result = result { cont.resume(returning: result) }
                    else { cont.resume(throwing: StorageError.uploadFailed("listAll returned no result")) }
                }
            }
            for p in list.prefixes {
                await deleteStorageRefRecursively(p)
            }
            for item in list.items {
                do {
                    try await item.delete()
                } catch {
                    print("⚠️ Storage delete \(item.fullPath): \(error.localizedDescription)")
                }
            }
        } catch {
            // Listing an empty or missing "folder" may return an error; skip noisy logs for not-found.
            let msg = error.localizedDescription.lowercased()
            if !msg.contains("not found") && !msg.contains("not exist") {
                print("⚠️ deleteStorage list \(ref.fullPath): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Error Types
    
    enum StorageError: LocalizedError {
        case notAuthenticated
        case invalidImageData
        case uploadFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You must be signed in to upload files."
            case .invalidImageData:
                return "Could not process image data."
            case .uploadFailed(let message):
                return "Upload failed: \(message)"
            }
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
