import Foundation
import UIKit
import FirebaseFirestore

struct BookPrintSpec {
    static let layoutVersion = 1

    let widthPt: CGFloat
    let heightPt: CGFloat
    let orientation: String
    let trimSizeInches: String
    let layoutVersion: Int

    var aspectRatio: CGFloat {
        guard heightPt > 0 else { return 1.0 }
        return widthPt / heightPt
    }

    static let kidsLandscape = BookPrintSpec(
        widthPt: 11.0 * 72.0,
        heightPt: 8.5 * 72.0,
        orientation: "landscape",
        trimSizeInches: "11x8.5",
        layoutVersion: BookPrintSpec.layoutVersion
    )

    static let standardPortrait = BookPrintSpec(
        widthPt: 8.5 * 72.0,
        heightPt: 11.0 * 72.0,
        orientation: "portrait",
        trimSizeInches: "8.5x11",
        layoutVersion: BookPrintSpec.layoutVersion
    )

    static func forArtStyle(_ artStyle: String) -> BookPrintSpec {
        artStyle.lowercased().contains("kid") ? .kidsLandscape : .standardPortrait
    }
}

enum BookVersionSource: String, Codable {
    case storyGeneration = "story_generation"
    case localMigration = "local_migration"
}

enum BookRenderStatus: String, Codable {
    case pending
    case rendered
    case failed
}

struct BookVersionPageRecord: Codable, Identifiable {
    let pageIndex: Int
    let type: String
    let memoryId: String?
    let memoryCreatedAt: Date?
    let title: String?
    let subtitle: String?
    let textContent: String?
    let imageStoragePath: String?
    let imageURL: String?
    let renderedPageStoragePath: String?
    let renderedPageURL: String?
    let renderedPageFormat: String?
    let renderedPixelWidth: Int?
    let renderedPixelHeight: Int?
    let renderedChecksum: String?
    let renderedBytes: Int?
    let createdAt: Date

    var id: String { "page_\(pageIndex)" }

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "pageIndex": pageIndex,
            "type": type,
            "createdAt": Timestamp(date: createdAt)
        ]
        if let memoryId { data["memoryId"] = memoryId }
        if let memoryCreatedAt { data["memoryCreatedAt"] = Timestamp(date: memoryCreatedAt) }
        if let title { data["title"] = title }
        if let subtitle { data["subtitle"] = subtitle }
        if let textContent { data["textContent"] = textContent }
        if let imageStoragePath { data["imageStoragePath"] = imageStoragePath }
        if let imageURL { data["imageURL"] = imageURL }
        if let renderedPageStoragePath { data["renderedPageStoragePath"] = renderedPageStoragePath }
        if let renderedPageURL { data["renderedPageURL"] = renderedPageURL }
        if let renderedPageFormat { data["renderedPageFormat"] = renderedPageFormat }
        if let renderedPixelWidth { data["renderedPixelWidth"] = renderedPixelWidth }
        if let renderedPixelHeight { data["renderedPixelHeight"] = renderedPixelHeight }
        if let renderedChecksum { data["renderedChecksum"] = renderedChecksum }
        if let renderedBytes { data["renderedBytes"] = renderedBytes }
        return data
    }

    static func fromFirestoreData(_ data: [String: Any]) -> BookVersionPageRecord? {
        guard let pageIndex = data["pageIndex"] as? Int,
              let type = data["type"] as? String else {
            return nil
        }

        let memoryCreatedAt = (data["memoryCreatedAt"] as? Timestamp)?.dateValue()
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()

        return BookVersionPageRecord(
            pageIndex: pageIndex,
            type: type,
            memoryId: data["memoryId"] as? String,
            memoryCreatedAt: memoryCreatedAt,
            title: data["title"] as? String,
            subtitle: data["subtitle"] as? String,
            textContent: data["textContent"] as? String,
            imageStoragePath: data["imageStoragePath"] as? String,
            imageURL: data["imageURL"] as? String,
            renderedPageStoragePath: data["renderedPageStoragePath"] as? String,
            renderedPageURL: data["renderedPageURL"] as? String,
            renderedPageFormat: data["renderedPageFormat"] as? String,
            renderedPixelWidth: data["renderedPixelWidth"] as? Int,
            renderedPixelHeight: data["renderedPixelHeight"] as? Int,
            renderedChecksum: data["renderedChecksum"] as? String,
            renderedBytes: data["renderedBytes"] as? Int,
            createdAt: createdAt
        )
    }
}

