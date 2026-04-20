//
//  FirestoreSyncService.swift
//  MemoirAI
//
//  Syncs memories and books to Firebase Firestore for admin visibility
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import UIKit

/// Service for syncing local Core Data to Firebase Firestore
/// This runs alongside CloudKit - CloudKit handles fast local sync,
/// Firebase provides admin access to all user data
final class FirestoreSyncService {
    
    static let shared = FirestoreSyncService()
    
    private let db = Firestore.firestore()
    
    private init() {}

    struct BookRenderFunctionResponse {
        let status: String?
        let pdfURL: String?
        let pdfStoragePath: String?
        let renderDurationMs: Int?
        let pdfBytes: Int?
        let message: String?
    }
    
    private func migrationCompletionKey(for userId: String) -> String {
        "firebase_migration_complete_\(userId)"
    }

    private var bookRenderFunctionURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "BOOK_RENDER_FUNCTION_URL") as? String,
              let url = URL(string: raw),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return url
    }

    /// True when Firestore reports FAILED_PRECONDITION for a missing composite index (common code 9).
    private func isMissingFirestoreCompositeIndexError(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == FirestoreErrorDomain,
              ns.code == FirestoreErrorCode.failedPrecondition.rawValue else {
            return false
        }
        let msg = ns.localizedDescription.lowercased()
        return msg.contains("index") || msg.contains("requires an index")
    }

    /// Fallback: no composite index — fetch recent bookVersions ordered by createdAt only, filter profileId in memory.
    private func fetchLatestBookVersionClientFilter(profileID: UUID, userId: String) async -> BookVersionRecord? {
        let ref = db.collection("users").document(userId).collection("bookVersions")
        do {
            let snapshot = try await ref.order(by: "createdAt", descending: true).limit(to: 80).getDocuments()
            let wanted = profileID.uuidString
            for doc in snapshot.documents {
                guard let record = BookVersionRecord.fromFirestoreData(doc.data()),
                      record.profileId == wanted else { continue }
                return record
            }
            return nil
        } catch {
            print("❌ fetchLatestBookVersionClientFilter failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchBookVersionsClientFilter(profileID: UUID, userId: String) async -> [BookVersionRecord] {
        let ref = db.collection("users").document(userId).collection("bookVersions")
        do {
            let snapshot = try await ref.order(by: "createdAt", descending: true).limit(to: 80).getDocuments()
            let wanted = profileID.uuidString
            return snapshot.documents.compactMap { BookVersionRecord.fromFirestoreData($0.data()) }
                .filter { $0.profileId == wanted }
        } catch {
            print("❌ fetchBookVersionsClientFilter failed: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Memory Sync
    
    /// Sync a memory entry to Firestore
    /// Call this after saving to Core Data
    func syncMemory(_ entry: MemoryEntry, profileName: String? = nil) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot sync memory - user not signed in")
            return
        }
        
        guard let memoryId = entry.id else {
            print("⚠️ Cannot sync memory - no ID")
            return
        }
        
        let memoryRef = db.collection("users").document(userId)
            .collection("memories").document(memoryId.uuidString)
        
        do {
            // Upload audio if available; otherwise remove stale audioURL in Firestore (e.g. after re-record clear).
            var memoryData: [String: Any] = [
                "prompt": entry.prompt ?? "",
                "transcription": entry.text ?? "",
                "createdAt": entry.createdAt ?? Date(),
                "chapter": entry.chapter ?? "",
                "profileID": entry.profileID?.uuidString ?? "",
                "syncedAt": FieldValue.serverTimestamp()
            ]
            
            if let audioData = entry.audioData, !audioData.isEmpty {
                let uploaded = try await StorageService.shared.uploadAudio(audioData, memoryId: memoryId.uuidString)
                memoryData["audioURL"] = uploaded
            } else {
                memoryData["audioURL"] = FieldValue.delete()
            }
            
            // Include profile name for easy identification
            if let profileName = profileName {
                memoryData["profileName"] = profileName
            }
            
            if let characterDetails = entry.characterDetails {
                memoryData["characterDetails"] = characterDetails
            }
            
            // Save to Firestore
            try await memoryRef.setData(memoryData, merge: true)
            print("✅ Synced memory \(memoryId.uuidString) to Firebase")
            
        } catch {
            print("❌ Failed to sync memory to Firebase: \(error)")
        }
    }
    
    /// Update just the transcription for a memory
    func updateMemoryTranscription(memoryId: UUID, transcription: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let memoryRef = db.collection("users").document(userId)
            .collection("memories").document(memoryId.uuidString)
        
        do {
            try await memoryRef.updateData([
                "transcription": transcription,
                "syncedAt": FieldValue.serverTimestamp()
            ])
            print("✅ Updated transcription for memory \(memoryId.uuidString)")
        } catch {
            print("❌ Failed to update transcription: \(error)")
        }
    }
    
    // MARK: - Book Sync
    
    /// Cover generation inputs for print cover (kids + portrait when Gemini is available).
    /// When `headshot` is nil, cover art must not depict people (`generateCoverIllustration` no-humans path).
    struct CoverInputs {
        let headshot: UIImage?
        let profileName: String
        let ethnicity: String?
        let gender: String?
        let memoryThemes: [String]
        let artStyle: ArtStyle
        /// User custom style phrase when `artStyle == .custom`; also forwarded for consistency on other styles if ever set.
        let customArtStyleText: String?
        /// Canonical title — rendered inside AI cover art when using Gemini; also passed to PDF renderer for legacy/native overlay paths.
        let printTitle: String
        /// Back panel marketing copy.
        let backCoverPitch: String
        let coverFontPreset: CoverFontPreset
    }

    /// Sync a generated storybook to Firestore with rendered page artifacts.
    func syncBook(
        _ book: PersistableStorybook,
        bookId: String,
        renderedPageImages: [UIImage]? = nil,
        coverInputs: CoverInputs? = nil
    ) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot sync book - user not signed in")
            return
        }
        
        let bookRef = db.collection("users").document(userId)
            .collection("bookVersions").document(bookId)
        
        do {
            // Build canonical version record first.
            let syncStart = Date()
            let baseRecord = BookVersionRecordFactory.fromPersistable(book, bookVersionId: bookId)
            let isLandscapeTrim = baseRecord.pageWidth > baseRecord.pageHeight
            var coverStoragePath: String?
            var coverURL: String?

            let geminiKey = (Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let canUseGemini = !geminiKey.isEmpty

            // Landscape trim (11×8.5): AI cover (headshot → likeness; no headshot → non-human art). Title is painted in-image.
            if isLandscapeTrim, let inputs = coverInputs, canUseGemini {
                let svc = GeminiImageService(apiKey: geminiKey)
                if let coverArt = try? await svc.generateCoverIllustration(
                    headshot: inputs.headshot,
                    profileName: inputs.profileName,
                    ethnicity: inputs.ethnicity,
                    gender: inputs.gender,
                    memoryThemes: inputs.memoryThemes,
                    artStyle: inputs.artStyle,
                    customStyle: inputs.customArtStyleText,
                    printTitle: inputs.printTitle
                ) {
                    let backCoverArt = try? await svc.generateBackCoverIllustration(
                        frontCoverArt: coverArt,
                        headshot: inputs.headshot,
                        profileName: inputs.profileName,
                        ethnicity: inputs.ethnicity,
                        gender: inputs.gender,
                        memoryThemes: inputs.memoryThemes,
                        artStyle: inputs.artStyle,
                        customStyle: inputs.customArtStyleText
                    )
                    if let coverPDFData = BookCoverRenderer.renderPDF(
                        frontCoverArt: coverArt,
                        backCoverArt: backCoverArt,
                        profileName: inputs.profileName,
                        pageCount: book.pageItems.count,
                        frontTitle: inputs.printTitle,
                        backCoverPitch: inputs.backCoverPitch,
                        fontPreset: inputs.coverFontPreset,
                        useNativeFrontTitleOverlay: false
                    ) {
                        let result = try await StorageService.shared.uploadBookCoverPDF(coverPDFData, bookId: bookId)
                        coverStoragePath = result.storagePath
                        coverURL = result.downloadURL
                        print("✅ Landscape trim cover PDF generated and uploaded")
                    } else {
                        print("⚠️ Landscape cover generation skipped (render failed)")
                    }
                } else {
                    print("⚠️ Landscape cover generation skipped (AI or render failed)")
                }
            }

            // Portrait trim: prefer Gemini + AI title when API key and `coverInputs` are available.
            if !isLandscapeTrim, coverStoragePath == nil, let inputs = coverInputs, canUseGemini {
                let svc = GeminiImageService(apiKey: geminiKey)
                if let coverArt = try? await svc.generateCoverIllustration(
                    headshot: inputs.headshot,
                    profileName: inputs.profileName,
                    ethnicity: inputs.ethnicity,
                    gender: inputs.gender,
                    memoryThemes: inputs.memoryThemes,
                    artStyle: inputs.artStyle,
                    customStyle: inputs.customArtStyleText,
                    printTitle: inputs.printTitle
                ) {
                    let backCoverArt = try? await svc.generateBackCoverIllustration(
                        frontCoverArt: coverArt,
                        headshot: inputs.headshot,
                        profileName: inputs.profileName,
                        ethnicity: inputs.ethnicity,
                        gender: inputs.gender,
                        memoryThemes: inputs.memoryThemes,
                        artStyle: inputs.artStyle,
                        customStyle: inputs.customArtStyleText
                    )
                    if let coverPDFData = BookCoverRenderer.renderPortraitPDF(
                        frontCoverArt: coverArt,
                        backCoverArt: backCoverArt,
                        profileName: inputs.profileName,
                        pageCount: book.pageItems.count,
                        frontTitle: inputs.printTitle,
                        backCoverPitch: inputs.backCoverPitch,
                        fontPreset: inputs.coverFontPreset,
                        useNativeFrontTitleOverlay: false
                    ) {
                        let result = try await StorageService.shared.uploadBookCoverPDF(coverPDFData, bookId: bookId)
                        coverStoragePath = result.storagePath
                        coverURL = result.downloadURL
                        print("✅ Portrait Book AI cover PDF generated and uploaded")
                    } else {
                        print("⚠️ Portrait AI cover render failed; may fall back to first illustration")
                    }
                } else {
                    print("⚠️ Portrait AI cover generation skipped (AI or render failed); may fall back to first illustration")
                }
            }

            // Portrait fallback: interior illustration as front art — native title overlay remains for readability (no AI title).
            if !isLandscapeTrim, coverStoragePath == nil, let renderedPageImages {
                let firstIllustration: UIImage? = {
                    for (index, page) in baseRecord.pages.enumerated() {
                        if page.type == "illustration", index < renderedPageImages.count {
                            return renderedPageImages[index]
                        }
                    }
                    return nil
                }()
                let trimmedDisplay = book.bookDisplayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let firstPageTitle = book.pageItems.first?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolvedTitle: String? = {
                    if !trimmedDisplay.isEmpty { return trimmedDisplay }
                    return firstPageTitle.isEmpty ? nil : firstPageTitle
                }()
                let artStyle = ArtStyle(rawValue: book.artStyle) ?? .realistic
                let policy = CoverCopyPolicy(artStyle: artStyle, profileDisplayName: resolvedTitle ?? "Memoir")
                let trimmedPitch = book.backCoverPitch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let pitch = trimmedPitch.isEmpty
                    ? policy.fallbackBackCoverPitch(bookTitle: resolvedTitle ?? "Memoir")
                    : trimmedPitch
                let fontPreset = CoverFontPreset(rawValue: book.coverFontPreset ?? "") ?? policy.coverFontPreset()

                if let coverArt = firstIllustration {
                    let memoryThemesForBack = book.pageItems.prefix(8).compactMap { item in
                        item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.filter { !$0.isEmpty }
                    var backCoverArt: UIImage? = nil
                    if canUseGemini {
                        let svc = GeminiImageService(apiKey: geminiKey)
                        backCoverArt = try? await svc.generateBackCoverIllustration(
                            frontCoverArt: coverArt,
                            headshot: nil,
                            profileName: resolvedTitle ?? "Memoir",
                            ethnicity: nil,
                            gender: nil,
                            memoryThemes: memoryThemesForBack,
                            artStyle: artStyle
                        )
                    }
                    if let coverPDFData = BookCoverRenderer.renderPortraitPDF(
                        frontCoverArt: coverArt,
                        backCoverArt: backCoverArt,
                        profileName: resolvedTitle ?? "Memoir",
                        pageCount: book.pageItems.count,
                        frontTitle: resolvedTitle,
                        backCoverPitch: pitch,
                        fontPreset: fontPreset,
                        useNativeFrontTitleOverlay: false
                    ) {
                        let result = try await StorageService.shared.uploadBookCoverPDF(coverPDFData, bookId: bookId)
                        coverStoragePath = result.storagePath
                        coverURL = result.downloadURL
                        print("✅ Portrait Book cover PDF generated and uploaded (illustration fallback; no native front title overlay)")
                    } else {
                        print("⚠️ Portrait Book cover render failed (illustration fallback path)")
                    }
                } else {
                    print("⚠️ Portrait Book cover generation skipped (no illustration found)")
                }
            }

            var uploadedPages: [BookVersionPageRecord] = []
            var totalPngBytes = 0
            
            for (index, page) in baseRecord.pages.enumerated() {
                var updatedPage = page

                let renderedImage: UIImage = {
                    // 1. Prefer on-device rendered images (text + illustration) for full visual parity
                    if let renderedPageImages, index < renderedPageImages.count {
                        return renderedPageImages[index]
                    }
                    // 2. Fallback: use persisted image data for illustrations (e.g. legacy migration)
                    if index < book.pageItems.count,
                       let imageData = book.pageItems[index].imageData,
                       let image = UIImage(data: imageData) {
                        return image
                    }
                    // 3. Fallback: render text pages from content (required for Cloud Function; never skip)
                    if page.type == "textPage" {
                        let text = page.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return fallbackTextPageImage(
                            text: text.isEmpty ? " " : text,
                            title: page.title,
                            subtitle: page.subtitle,
                            widthPt: CGFloat(baseRecord.pageWidth),
                            heightPt: CGFloat(baseRecord.pageHeight)
                        )
                    }
                    // 4. Last resort: blank placeholder (ensures every page has an artifact)
                    print("⚠️ No image for page \(index) (type=\(page.type)); using blank placeholder")
                    return fallbackTextPageImage(
                        text: " ",
                        title: nil,
                        subtitle: nil,
                        widthPt: CGFloat(baseRecord.pageWidth),
                        heightPt: CGFloat(baseRecord.pageHeight)
                    )
                }()

                let artifacts = try await StorageService.shared.uploadRenderedBookPageArtifacts(
                    renderedImage,
                    bookId: bookId,
                    pageIndex: index,
                    isKidsBook: baseRecord.pageWidth > baseRecord.pageHeight
                )
                totalPngBytes += artifacts.png.bytes

                updatedPage = BookVersionPageRecord(
                    pageIndex: page.pageIndex,
                    type: page.type,
                    memoryId: page.memoryId,
                    memoryCreatedAt: page.memoryCreatedAt,
                    title: page.title,
                    subtitle: page.subtitle,
                    textContent: page.textContent,
                    imageStoragePath: artifacts.jpeg.storagePath,
                    imageURL: artifacts.jpeg.downloadURL,
                    renderedPageStoragePath: artifacts.png.storagePath,
                    renderedPageURL: artifacts.png.downloadURL,
                    renderedPageFormat: "png",
                    renderedPixelWidth: artifacts.png.pixelWidth,
                    renderedPixelHeight: artifacts.png.pixelHeight,
                    renderedChecksum: artifacts.png.checksum,
                    renderedBytes: artifacts.png.bytes,
                    createdAt: page.createdAt
                )
                uploadedPages.append(updatedPage)
            }
            
            let canonicalRecord = BookVersionRecord(
                bookVersionId: baseRecord.bookVersionId,
                profileId: baseRecord.profileId,
                createdAt: baseRecord.createdAt,
                memoryOrder: baseRecord.memoryOrder,
                pageCount: uploadedPages.count,
                artStyle: baseRecord.artStyle,
                orientation: baseRecord.orientation,
                pageWidth: baseRecord.pageWidth,
                pageHeight: baseRecord.pageHeight,
                trimSizeInches: baseRecord.trimSizeInches,
                layoutVersion: baseRecord.layoutVersion,
                printTitle: baseRecord.printTitle,
                backCoverPitch: baseRecord.backCoverPitch,
                coverFontPreset: baseRecord.coverFontPreset,
                pdfStoragePath: nil,
                pdfURL: nil,
                pdfPageCount: nil,
                coverStoragePath: coverStoragePath,
                coverURL: coverURL,
                syncedAt: Date(),
                renderStatus: BookRenderStatus.pending.rawValue,
                renderedAt: nil,
                renderError: nil,
                renderAttemptCount: 0,
                renderDurationMs: Int(Date().timeIntervalSince(syncStart) * 1000),
                totalPngBytes: totalPngBytes,
                pdfBytes: nil,
                source: baseRecord.source,
                pages: uploadedPages
            )
            
            try await bookRef.setData(canonicalRecord.toFirestoreData())
            
            // Legacy metadata mirror for existing dashboards/query paths.
            let legacyBookRef = db.collection("users").document(userId)
                .collection("books").document(bookId)
            try await legacyBookRef.setData([
                "profileID": book.profileID.uuidString,
                "artStyle": book.artStyle,
                "createdAt": book.createdAt,
                "pageCount": uploadedPages.count,
                "bookVersionRef": bookId,
                "syncedAt": FieldValue.serverTimestamp()
            ], merge: true)
            
            // Fire-and-forget trigger to package server-side PDF from stored PNG pages.
            _ = await invokeBookRenderFunction(bookVersionId: bookId)
            
            print("✅ Synced canonical book version \(bookId) to Firebase with \(uploadedPages.count) pages and \(totalPngBytes) PNG bytes (layout: \(Int(baseRecord.pageWidth))x\(Int(baseRecord.pageHeight))pt)")
            
        } catch {
            print("❌ Failed to sync book to Firebase: \(error)")
        }
    }

    private func fallbackTextPageImage(
        text: String,
        title: String?,
        subtitle: String?,
        widthPt: CGFloat,
        heightPt: CGFloat
    ) -> UIImage {
        let size = CGSize(width: max(widthPt, 1), height: max(heightPt, 1))
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            UIColor(red: 250.0 / 255.0, green: 248.0 / 255.0, blue: 243.0 / 255.0, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            var y: CGFloat = size.height * 0.12
            let margin = size.width * 0.1
            let drawWidth = size.width - (margin * 2)

            if let title, !title.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: size.height * 0.045, weight: .semibold),
                    .foregroundColor: UIColor.black
                ]
                let rect = CGRect(x: margin, y: y, width: drawWidth, height: size.height * 0.12)
                title.draw(in: rect, withAttributes: attrs)
                y += size.height * 0.085
            }

            if let subtitle, !subtitle.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: size.height * 0.028, weight: .regular),
                    .foregroundColor: UIColor.darkGray
                ]
                let rect = CGRect(x: margin, y: y, width: drawWidth, height: size.height * 0.08)
                subtitle.draw(in: rect, withAttributes: attrs)
                y += size.height * 0.075
            }

            let bodyStyle = NSMutableParagraphStyle()
            bodyStyle.lineBreakMode = .byWordWrapping
            bodyStyle.alignment = .left
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.height * 0.028, weight: .regular),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]

            let bodyRect = CGRect(
                x: margin,
                y: y,
                width: drawWidth,
                height: size.height - y - (size.height * 0.08)
            )
            (text as NSString).draw(in: bodyRect, withAttributes: bodyAttrs)
        }
    }
    
    /// Lightweight book sync without images (faster)
    func syncBookMetadata(_ book: PersistableStorybook, bookId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let bookRef = db.collection("users").document(userId)
            .collection("bookVersions").document(bookId)
        
        do {
            let layout = BookVersionLayoutFactory.layout(forArtStyle: book.artStyle)
            let printSpec = BookPrintSpec.forArtStyle(book.artStyle)
            let memoryOrder = book.pageItems.compactMap { BookVersionRecordFactory.memoryId(from: $0.url) }
            let bookData: [String: Any] = [
                "bookVersionId": bookId,
                "profileId": book.profileID.uuidString,
                "artStyle": book.artStyle,
                "orientation": layout.orientation,
                "pageWidth": layout.pageWidth,
                "pageHeight": layout.pageHeight,
                "trimSizeInches": printSpec.trimSizeInches,
                "layoutVersion": printSpec.layoutVersion,
                "renderStatus": BookRenderStatus.pending.rawValue,
                "renderAttemptCount": 0,
                "memoryOrder": memoryOrder,
                "pageCount": book.pageItems.count,
                "source": BookVersionSource.storyGeneration.rawValue,
                "createdAt": Timestamp(date: book.createdAt),
                "syncedAt": FieldValue.serverTimestamp()
            ]
            
            try await bookRef.setData(bookData, merge: true)
            print("✅ Synced book metadata for \(bookId)")
        } catch {
            print("❌ Failed to sync book metadata: \(error)")
        }
    }
    
    /// Fetch all canonical book versions for a profile, newest first.
    func fetchBookVersions(profileID: UUID) async -> [BookVersionRecord] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        // Avoid composite-index requirement by using createdAt ordering only and profile client filter.
        return await fetchBookVersionsClientFilter(profileID: profileID, userId: userId)
    }
    
    /// Fetch latest canonical book version for a profile.
    func fetchLatestBookVersion(profileID: UUID) async -> BookVersionRecord? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        // Avoid composite-index requirement by using createdAt ordering only and profile client filter.
        return await fetchLatestBookVersionClientFilter(profileID: profileID, userId: userId)
    }
    
    /// Fetch one canonical book version by exact ID (admin/order retrieval path).
    func fetchBookVersion(bookVersionId: String) async -> BookVersionRecord? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        
        let docRef = db.collection("users").document(userId)
            .collection("bookVersions")
            .document(bookVersionId)
        
        do {
            let snapshot = try await docRef.getDocument()
            guard let data = snapshot.data() else { return nil }
            return BookVersionRecord.fromFirestoreData(data)
        } catch {
            print("❌ Failed to fetch book version \(bookVersionId): \(error)")
            return nil
        }
    }

    /// Return canonical PDF URL if already rendered, or trigger cloud packaging and poll until ready.
    func fetchOrGenerateBookPDF(
        bookVersionId: String,
        forceRegenerate: Bool = false,
        timeoutSeconds: Int = 30
    ) async -> String? {
        if !forceRegenerate,
           let current = await fetchBookVersion(bookVersionId: bookVersionId),
           current.renderStatus == BookRenderStatus.rendered.rawValue,
           let pdfURL = current.pdfURL {
            return pdfURL
        }

        let response = await invokeBookRenderFunction(bookVersionId: bookVersionId, forceRegenerate: forceRegenerate)
        if response?.status == BookRenderStatus.rendered.rawValue, let ready = response?.pdfURL {
            return ready
        }

        let pollIntervalNs: UInt64 = 2_000_000_000
        let maxPolls = max(1, timeoutSeconds / 2)
        for _ in 0..<maxPolls {
            try? await Task.sleep(nanoseconds: pollIntervalNs)
            if let updated = await fetchBookVersion(bookVersionId: bookVersionId),
               updated.renderStatus == BookRenderStatus.rendered.rawValue,
               let pdfURL = updated.pdfURL {
                return pdfURL
            }
        }
        return nil
    }

    /// Triggers server-side PDF packaging from already uploaded PNG pages.
    func invokeBookRenderFunction(
        bookVersionId: String,
        forceRegenerate: Bool = false
    ) async -> BookRenderFunctionResponse? {
        guard let functionURL = bookRenderFunctionURL else {
            print("⚠️ BOOK_RENDER_FUNCTION_URL missing in Info.plist, skipping cloud PDF trigger")
            return nil
        }
        guard let user = Auth.auth().currentUser else {
            print("⚠️ Cannot trigger render - user not signed in")
            return nil
        }

        do {
            let idToken = try await user.getIDToken()
            var request = URLRequest(url: functionURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "bookVersionId": bookVersionId,
                "forceRegenerate": forceRegenerate
            ])
            request.timeoutInterval = 300
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 300
            config.timeoutIntervalForResource = 300
            let session = URLSession(configuration: config)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return nil
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("❌ Render function failed (\(http.statusCode)): \(body)")
                return nil
            }

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            return BookRenderFunctionResponse(
                status: json?["status"] as? String,
                pdfURL: json?["pdfURL"] as? String,
                pdfStoragePath: json?["pdfStoragePath"] as? String,
                renderDurationMs: json?["renderDurationMs"] as? Int,
                pdfBytes: json?["pdfBytes"] as? Int,
                message: json?["message"] as? String
            )
        } catch {
            print("❌ Failed invoking render function: \(error.localizedDescription)")
            return nil
        }
    }

    /// Incremental artifact backfill for legacy versions missing rendered page PNGs.
    func backfillBookVersionArtifacts(profileID: UUID? = nil, limit: Int = 20) async -> Int {
        guard let userId = Auth.auth().currentUser?.uid else { return 0 }

        var query: Query = db.collection("users").document(userId)
            .collection("bookVersions")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        if let profileID {
            query = query.whereField("profileId", isEqualTo: profileID.uuidString)
        }

        do {
            let snapshot = try await query.getDocuments()
            let candidates = snapshot.documents.compactMap { BookVersionRecord.fromFirestoreData($0.data()) }
                .filter { record in
                    record.pages.contains(where: { $0.renderedPageURL == nil }) ||
                    record.renderStatus != BookRenderStatus.rendered.rawValue ||
                    record.pdfURL == nil
                }

            var updated = 0
            for record in candidates {
                if await invokeBookRenderFunction(bookVersionId: record.bookVersionId) != nil {
                    updated += 1
                }
            }
            return updated
        } catch {
            if let profileID, isMissingFirestoreCompositeIndexError(error) {
                print("⚠️ backfillBookVersionArtifacts index missing; retrying with client-side profile filter")
                return await backfillBookVersionArtifactsClientFilter(profileID: profileID, userId: userId, limit: limit)
            }
            print("❌ Failed backfill query: \(error.localizedDescription)")
            return 0
        }
    }

    private func backfillBookVersionArtifactsClientFilter(profileID: UUID, userId: String, limit: Int) async -> Int {
        let ref = db.collection("users").document(userId).collection("bookVersions")
        do {
            let snapshot = try await ref.order(by: "createdAt", descending: true).limit(to: max(80, limit * 4)).getDocuments()
            let wanted = profileID.uuidString
            let candidates = snapshot.documents.compactMap { BookVersionRecord.fromFirestoreData($0.data()) }
                .filter { $0.profileId == wanted }
                .prefix(limit * 2)
            var updated = 0
            for record in candidates {
                if record.pages.contains(where: { $0.renderedPageURL == nil }) ||
                    record.renderStatus != BookRenderStatus.rendered.rawValue ||
                    record.pdfURL == nil {
                    if await invokeBookRenderFunction(bookVersionId: record.bookVersionId) != nil {
                        updated += 1
                    }
                }
            }
            return updated
        } catch {
            print("❌ backfillBookVersionArtifactsClientFilter failed: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Cover Design Backfill

    /// One-time backfill for existing books: regenerate cover PDFs with upgraded prompt/composition logic.
    func backfillCoverDesigns(profileID: UUID? = nil, limit: Int = 20) async -> Int {
        guard let userId = Auth.auth().currentUser?.uid else { return 0 }

        var query: Query = db.collection("users").document(userId)
            .collection("bookVersions")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        if let profileID {
            query = query.whereField("profileId", isEqualTo: profileID.uuidString)
        }

        do {
            let snapshot = try await query.getDocuments()
            let records = snapshot.documents.compactMap { BookVersionRecord.fromFirestoreData($0.data()) }
            var updated = 0
            for record in records {
                if await regenerateCoverDesign(for: record, userId: userId) {
                    updated += 1
                }
            }
            return updated
        } catch {
            if let profileID, isMissingFirestoreCompositeIndexError(error) {
                return await backfillCoverDesignsClientFilter(profileID: profileID, userId: userId, limit: limit)
            }
            print("❌ backfillCoverDesigns failed: \(error.localizedDescription)")
            return 0
        }
    }

    private func backfillCoverDesignsClientFilter(profileID: UUID, userId: String, limit: Int) async -> Int {
        let ref = db.collection("users").document(userId).collection("bookVersions")
        do {
            let snapshot = try await ref.order(by: "createdAt", descending: true).limit(to: max(80, limit * 4)).getDocuments()
            let wanted = profileID.uuidString
            let records = snapshot.documents.compactMap { BookVersionRecord.fromFirestoreData($0.data()) }
                .filter { $0.profileId == wanted }
                .prefix(limit)
            var updated = 0
            for record in records {
                if await regenerateCoverDesign(for: record, userId: userId) {
                    updated += 1
                }
            }
            return updated
        } catch {
            print("❌ backfillCoverDesignsClientFilter failed: \(error.localizedDescription)")
            return 0
        }
    }

    /// If this book version exists in Firestore but has no `coverURL` yet, run the Gemini → PDF → Storage path used by cover backfill.
    /// Returns `true` without regenerating when a cover is already present (safe if initial sync is still racing).
    func ensureCoverDesignExistsIfMissing(bookVersionId: String) async -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }
        let docRef = db.collection("users").document(userId).collection("bookVersions").document(bookVersionId)
        do {
            let snapshot = try await docRef.getDocument()
            guard snapshot.exists, let data = snapshot.data(), let record = BookVersionRecord.fromFirestoreData(data) else {
                return false
            }
            let trimmed = record.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return true
            }
            return await regenerateCoverDesign(for: record, userId: userId)
        } catch {
            print("ensureCoverDesignExistsIfMissing failed: \(error.localizedDescription)")
            return false
        }
    }

    private func regenerateCoverDesign(for record: BookVersionRecord, userId: String) async -> Bool {
        guard record.pageCount > 0 else { return false }

        let title = record.printTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (record.printTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Memoir")
            : ((record.pages.first?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? (record.pages.first?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Memoir")
                : "Memoir")

        let artStyle = ArtStyle(rawValue: record.artStyle) ?? .realistic
        let policy = CoverCopyPolicy(artStyle: artStyle, profileDisplayName: title)
        let pitch = record.backCoverPitch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (record.backCoverPitch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : policy.fallbackBackCoverPitch(bookTitle: title)
        let fontPreset = CoverFontPreset(rawValue: record.coverFontPreset ?? "") ?? policy.coverFontPreset()
        let themes = rankedCoverSignals(from: record.pages, maxCount: 5)

        guard let geminiKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
              !geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ regenerateCoverDesign skipped — no GEMINI_API_KEY (no-people AI title covers require Gemini)")
            return false
        }
        let svc = GeminiImageService(apiKey: geminiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let frontCoverArt = try? await svc.generateCoverIllustration(
            headshot: nil,
            profileName: title,
            ethnicity: nil,
            gender: nil,
            memoryThemes: themes,
            artStyle: artStyle,
            customStyle: nil,
            printTitle: title
        ) else {
            print("⚠️ regenerateCoverDesign failed — Gemini cover generation returned nil")
            return false
        }

        let backCoverArt = try? await svc.generateBackCoverIllustration(
            frontCoverArt: frontCoverArt,
            headshot: nil,
            profileName: title,
            ethnicity: nil,
            gender: nil,
            memoryThemes: themes,
            artStyle: artStyle,
            customStyle: nil
        )

        let pdfData: Data?
        if record.pageWidth > record.pageHeight {
            pdfData = BookCoverRenderer.renderPDF(
                frontCoverArt: frontCoverArt,
                backCoverArt: backCoverArt,
                profileName: title,
                pageCount: record.pageCount,
                frontTitle: title,
                backCoverPitch: pitch,
                fontPreset: fontPreset,
                useNativeFrontTitleOverlay: false
            )
        } else {
            pdfData = BookCoverRenderer.renderPortraitPDF(
                frontCoverArt: frontCoverArt,
                backCoverArt: backCoverArt,
                profileName: title,
                pageCount: record.pageCount,
                frontTitle: title,
                backCoverPitch: pitch,
                fontPreset: fontPreset,
                useNativeFrontTitleOverlay: false
            )
        }

        guard let pdfData else { return false }
        do {
            let uploaded = try await StorageService.shared.uploadBookCoverPDF(pdfData, bookId: record.bookVersionId)
            let docRef = db.collection("users").document(userId).collection("bookVersions").document(record.bookVersionId)
            try await docRef.setData([
                "coverStoragePath": uploaded.storagePath,
                "coverURL": uploaded.downloadURL,
                "syncedAt": FieldValue.serverTimestamp()
            ], merge: true)
            return true
        } catch {
            print("❌ regenerateCoverDesign failed for \(record.bookVersionId): \(error.localizedDescription)")
            return false
        }
    }

    private static let coverSignalStopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "into", "about", "have", "has", "had",
        "were", "was", "are", "our", "your", "their", "them", "they", "then", "than", "when", "where",
        "what", "which", "while", "after", "before", "over", "under", "through", "around", "very",
        "just", "really", "also", "story", "memory", "memoir", "page"
    ]

    private func rankedCoverSignals(from pages: [BookVersionPageRecord], maxCount: Int) -> [String] {
        struct Signal {
            var score: Int
            var recency: Int
            var display: String
        }
        var titleStats: [String: Signal] = [:]
        var tokenStats: [String: Signal] = [:]
        for (index, page) in pages.sorted(by: { $0.pageIndex < $1.pageIndex }).enumerated() {
            if let title = page.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                let key = title.lowercased()
                if var existing = titleStats[key] {
                    existing.score += 3
                    existing.recency = max(existing.recency, index)
                    titleStats[key] = existing
                } else {
                    titleStats[key] = Signal(score: 3, recency: index, display: title)
                }
            }
            if let text = page.textContent {
                for token in coverKeywordTokens(from: text) {
                    if var existing = tokenStats[token] {
                        existing.score += 1
                        existing.recency = max(existing.recency, index)
                        tokenStats[token] = existing
                    } else {
                        tokenStats[token] = Signal(score: 1, recency: index, display: token.capitalized)
                    }
                }
            }
        }

        let sortedTitles = titleStats.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.recency != $1.recency { return $0.recency > $1.recency }
            return $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending
        }
        let sortedTokens = tokenStats.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.recency != $1.recency { return $0.recency > $1.recency }
            return $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending
        }

        var selected: [String] = []
        var seen = Set<String>()
        for stat in sortedTitles {
            let key = stat.display.lowercased()
            if seen.insert(key).inserted { selected.append(stat.display) }
            if selected.count >= maxCount { return selected }
        }
        for stat in sortedTokens where stat.score >= 2 {
            let key = stat.display.lowercased()
            if seen.insert(key).inserted { selected.append(stat.display) }
            if selected.count >= maxCount { break }
        }
        return selected
    }

    private func coverKeywordTokens(from text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !Self.coverSignalStopWords.contains($0) }
    }
    
    // MARK: - Batch Migration
    
    /// Migrate all existing memories to Firebase (one-time operation)
    func migrateExistingMemories(_ memories: [MemoryEntry]) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot migrate - user not signed in")
            return
        }
        
        print("📤 Starting migration of \(memories.count) memories to Firebase...")
        
        for (index, memory) in memories.enumerated() {
            await syncMemory(memory)
            print("📤 Migrated \(index + 1)/\(memories.count) memories")
        }
        
        // Mark migration as complete
        let key = migrationCompletionKey(for: userId)
        UserDefaults.standard.set(true, forKey: key)
        print("✅ Migration complete for \(userId) using key: \(key)")
    }
    
    /// Check if migration has been completed
    var isMigrationComplete: Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }
        let key = migrationCompletionKey(for: userId)
        return UserDefaults.standard.bool(forKey: key)
    }
    
    // MARK: - Profile Sync
    
    /// Sync user profile to Firebase (updates user document with profile info)
    func syncProfile(_ profile: Profile) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Update user document with profile info (for easy identification)
        let userRef = db.collection("users").document(userId)
        
        do {
            var userData: [String: Any] = [
                "profileName": profile.name,
                "profileID": profile.id.uuidString,
                "lastActiveAt": FieldValue.serverTimestamp()
            ]
            
            if let birthdate = profile.birthdate {
                userData["profileBirthdate"] = birthdate
            }
            
            try await userRef.setData(userData, merge: true)
            print("✅ Synced profile info to user document: \(profile.name)")
            
            // Also save to profiles subcollection for history
            let profileRef = userRef.collection("profiles").document(profile.id.uuidString)
            
            var profileData: [String: Any] = [
                "name": profile.name,
                "syncedAt": FieldValue.serverTimestamp()
            ]
            
            if let birthdate = profile.birthdate {
                profileData["birthdate"] = birthdate
            }
            
            try await profileRef.setData(profileData, merge: true)
        } catch {
            print("❌ Failed to sync profile: \(error)")
        }
    }
    
    /// Sync profile info along with memory (convenience method)
    func syncMemoryWithProfile(_ entry: MemoryEntry, profile: Profile) async {
        // First sync the profile info to user document
        await syncProfile(profile)
        
        // Then sync the memory
        await syncMemory(entry)
    }
    
    // MARK: - Delete Operations
    
    /// Delete a memory from Firebase
    func deleteMemory(memoryId: UUID) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let memoryRef = db.collection("users").document(userId)
            .collection("memories").document(memoryId.uuidString)
        
        do {
            try await memoryRef.delete()
            print("✅ Deleted memory \(memoryId.uuidString) from Firebase")
        } catch {
            print("❌ Failed to delete memory: \(error)")
        }
    }
}

// MARK: - Convenience Extension for Background Sync

extension FirestoreSyncService {
    
    /// Queue a memory sync in the background (fire and forget)
    func queueMemorySync(_ entry: MemoryEntry, profileName: String? = nil) {
        Task {
            await syncMemory(entry, profileName: profileName)
        }
    }
    
    /// Queue a memory sync with profile info
    func queueMemorySyncWithProfile(_ entry: MemoryEntry, profile: Profile) {
        Task {
            // Sync profile to user document first
            await syncProfile(profile)
            // Then sync memory with profile name
            await syncMemory(entry, profileName: profile.name)
        }
    }
    
    /// Queue a book sync in the background.
    /// Pass `coverInputs` so Gemini can render the flat `cover.pdf` (AI title in-image; headshot drives likeness, or non-human art when headshot is nil).
    func queueBookSync(
        _ book: PersistableStorybook,
        bookId: String,
        renderedPageImages: [UIImage]? = nil,
        coverInputs: FirestoreSyncService.CoverInputs? = nil
    ) {
        Task {
            await syncBook(
                book,
                bookId: bookId,
                renderedPageImages: renderedPageImages,
                coverInputs: coverInputs
            )
        }
    }
}
