import SwiftUI
import PDFKit

// MARK: - Shared load / cache (preview + prefetch before revealing storybook)

/// Coalesces concurrent downloads for the same cache key (prefetch + SwiftUI `.task`).
private actor CoverPDFThumbnailInflight {
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    func deduped(key: String, compute: @escaping @Sendable () async -> UIImage?) async -> UIImage? {
        if let existing = tasks[key] {
            return await existing.value
        }
        let task = Task { await compute() }
        tasks[key] = task
        let value = await task.value
        tasks[key] = nil
        return value
    }

    static let shared = CoverPDFThumbnailInflight()
}

private struct PDFCoverDownloadResult: Sendable {
    let data: Data?
    let status: Int?
}

enum CoverPDFThumbnailService {
    static func cacheKey(
        url: URL,
        layout: BookCoverFlatLayoutKind,
        panel: BookCoverFlatPanel,
        cacheRevision: String = "",
        cacheIdentity: String = ""
    ) -> String {
        let layoutKey: String
        switch layout {
        case .kidsBook(let n): layoutKey = "kids:\(n)"
        case .portraitCasewrap(let n): layoutKey = "portrait:\(n)"
        }
        let panelKey: String
        switch panel {
        case .full: panelKey = "full"
        case .back: panelKey = "back"
        case .spine: panelKey = "spine"
        case .front: panelKey = "front"
        }
        let trimmedId = cacheIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = trimmedId.isEmpty ? url.absoluteString : trimmedId
        let revSuffix = cacheRevision.isEmpty ? "" : "|rev:\(cacheRevision)"
        return "\(primary)|\(panelKey)|\(layoutKey)\(revSuffix)"
    }

    static func cachedImage(
        url: URL,
        layout: BookCoverFlatLayoutKind,
        panel: BookCoverFlatPanel,
        cacheRevision: String = "",
        cacheIdentity: String = ""
    ) -> UIImage? {
        let key = cacheKey(url: url, layout: layout, panel: panel, cacheRevision: cacheRevision, cacheIdentity: cacheIdentity)
        if let hit = PDFThumbnailCache.shared.image(forKey: key) {
            return hit
        }
        if let disk = PDFThumbnailDiskCache.shared.image(forKey: key) {
            PDFThumbnailCache.shared.store(image: disk, forKey: key)
            return disk
        }
        return nil
    }

    static func loadAndCache(
        url: URL,
        layout: BookCoverFlatLayoutKind,
        panel: BookCoverFlatPanel,
        targetSize: CGSize,
        cacheRevision: String = "",
        cacheIdentity: String = ""
    ) async -> UIImage? {
        let key = cacheKey(url: url, layout: layout, panel: panel, cacheRevision: cacheRevision, cacheIdentity: cacheIdentity)
        if let mem = await MainActor.run(body: { PDFThumbnailCache.shared.image(forKey: key) }) {
            return mem
        }
        if let disk = await MainActor.run(body: { PDFThumbnailDiskCache.shared.image(forKey: key) }) {
            await MainActor.run {
                PDFThumbnailCache.shared.store(image: disk, forKey: key)
            }
            return disk
        }

        let trimmed = cacheIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathForFreshURL = trimmed.isEmpty ? nil : trimmed

        return await CoverPDFThumbnailInflight.shared.deduped(key: key) {
            await Self.downloadRenderAndStore(
                initialURL: url,
                layout: layout,
                panel: panel,
                targetSize: targetSize,
                cacheKey: key,
                storagePathForFreshURL: pathForFreshURL
            )
        }
    }

