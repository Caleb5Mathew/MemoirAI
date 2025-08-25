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
    
    // MARK: - Initialization
    init(webView: WKWebView? = nil) {
        self.webView = webView
        super.init()
    }
    
    // MARK: - Public Methods
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
        
        // Trigger JavaScript PDF generation
        webView.evaluateJavaScript("window.downloadPDF()") { [weak self] _, error in
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
    func presentPDFSaveDialog(with pdfData: Data, filename: String, from viewController: UIViewController) {
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
    static func handlePDFDownload(pages: [String], filename: String, presentingView: UIViewController?) {
        // Create PDF document
        let pdfDocument = PDFDocument()
        
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
            
            // Create PDF page from image
            if let pdfPage = PDFPage(image: image) {
                pdfDocument.insert(pdfPage, at: index)
            }
        }
        
        // Check if we have pages
        guard pdfDocument.pageCount > 0 else {
            print("BookDownloadHandler: No pages were added to PDF")
            return
        }
        
        // Get PDF data
        guard let pdfData = pdfDocument.dataRepresentation() else {
            print("BookDownloadHandler: Failed to generate PDF data")
            return
        }
        
        // Present save dialog
        if let viewController = presentingView {
            let manager = BookDownloadManager()
            manager.presentPDFSaveDialog(with: pdfData, filename: filename, from: viewController)
        }
    }
}