struct BookVersionRecord: Codable, Identifiable {
    let bookVersionId: String
    let profileId: String
    let createdAt: Date
    let memoryOrder: [String]
    let pageCount: Int
    let artStyle: String
    let orientation: String
    let pageWidth: Double
    let pageHeight: Double
    let trimSizeInches: String
    let layoutVersion: Int
    /// User-facing / Lulu line-item title (editable); falls back to first page title when absent.
    let printTitle: String?
    /// Marketing copy rendered on the physical back cover (casewrap).
    let backCoverPitch: String?
    /// Font family preset for cover typography (`CoverFontPreset.rawValue`).
    let coverFontPreset: String?
    let pdfStoragePath: String?
    let pdfURL: String?
    let pdfPageCount: Int?
    let coverStoragePath: String?
    let coverURL: String?
    /// Bumped on each cover bytes write (upload / regenerate / merge) so thumbnail cache stays aligned without overloading `syncedAt`.
    let coverArtRevision: Int?
    /// Server/client timestamp of last Firestore write (used to bust cover PDF thumbnail cache when the file is overwritten at the same URL).
    let syncedAt: Date?
    let renderStatus: String
    let renderedAt: Date?
    let renderError: String?
    let renderAttemptCount: Int?
    let renderDurationMs: Int?
    let totalPngBytes: Int?
    let pdfBytes: Int?
    let source: String
    let pages: [BookVersionPageRecord]

    var id: String { bookVersionId }

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "bookVersionId": bookVersionId,
            "profileId": profileId,
            "createdAt": Timestamp(date: createdAt),
            "memoryOrder": memoryOrder,
            "pageCount": pageCount,
            "artStyle": artStyle,
            "orientation": orientation,
            "pageWidth": pageWidth,
            "pageHeight": pageHeight,
            "trimSizeInches": trimSizeInches,
            "layoutVersion": layoutVersion,
            "renderStatus": renderStatus,
            "source": source,
            "pages": pages.map { $0.toFirestoreData() },
            "syncedAt": FieldValue.serverTimestamp()
        ]
        if let pdfStoragePath { data["pdfStoragePath"] = pdfStoragePath }
        if let pdfURL { data["pdfURL"] = pdfURL }
        if let pdfPageCount { data["pdfPageCount"] = pdfPageCount }
        if let coverStoragePath { data["coverStoragePath"] = coverStoragePath }
        if let coverURL { data["coverURL"] = coverURL }
        if let coverArtRevision { data["coverArtRevision"] = coverArtRevision }
        if let renderedAt { data["renderedAt"] = Timestamp(date: renderedAt) }
        if let renderError { data["renderError"] = renderError }
        if let renderAttemptCount { data["renderAttemptCount"] = renderAttemptCount }
        if let renderDurationMs { data["renderDurationMs"] = renderDurationMs }
        if let totalPngBytes { data["totalPngBytes"] = totalPngBytes }
        if let pdfBytes { data["pdfBytes"] = pdfBytes }
        if let printTitle { data["printTitle"] = printTitle }
        if let backCoverPitch { data["backCoverPitch"] = backCoverPitch }
        if let coverFontPreset { data["coverFontPreset"] = coverFontPreset }
        return data
    }

    static func fromFirestoreData(_ data: [String: Any]) -> BookVersionRecord? {
        guard let bookVersionId = data["bookVersionId"] as? String,
              let profileId = data["profileId"] as? String,
              let pageCount = data["pageCount"] as? Int,
              let artStyle = data["artStyle"] as? String,
              let orientation = data["orientation"] as? String,
              let pageWidth = data["pageWidth"] as? Double,
              let pageHeight = data["pageHeight"] as? Double,
              let source = data["source"] as? String else {
            return nil
        }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let memoryOrder = data["memoryOrder"] as? [String] ?? []
        let pageMaps = data["pages"] as? [[String: Any]] ?? []
        let pages = pageMaps.compactMap { BookVersionPageRecord.fromFirestoreData($0) }
            .sorted { $0.pageIndex < $1.pageIndex }

        let trimSizeInches = (data["trimSizeInches"] as? String) ?? {
            if orientation == "landscape" { return "11x8.5" }
            return "8.5x11"
        }()
        let layoutVersion = data["layoutVersion"] as? Int ?? BookPrintSpec.layoutVersion
        let renderedAt = (data["renderedAt"] as? Timestamp)?.dateValue()
        let syncedAt = (data["syncedAt"] as? Timestamp)?.dateValue()
        let coverArtRevision: Int? = {
            if let v = data["coverArtRevision"] as? Int { return v }
            if let v = data["coverArtRevision"] as? Int64 { return Int(v) }
            return nil
        }()

        return BookVersionRecord(
            bookVersionId: bookVersionId,
            profileId: profileId,
            createdAt: createdAt,
            memoryOrder: memoryOrder,
            pageCount: pageCount,
            artStyle: artStyle,
            orientation: orientation,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            trimSizeInches: trimSizeInches,
            layoutVersion: layoutVersion,
            printTitle: data["printTitle"] as? String,
            backCoverPitch: data["backCoverPitch"] as? String,
            coverFontPreset: data["coverFontPreset"] as? String,
            pdfStoragePath: data["pdfStoragePath"] as? String,
            pdfURL: data["pdfURL"] as? String,
            pdfPageCount: data["pdfPageCount"] as? Int,
            coverStoragePath: data["coverStoragePath"] as? String,
            coverURL: data["coverURL"] as? String,
            coverArtRevision: coverArtRevision,
            syncedAt: syncedAt,
            renderStatus: (data["renderStatus"] as? String) ?? BookRenderStatus.pending.rawValue,
            renderedAt: renderedAt,
            renderError: data["renderError"] as? String,
            renderAttemptCount: data["renderAttemptCount"] as? Int,
            renderDurationMs: data["renderDurationMs"] as? Int,
            totalPngBytes: data["totalPngBytes"] as? Int,
            pdfBytes: data["pdfBytes"] as? Int,
            source: source,
            pages: pages
        )
    }
}