    private static func downloadPDFBytes(from url: URL) async -> PDFCoverDownloadResult {
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            let code = (response as? HTTPURLResponse)?.statusCode
            return PDFCoverDownloadResult(data: data, status: code)
        } catch {
            return PDFCoverDownloadResult(data: nil, status: nil)
        }
    }

    private static func pdfPayloadLooksValid(_ r: PDFCoverDownloadResult) -> Bool {
        guard let s = r.status, (200...299).contains(s),
              let d = r.data,
              !d.isEmpty,
              PDFDocument(data: d)?.page(at: 0) != nil else {
            return false
        }
        return true
    }

    private static func downloadRenderAndStore(
        initialURL: URL,
        layout: BookCoverFlatLayoutKind,
        panel: BookCoverFlatPanel,
        targetSize: CGSize,
        cacheKey: String,
        storagePathForFreshURL: String?
    ) async -> UIImage? {
        var result = await downloadPDFBytes(from: initialURL)
        if !pdfPayloadLooksValid(result), let path = storagePathForFreshURL,
           let fresh = try? await StorageService.shared.freshDownloadURL(forStoragePath: path) {
            result = await downloadPDFBytes(from: fresh)
        }

        guard pdfPayloadLooksValid(result), let data = result.data else { return nil }

        let thumb: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) else { return nil }
            return renderThumbnail(page: page, targetSize: targetSize, layout: layout, panel: panel)
        }.value

        guard let thumb else { return nil }
        await MainActor.run {
            PDFThumbnailCache.shared.store(image: thumb, forKey: cacheKey)
            PDFThumbnailDiskCache.shared.store(image: thumb, forKey: cacheKey)
        }
        return thumb
    }

    nonisolated private static func renderThumbnail(
        page: PDFPage,
        targetSize: CGSize,
        layout: BookCoverFlatLayoutKind,
        panel: BookCoverFlatPanel
    ) -> UIImage? {
        if panel == .full {
            let sanitizedSize = CGSize(
                width: max(targetSize.width, 24),
                height: max(targetSize.height, 24)
            )
            return page.thumbnail(of: sanitizedSize, for: .mediaBox)
        }

        let rects = BookCoverRenderer.flatPanelRects(for: layout)
        guard let panelRect = rects.normalizedRect(for: panel) else { return nil }

        let expandW = 1 / max(panelRect.width, 0.01)
        let expandH = 1 / max(panelRect.height, 0.01)
        let sanitizedSize = CGSize(
            width: max(targetSize.width * expandW, 24),
            height: max(targetSize.height * expandH, 24)
        )

        let fullThumb = page.thumbnail(of: sanitizedSize, for: .mediaBox)
        let oriented = fullThumb.normalizedUpOrientation()
        return oriented.cropping(toNormalizedRect: panelRect)
    }
}

struct RemotePDFThumbnailView<Placeholder: View>: View {
    let url: URL
    let targetSize: CGSize
    var layout: BookCoverFlatLayoutKind = .kidsBook(pageCount: 24)
    var panel: BookCoverFlatPanel = .full
    /// Busts in-memory cache when the same Storage URL is overwritten (e.g. new cover PDF).
    var cacheRevision: String = ""
    /// When non-empty (e.g. Firebase Storage path for `cover.pdf`), cache keys stay stable across rotated signed URLs.
    var cacheIdentity: String = ""
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    private var cacheKey: String {
        CoverPDFThumbnailService.cacheKey(url: url, layout: layout, panel: panel, cacheRevision: cacheRevision, cacheIdentity: cacheIdentity)
    }

