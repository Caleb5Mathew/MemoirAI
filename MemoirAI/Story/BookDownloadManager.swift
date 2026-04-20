import SwiftUI
import WebKit
import PDFKit
import Photos
import UniformTypeIdentifiers

class BookDownloadManager: NSObject, ObservableObject {
    @Published var isProcessing = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showSuccess = false
    @Published var successMessage = ""
    
    private weak var presentingViewController: UIViewController?
    private var webView: WKWebView?
    private var completion: (() -> Void)?
    private var isKidsBook: Bool = false  // Track if this is a kids book for orientation
    
    // MARK: - Initialization
    init(webView: WKWebView? = nil, isKidsBook: Bool = false) {
        self.webView = webView
        self.isKidsBook = isKidsBook
        super.init()
    }
    
    // MARK: - Set Book Type
    func setBookType(isKidsBook: Bool) {
        self.isKidsBook = isKidsBook
    }
    
    // MARK: - Public Methods
    func saveRenderedPagesToPhotos(_ pageImages: [UIImage], from viewController: UIViewController?) {
        guard !pageImages.isEmpty else {
            showErrorAlert("No rendered pages available to save")
            return
        }
        
        self.presentingViewController = viewController
        
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    self?.saveUIImagePagesToPhotoLibrary(pageImages)
                case .denied, .restricted:
                    self?.showErrorAlert("Photo library access is required to save images. Please enable it in Settings.")
                default:
                    self?.showErrorAlert("Photo library permission not granted")
                }
            }
        }
    }
    
    func saveRenderedPagesAsPDF(
        _ pageImages: [UIImage],
        printSpec: BookPrintSpec,
        filename: String = "MemoirAI_Storybook.pdf",
        from viewController: UIViewController?
    ) {
        guard !pageImages.isEmpty else {
            showErrorAlert("No rendered pages available for PDF export")
            return
        }
        
        guard let pdfData = BookDownloadHandler.makePDFFromRenderedPages(pageImages, printSpec: printSpec) else {
            showErrorAlert("Failed to generate PDF from rendered pages")
            return
        }
        
        guard let viewController else {
            showErrorAlert("No presenting view controller for PDF export")
            return
        }
        
        presentPDFSaveDialog(with: pdfData, filename: filename, from: viewController)
    }

    func saveToPhotos(webView: WKWebView?, from viewController: UIViewController?) {
        guard let webView = webView else {
            showErrorAlert("Unable to access book content")
            return
        }
        
        self.webView = webView
        self.presentingViewController = viewController
        
        // Check photo library permission
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    self?.captureAndSaveToPhotos()
                case .denied, .restricted:
                    self?.showErrorAlert("Photo library access is required to save images. Please enable it in Settings.")
                case .notDetermined:
                    self?.showErrorAlert("Photo library permission not determined")
                @unknown default:
                    self?.showErrorAlert("Unknown photo library permission status")
                }
            }
        }
    }
    
    func saveToFiles(webView: WKWebView?, from viewController: UIViewController?) {
        guard let webView = webView else {
            showErrorAlert("Unable to access book content")
            return
        }
        
        self.webView = webView
        self.presentingViewController = viewController
        
        isProcessing = true
        
        // Trigger JavaScript PDF generation with orientation info
        let jsCode = "window.downloadPDF(\(isKidsBook ? "true" : "false"))"
        webView.evaluateJavaScript(jsCode) { [weak self] _, error in
            if let error = error {
                self?.isProcessing = false
                self?.showErrorAlert("Failed to generate PDF: \(error.localizedDescription)")
            }
            // The PDF will be handled by the message handler in FlipbookView
            // We'll implement a delegate pattern or notification to handle the result
        }
    }
    
    // MARK: - Private Methods
    private func captureAndSaveToPhotos() {
        guard let webView = webView else { return }
        
        isProcessing = true
        
        // JavaScript to capture all pages as images
        let jsCode = """
        (async function() {
            if (!window.pageFlip) {
                return { error: 'PageFlip not initialized' };
            }
            
            const totalPages = window.pageFlip.getPageCount();
            const currentPage = window.pageFlip.getCurrentPageIndex();
            const images = [];
            
            for (let i = 0; i < totalPages; i++) {
                window.pageFlip.flip(i);
                await new Promise(resolve => setTimeout(resolve, 500));
                
                // Capture the current page
                const bookElement = document.getElementById('book');
                if (bookElement && typeof html2canvas !== 'undefined') {
                    const canvas = await html2canvas(bookElement, {
                        backgroundColor: '#faf8f3',
                        scale: 2,
                        logging: false
                    });
                    images.push(canvas.toDataURL('image/jpeg', 0.95));
                }
            }
            
            // Return to original page
            window.pageFlip.flip(currentPage);
            
            return { images: images, count: images.length };
        })();
        """
        
        webView.evaluateJavaScript(jsCode) { [weak self] result, error in
            self?.isProcessing = false
            
            if let error = error {
                self?.showErrorAlert("Failed to capture pages: \(error.localizedDescription)")
                return
            }
            
            guard let dict = result as? [String: Any],
                  let imageStrings = dict["images"] as? [String] else {
                self?.showErrorAlert("Failed to process page images")
                return
            }
            
            self?.saveImagesToPhotoLibrary(imageStrings)
        }
    }
    
    private func saveImagesToPhotoLibrary(_ imageDataStrings: [String]) {
        var savedCount = 0
        let totalCount = imageDataStrings.count
        
        PHPhotoLibrary.shared().performChanges({
            for imageString in imageDataStrings {
                // Remove data URL prefix if present
                let base64String: String
                if imageString.hasPrefix("data:image/jpeg;base64,") {
                    base64String = String(imageString.dropFirst("data:image/jpeg;base64,".count))
                } else if imageString.hasPrefix("data:image/png;base64,") {
                    base64String = String(imageString.dropFirst("data:image/png;base64,".count))
                } else {
                    base64String = imageString
                }
                
                guard let imageData = Data(base64Encoded: base64String),
                      let image = UIImage(data: imageData) else {
                    continue
                }
                
                // Create photo asset
                PHAssetChangeRequest.creationRequestForAsset(from: image)
                savedCount += 1
            }
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.showSuccessAlert("Saved \(savedCount) pages to Photos")
                } else {
                    self?.showErrorAlert("Failed to save images: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    private func saveUIImagePagesToPhotoLibrary(_ images: [UIImage]) {
        PHPhotoLibrary.shared().performChanges({
            for image in images {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.showSuccessAlert("Saved \(images.count) pages to Photos")
                } else {
                    self?.showErrorAlert("Failed to save images: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    // MARK: - Alert Helpers
    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
        
        // Also show system alert for better visibility
        if let viewController = presentingViewController {
            let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
        }
    }
    
    private func showSuccessAlert(_ message: String) {
        successMessage = message
        showSuccess = true
        
        // Also show system alert for better visibility
        if let viewController = presentingViewController {
            let alert = UIAlertController(title: "Success", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
        }
    }
}

// MARK: - PDF Handling Extension
extension BookDownloadManager {
    func presentPDFSaveDialog(with pdfData: Data, filename: String, from viewController: UIViewController, isKidsBook: Bool? = nil) {
        // Save to temporary directory first
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try pdfData.write(to: tempURL)
            
            // Present document picker for saving
            let documentPicker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
            documentPicker.delegate = self
            documentPicker.modalPresentationStyle = .formSheet
            
            viewController.present(documentPicker, animated: true)
            
        } catch {
            showErrorAlert("Failed to prepare PDF for saving: \(error.localizedDescription)")
        }
    }
}

// MARK: - UIDocumentPickerDelegate
extension BookDownloadManager: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        showSuccessAlert("Book saved successfully to Files")
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // User cancelled, no action needed
    }
}

// MARK: - SwiftUI Integration
struct BookDownloadHandler {
    static func makePDFFromRenderedPages(_ pageImages: [UIImage], printSpec: BookPrintSpec) -> Data? {
        guard !pageImages.isEmpty else { return nil }
        
        let bounds = CGRect(x: 0, y: 0, width: printSpec.widthPt, height: printSpec.heightPt)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        
        return renderer.pdfData { context in
            for image in pageImages {
                context.beginPage()
                image.draw(in: bounds)
            }
        }
    }

    static func handlePDFDownload(pages: [String], filename: String, presentingView: UIViewController?, isKidsBook: Bool = false) {
        // Standard US Letter dimensions in points (1 inch = 72 points)
        // Comic, Realistic, Custom: 8.5 x 11 inches = 612 x 792 points (portrait)
        // Kids Book: 11 x 8.5 inches = 792 x 612 points (landscape)
        let pdfWidth: CGFloat = isKidsBook ? (11.0 * 72) : (8.5 * 72)  // 792 or 612 points
        let pdfHeight: CGFloat = isKidsBook ? (8.5 * 72) : (11.0 * 72)  // 612 or 792 points
        let pdfBounds = CGRect(x: 0, y: 0, width: pdfWidth, height: pdfHeight)
        
        // Use UIGraphicsPDFRenderer to create PDF with correct page dimensions
        let renderer = UIGraphicsPDFRenderer(bounds: pdfBounds)
        
        let pdfData = renderer.pdfData { ctx in
            // Process each page image
            for (index, pageDataString) in pages.enumerated() {
                // Remove data URL prefix if present
                let base64String: String
                if pageDataString.hasPrefix("data:image/jpeg;base64,") {
                    base64String = String(pageDataString.dropFirst("data:image/jpeg;base64,".count))
                } else if pageDataString.hasPrefix("data:image/png;base64,") {
                    base64String = String(pageDataString.dropFirst("data:image/png;base64,".count))
                } else {
                    base64String = pageDataString
                }
                
                // Decode base64 to image data
                guard let imageData = Data(base64Encoded: base64String),
                      let image = UIImage(data: imageData) else {
                    print("BookDownloadHandler: Failed to decode page \(index + 1)")
                    continue
                }
                
                // Begin new PDF page with correct bounds
                ctx.beginPage(withBounds: pdfBounds, pageInfo: [:])
                
                // Fill background with paper color
                let context = ctx.cgContext
                context.setFillColor(UIColor(red: 0.98, green: 0.96, blue: 0.89, alpha: 1.0).cgColor)
                context.fill(pdfBounds)
                
                // Draw image scaled to fit page bounds while maintaining aspect ratio
                let imageAspect = image.size.width / image.size.height
                let pageAspect = pdfWidth / pdfHeight
                
                var drawRect = pdfBounds
                if imageAspect > pageAspect {
                    // Image is wider - fit to width
                    let scaledHeight = pdfWidth / imageAspect
                    drawRect = CGRect(x: 0, y: (pdfHeight - scaledHeight) / 2, width: pdfWidth, height: scaledHeight)
                } else {
                    // Image is taller - fit to height
                    let scaledWidth = pdfHeight * imageAspect
                    drawRect = CGRect(x: (pdfWidth - scaledWidth) / 2, y: 0, width: scaledWidth, height: pdfHeight)
                }
                
                image.draw(in: drawRect)
            }
        }
        
        // Check if we have pages
        guard !pages.isEmpty else {
            print("BookDownloadHandler: No pages were added to PDF")
            return
        }
        
        // Present save dialog
        if let viewController = presentingView {
            let manager = BookDownloadManager(isKidsBook: isKidsBook)
            manager.presentPDFSaveDialog(with: pdfData, filename: filename, from: viewController, isKidsBook: isKidsBook)
        }
    }
}