struct BookVersionLayout {
    let orientation: String
    let pageWidth: Double
    let pageHeight: Double
}

enum BookVersionLayoutFactory {
    static func layout(forArtStyle artStyle: String) -> BookVersionLayout {
        let spec = BookPrintSpec.forArtStyle(artStyle)
        return BookVersionLayout(
            orientation: spec.orientation,
            pageWidth: Double(spec.widthPt),
            pageHeight: Double(spec.heightPt)
        )
    }
}

enum BookVersionRecordFactory {
    static func memoryId(from urlString: String?) -> String? {
        guard let urlString,
              let url = URL(string: urlString),
              url.scheme == "memoirai",
              url.host == "memory" else {
            return nil
        }

        let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : trimmed
    }

    static func fromPersistable(
        _ book: PersistableStorybook,
        bookVersionId: String,
        source: BookVersionSource = .storyGeneration
    ) -> BookVersionRecord {
        let spec = BookPrintSpec.forArtStyle(book.artStyle)
        var memoryOrder: [String] = []
        var pages: [BookVersionPageRecord] = []

        for (index, item) in book.pageItems.enumerated() {
            let memoryId = memoryId(from: item.url)
            if let memoryId, !memoryOrder.contains(memoryId) {
                memoryOrder.append(memoryId)
            }

            pages.append(
                BookVersionPageRecord(
                    pageIndex: index,
                    type: item.type,
                    memoryId: memoryId,
                    memoryCreatedAt: nil,
                    title: item.title,
                    subtitle: item.subtitle,
                    textContent: item.textContent,
                    imageStoragePath: nil,
                    imageURL: nil,
                    renderedPageStoragePath: nil,
                    renderedPageURL: nil,
                    renderedPageFormat: nil,
                    renderedPixelWidth: nil,
                    renderedPixelHeight: nil,
                    renderedChecksum: nil,
                    renderedBytes: nil,
                    createdAt: book.createdAt
                )
            )
        }

        return BookVersionRecord(
            bookVersionId: bookVersionId,
            profileId: book.profileID.uuidString,
            createdAt: book.createdAt,
            memoryOrder: memoryOrder,
            pageCount: pages.count,
            artStyle: book.artStyle,
            orientation: spec.orientation,
            pageWidth: Double(spec.widthPt),
            pageHeight: Double(spec.heightPt),
            trimSizeInches: spec.trimSizeInches,
            layoutVersion: spec.layoutVersion,
            printTitle: book.bookDisplayTitle,
            backCoverPitch: book.backCoverPitch,
            coverFontPreset: book.coverFontPreset,
            pdfStoragePath: nil,
            pdfURL: nil,
            pdfPageCount: nil,
            coverStoragePath: nil,
            coverURL: nil,
            coverArtRevision: nil,
            syncedAt: nil,
            renderStatus: BookRenderStatus.pending.rawValue,
            renderedAt: nil,
            renderError: nil,
            renderAttemptCount: 0,
            renderDurationMs: nil,
            totalPngBytes: nil,
            pdfBytes: nil,
            source: source.rawValue,
            pages: pages
        )
    }
}

extension BookVersionRecord {
    /// Layout used when generating `cover.pdf` for this version (kids `BookCoverTemplate` vs portrait `PortraitLuluCoverTemplate`).
    var coverFlatLayoutKind: BookCoverFlatLayoutKind {
        if pageWidth > pageHeight {
            return .kidsBook
        } else {
            return .portraitCasewrap(pageCount: pageCount)
        }
    }

    /// Stable fingerprint for cover thumbnail caches: prefer explicit revision, then storage path, then legacy `syncedAt` / URL fallbacks.
    var coverThumbnailCacheRevision: String {
        if let r = coverArtRevision {
            return "art:\(r)"
        }
        if let p = coverStoragePath?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return "path:\(p)"
        }
        if let s = syncedAt {
            return String(s.timeIntervalSince1970)
        }
        return [coverURL, "\(renderDurationMs ?? 0)"]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    /// Remote URL for the print cover PDF used by in-app preview (`RemotePDFThumbnailView`).
    /// Accepts Firebase Storage URLs even when `.pdf` is only in `coverStoragePath` or path segments are encoded.
    var printCoverPDFURL: URL? {
        guard let raw = coverURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let lower = raw.lowercased()
        let storageLower = (coverStoragePath ?? "").lowercased()
        if storageLower.hasSuffix("cover.pdf") || storageLower.contains("/cover.pdf") {
            return url
        }
        if lower.contains(".pdf") {
            return url
        }
        let pathLower = url.path.lowercased()
        if pathLower.hasSuffix(".pdf") || pathLower.contains("cover.pdf") {
            return url
        }
        if lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png") || lower.contains(".webp") {
            return nil
        }
        return nil
    }
}

