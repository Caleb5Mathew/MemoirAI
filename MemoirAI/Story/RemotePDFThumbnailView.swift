import SwiftUI
import PDFKit

// MARK: - Shared load / cache (preview + prefetch before revealing storybook)

enum CoverPDFThumbnailService {
    static func cacheKey(
        url: URL,
        layout: BookCoverFlatLayoutKind,
        panel: BookCoverFlatPanel,
        cacheRevision: String = ""
    ) -> String {
        let layoutKey: String
        switch layout {
        case .kidsBook: layoutKey = "kids"
        case .portraitCasewrap(let n): layoutKey = "portrait:\(n)"
        }
        let panelKey: String
        switch panel {
        case .full: panelKey = "full"
        case .back: panelKey = "back"
        case .spine: panelKey = "spine"
        case .front: panelKey = "front"
        }
        let revSuffix = cacheRevision.isEmpty ? "" : "|rev:\(cacheRevision)"
        return "\(url.absoluteString)|\(panelKey)|\(layoutKey)\(revSuffix)"
    }

    static func cachedImage(
        url: URL,
        layout: BookCoverFlatLayoutKind,
        panel: BookCoverFlatPanel,
        cacheRevision: String = ""
    ) -> UIImage? {
        PDFThumbnailCache.shared.image(forKey: cacheKey(url: url, layout: layout, panel: panel, cacheRevision: cacheRevision))
    }

    @MainActor
    static func loadAndCache(
        url: URL,
        layout: BookCoverFlatLayoutKind,
        panel: BookCoverFlatPanel,
        targetSize: CGSize,
        cacheRevision: String = ""
    ) async -> UIImage? {
        let key = cacheKey(url: url, layout: layout, panel: panel, cacheRevision: cacheRevision)
        if let hit = PDFThumbnailCache.shared.image(forKey: key) {
            return hit
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let pdf = PDFDocument(data: data),
                  let page = pdf.page(at: 0) else {
                return nil
            }

            let thumb = renderThumbnail(page: page, targetSize: targetSize, layout: layout, panel: panel)
            guard let thumb else { return nil }
            PDFThumbnailCache.shared.store(image: thumb, forKey: key)
            return thumb
        } catch {
            return nil
        }
    }

    private static func renderThumbnail(
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
    var layout: BookCoverFlatLayoutKind = .kidsBook
    var panel: BookCoverFlatPanel = .full
    /// Busts in-memory cache when the same Storage URL is overwritten (e.g. new cover PDF).
    var cacheRevision: String = ""
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    private var cacheKey: String {
        CoverPDFThumbnailService.cacheKey(url: url, layout: layout, panel: panel, cacheRevision: cacheRevision)
    }

    init(
        url: URL,
        targetSize: CGSize,
        layout: BookCoverFlatLayoutKind = .kidsBook,
        panel: BookCoverFlatPanel = .full,
        cacheRevision: String = "",
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.layout = layout
        self.panel = panel
        self.cacheRevision = cacheRevision
        self.placeholder = placeholder
        _image = State(initialValue: CoverPDFThumbnailService.cachedImage(url: url, layout: layout, panel: panel, cacheRevision: cacheRevision))
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
            image = CoverPDFThumbnailService.cachedImage(url: url, layout: layout, panel: panel, cacheRevision: cacheRevision)
            await load()
        }
    }

    @MainActor
    private func load() async {
        if image != nil { return }
        if isLoading || loadFailed { return }

        isLoading = true
        defer { isLoading = false }

        if let thumb = await CoverPDFThumbnailService.loadAndCache(
            url: url,
            layout: layout,
            panel: panel,
            targetSize: targetSize,
            cacheRevision: cacheRevision
        ) {
            image = thumb
        } else {
            loadFailed = true
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