    init(
        url: URL,
        targetSize: CGSize,
        layout: BookCoverFlatLayoutKind = .kidsBook(pageCount: 24),
        panel: BookCoverFlatPanel = .full,
        cacheRevision: String = "",
        cacheIdentity: String = "",
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.layout = layout
        self.panel = panel
        self.cacheRevision = cacheRevision
        self.cacheIdentity = cacheIdentity
        self.placeholder = placeholder
        _image = State(initialValue: CoverPDFThumbnailService.cachedImage(url: url, layout: layout, panel: panel, cacheRevision: cacheRevision, cacheIdentity: cacheIdentity))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    placeholder()
                    if isLoading {
                        ProgressView()
                    }
                }
            }
        }
        .task(id: cacheKey) {
            loadFailed = false
            image = CoverPDFThumbnailService.cachedImage(url: url, layout: layout, panel: panel, cacheRevision: cacheRevision, cacheIdentity: cacheIdentity)
            await load()
        }
    }

    @MainActor
    private func load() async {
        if image != nil { return }
        if isLoading || loadFailed { return }

        let panelLabel = String(describing: panel)
        print("[CoverThumb] load START panel=\(panelLabel) cacheKeySuffix=\(cacheRevision.prefix(16))…")
        isLoading = true
        defer { isLoading = false }

        if let thumb = await CoverPDFThumbnailService.loadAndCache(
            url: url,
            layout: layout,
            panel: panel,
            targetSize: targetSize,
            cacheRevision: cacheRevision,
            cacheIdentity: cacheIdentity
        ) {
            image = thumb
            print("[CoverThumb] load OK panel=\(panelLabel)")
        } else {
            loadFailed = true
            print("[CoverThumb] load FAIL panel=\(panelLabel)")
        }
    }
}

final class PDFThumbnailCache {
    static let shared = PDFThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    /// Clears all cached cover thumbnails (e.g. after sign-out). Panel keys include URL + revision.
    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Persistent disk cache for rendered cover thumbnails. Keys include `cacheRevision`,
/// so regenerating the cover naturally invalidates.
final class PDFThumbnailDiskCache {
    static let shared = PDFThumbnailDiskCache()
    private let queue = DispatchQueue(label: "PDFThumbnailDiskCache", qos: .utility)
    private let directory: URL?

    init() {
        let fm = FileManager.default
        if let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = base.appendingPathComponent("memoir-cover-thumbs", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            self.directory = dir
        } else {
            self.directory = nil
        }
    }

    private func fileURL(forKey key: String) -> URL? {
        guard let directory else { return nil }
        let hash = String(key.hashValue)
        return directory.appendingPathComponent("\(hash).jpg", isDirectory: false)
    }

    func image(forKey key: String) -> UIImage? {
        guard let url = fileURL(forKey: key),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    func store(image: UIImage, forKey key: String) {
        guard let url = fileURL(forKey: key),
              let data = image.jpegData(compressionQuality: 0.88) else { return }
        queue.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    func removeAll() {
        guard let directory else { return }
        queue.async {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

/// Persistent disk cache for full-resolution page illustration images.
final class IllustrationImageDiskCache {
    static let shared = IllustrationImageDiskCache()
    private let queue = DispatchQueue(label: "IllustrationImageDiskCache", qos: .utility)
    private let directory: URL?

    init() {
        let fm = FileManager.default
        if let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = base.appendingPathComponent("memoir-illustrations", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            self.directory = dir
        } else {
            self.directory = nil
        }
    }

    private func fileURL(forKey key: String) -> URL? {
        guard let directory else { return nil }
        let hash = String(key.hashValue)
        return directory.appendingPathComponent("\(hash).jpg", isDirectory: false)
    }

    func image(forKey key: String) -> UIImage? {
        guard let url = fileURL(forKey: key),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    func store(image: UIImage, forKey key: String) {
        guard let url = fileURL(forKey: key),
              let data = image.jpegData(compressionQuality: 0.9) else { return }
        queue.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    func removeAll() {
        guard let directory else { return }
        queue.async {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

private extension UIImage {
    /// PDFKit thumbnails can report non-`.up` orientation; normalize before pixel cropping.
    func normalizedUpOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func cropping(toNormalizedRect normalizedRect: CGRect) -> UIImage? {
        let normalized = normalizedUpOrientation()
        guard let cg = normalized.cgImage else { return nil }
        let iw = CGFloat(cg.width)
        let ih = CGFloat(cg.height)
        let cropRect = CGRect(
            x: normalizedRect.origin.x * iw,
            y: normalizedRect.origin.y * ih,
            width: normalizedRect.width * iw,
            height: normalizedRect.height * ih
        ).integral
        guard cropRect.width >= 1, cropRect.height >= 1,
              let cut = cg.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cut, scale: normalized.scale, orientation: .up)
    }
}
