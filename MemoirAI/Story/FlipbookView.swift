import SwiftUI
import WebKit
import PDFKit

// MARK: - Flipbook View (WKWebView wrapper)
struct FlipbookView: UIViewRepresentable {
    let pages: [FlipPage]
    @Binding var currentPage: Int
    @Binding var webView: WKWebView?
    let onReady: (() -> Void)?
    let onFlip: ((Int) -> Void)?
    let onPageTap: ((Int) -> Void)?
    let onPhotoFrameTap: ((Int, String, Int) -> Void)?
    let isKidsBook: Bool
    
    init(pages: [FlipPage], currentPage: Binding<Int>, webView: Binding<WKWebView?> = .constant(nil), isKidsBook: Bool = false, onReady: (() -> Void)? = nil, onFlip: ((Int) -> Void)? = nil, onPageTap: ((Int) -> Void)? = nil, onPhotoFrameTap: ((Int, String, Int) -> Void)? = nil) {
        self.pages = pages
        self._currentPage = currentPage
        self._webView = webView
        self.isKidsBook = isKidsBook
        self.onReady = onReady
        self.onFlip = onFlip
        self.onPageTap = onPageTap
        self.onPhotoFrameTap = onPhotoFrameTap
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Enable JavaScript (iOS 14+ compatible)
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            config.preferences.javaScriptEnabled = true
        }
        
        // Add message handler for communication with JavaScript
        config.userContentController.add(context.coordinator, name: "native")
        
        // Create WKWebView with a proper initial frame - use the expected book size
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 280, height: 374), configuration: config)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        
        // CRITICAL: Set content mode to scale to fit
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        
        // Ensure webview background is transparent
        webView.scrollView.backgroundColor = .clear
        
        // Store reference to webView in coordinator and binding
        context.coordinator.webView = webView
        
        // Set the webView in the binding so parent views can access it
        DispatchQueue.main.async {
            self.webView = webView
        }
        
        print("FlipbookView: Created WKWebView with frame: \(webView.frame)")
        
        // Load the local HTML file
        if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            print("FlipbookView: Index URL found: \(indexURL)")
            // Get the bundle directory for read access
            if let bundlePath = Bundle.main.resourcePath {
                let bundleURL = URL(fileURLWithPath: bundlePath)
                print("FlipbookView: Bundle path: \(bundlePath)")
                webView.loadFileURL(indexURL, allowingReadAccessTo: bundleURL)
            } else {
                print("FlipbookView: ERROR - Could not get bundle resource path")
            }
        } else {
            print("FlipbookView: ERROR - index.html not found in app bundle!")
            // List available resources for debugging
            if let resourceURLs = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: nil) {
                print("FlipbookView: Available resources: \(resourceURLs)")
            } else {
                print("FlipbookView: No resources found")
            }
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        
        // CRITICAL FIX: Get the actual container size from the webView's superview
        // Try multiple approaches to get the correct container size
        var containerSize = webView.superview?.bounds.size ?? webView.bounds.size
        
        // If superview bounds are zero, try to get from the webView's frame in the parent view
        if containerSize.width == 0 || containerSize.height == 0 {
            if let superview = webView.superview {
                // Get the webView's frame within its superview
                let webViewFrame = webView.frame
                if webViewFrame.width > 0 && webViewFrame.height > 0 {
                    containerSize = webViewFrame.size
                } else {
                    // Fallback to superview bounds
                    containerSize = superview.bounds.size
                }
            }
        }
        
        // Debug: Log the current frame and container size
        print("FlipbookView: updateUIView called with frame: \(webView.frame)")
        print("FlipbookView: WebView bounds: \(webView.bounds)")
        print("FlipbookView: Container size: \(containerSize)")
        print("FlipbookView: WebView content size: \(webView.scrollView.contentSize)")
        print("FlipbookView: WebView superview: \(webView.superview?.description ?? "nil")")
        print("FlipbookView: WebView superview bounds: \(webView.superview?.bounds ?? CGRect.zero)")
        
        // DEBUG: Keep red background for visual debugging but don't load test content
        print("FlipbookView: WebView frame updated, keeping red background for debugging")
        
        // CRITICAL: Update the WebView frame to match the container size
        if containerSize.width > 0 && containerSize.height > 0 {
            // Ensure we don't exceed the container bounds
            let maxWidth = min(containerSize.width, 800)
            let maxHeight = min(containerSize.height, 800)
            let newFrame = CGRect(x: 0, y: 0, width: maxWidth, height: maxHeight)
            
            print("FlipbookView: Updating WebView frame from \(webView.frame) to \(newFrame)")
            webView.frame = newFrame
            
            // Force layout update
            webView.setNeedsLayout()
            webView.layoutIfNeeded()
            
            // Don't call dimension updates to prevent recursion - let PageFlip handle its own sizing
            print("FlipbookView: Frame updated, letting PageFlip handle dimensions")
        } else {
            print("FlipbookView: WARNING - Container has zero dimensions!")
            print("FlipbookView: This is the root cause - SwiftUI is not giving the WebView proper space!")
            print("FlipbookView: Setting WebView to use its own frame instead of container size")
            
            // CRITICAL FIX: Use the WebView's current frame instead of relying on container
            let currentFrame = webView.frame
            if currentFrame.width > 0 && currentFrame.height > 0 {
                print("FlipbookView: Using WebView's current frame: \(currentFrame)")
            } else {
                // Try to set a reasonable default size
                let defaultFrame = CGRect(x: 0, y: 0, width: 280, height: 374) // Conservative default size
                webView.frame = defaultFrame
                print("FlipbookView: Set default frame: \(defaultFrame)")
            }
            
            // Don't call dimension updates to prevent recursion
            print("FlipbookView: Set default frame, letting PageFlip handle dimensions")
        }
        
        // If the webview is ready and we have pages, render them
        // Always re-render when ready to ensure updates are reflected
        if context.coordinator.isReady && !pages.isEmpty {
            renderPages(webView: webView)
        }
    }
    
    // CRITICAL: Add this method to handle SwiftUI frame updates
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WKWebView, context: Context) -> CGSize? {
        // Return the proposed size to ensure the WebView matches the SwiftUI frame
        let size = proposal.replacingUnspecifiedDimensions()
        print("FlipbookView: sizeThatFits called with proposal: \(proposal), returning: \(size)")
        
        // CRITICAL FIX: Always return a valid size, even if proposal is zero
        let finalSize = CGSize(
            width: max(size.width, 280),
            height: max(size.height, 374)
        )
        
        // Also update the WebView frame directly
        if finalSize.width > 0 && finalSize.height > 0 {
            let newFrame = CGRect(x: 0, y: 0, width: finalSize.width, height: finalSize.height)
            if uiView.frame != newFrame {
                print("FlipbookView: Updating WebView frame in sizeThatFits from \(uiView.frame) to \(newFrame)")
                uiView.frame = newFrame
            }
        }
        
        return finalSize
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Public API
    func next(webView: WKWebView) {
        webView.evaluateJavaScript("window.next()") { _, error in
            if let error = error {
                print("Error calling next: \(error)")
            }
        }
    }
    
    func prev(webView: WKWebView) {
        webView.evaluateJavaScript("window.prev()") { _, error in
            if let error = error {
                print("Error calling prev: \(error)")
            }
        }
    }
    
    func goToPage(_ pageIndex: Int, webView: WKWebView) {
        webView.evaluateJavaScript("window.goToPage(\(pageIndex))") { _, error in
            if let error = error {
                print("Error calling goToPage: \(error)")
            }
        }
    }
    

    

    
    private func renderPages(webView: WKWebView) {
        do {
            // Convert pages with image names to base64
            let pagesWithBase64 = pages.map { page -> FlipPage in
                if let imageName = page.imageName, page.imageBase64 == nil {
                    // Try to load image from Assets and convert to base64
                    if let uiImage = UIImage(named: imageName) {
                        // Resize large images to reasonable dimensions for flipbook
                        let maxSize: CGFloat = 800
                        let resizedImage: UIImage
                        
                        if uiImage.size.width > maxSize || uiImage.size.height > maxSize {
                            let scale = min(maxSize / uiImage.size.width, maxSize / uiImage.size.height)
                            let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
                            
                            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
                            uiImage.draw(in: CGRect(origin: .zero, size: newSize))
                            resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? uiImage
                            UIGraphicsEndImageContext()
                            
                            print("FlipbookView: Resized \(imageName) from \(uiImage.size) to \(newSize)")
                        } else {
                            resizedImage = uiImage
                        }
                        
                        // Use higher compression for better performance
                        if let imageData = resizedImage.jpegData(compressionQuality: 0.6) {
                            let base64String = imageData.base64EncodedString()
                            print("FlipbookView: Converted \(imageName) to base64 (length: \(base64String.count))")
                            return FlipPage(
                                type: page.type,
                                title: page.title,
                                caption: page.caption,
                                text: page.text,
                                imageBase64: base64String,
                                imageName: page.imageName
                            )
                        } else {
                            print("FlipbookView: Could not compress image: \(imageName)")
                        }
                    } else {
                        print("FlipbookView: Could not load image: \(imageName)")
                    }
                }
                return page
            }
            
            let jsonData = try JSONEncoder().encode(pagesWithBase64)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            
            print("FlipbookView: JSON data to render: \(jsonString.prefix(200))...")
            
            // Use a safer approach to pass JSON data
            let escapedJSON = jsonString.replacingOccurrences(of: "\\", with: "\\\\")
                                        .replacingOccurrences(of: "'", with: "\\'")
                                        .replacingOccurrences(of: "\"", with: "\\\"")
                                        .replacingOccurrences(of: "\n", with: "\\n")
                                        .replacingOccurrences(of: "\r", with: "\\r")
            
            let jsCode = "window.renderPages('\(escapedJSON)')"
            print("FlipbookView: Executing JS (length: \(jsCode.count))")
            
            webView.evaluateJavaScript(jsCode) { result, error in
                if let error = error {
                    print("Error rendering pages: \(error)")
                    // Try alternative approach if the first fails
                    self.renderPagesAlternative(webView: webView, jsonString: jsonString)
                } else {
                    print("FlipbookView: Pages rendered successfully")
                }
            }
        } catch {
            print("Error encoding pages: \(error)")
        }
    }
    
    private func renderPagesAlternative(webView: WKWebView, jsonString: String) {
        // Alternative approach - convert pages with images before encoding
        do {
            let pagesWithBase64 = pages.map { page -> FlipPage in
                if let imageName = page.imageName, page.imageBase64 == nil {
                    if let uiImage = UIImage(named: imageName) {
                        // Resize large images to reasonable dimensions for flipbook
                        let maxSize: CGFloat = 800
                        let resizedImage: UIImage
                        
                        if uiImage.size.width > maxSize || uiImage.size.height > maxSize {
                            let scale = min(maxSize / uiImage.size.width, maxSize / uiImage.size.height)
                            let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
                            
                            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
                            uiImage.draw(in: CGRect(origin: .zero, size: newSize))
                            resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? uiImage
                            UIGraphicsEndImageContext()
                        } else {
                            resizedImage = uiImage
                        }
                        
                        // Use higher compression for better performance
                        if let imageData = resizedImage.jpegData(compressionQuality: 0.6) {
                            let base64String = imageData.base64EncodedString()
                            return FlipPage(
                                type: page.type,
                                title: page.title,
                                caption: page.caption,
                                text: page.text,
                                imageBase64: base64String,
                                imageName: page.imageName
                            )
                        }
                    }
                }
                return page
            }
            
            let jsonData = try JSONEncoder().encode(pagesWithBase64)
            let base64String = jsonData.base64EncodedString()
            let jsCode = """
                (function() {
                    try {
                        var jsonData = atob('\(base64String)');
                        var pages = JSON.parse(jsonData);
                        window.renderPages(pages);
                    } catch(e) {
                        console.error('Error parsing pages:', e);
                    }
                })();
            """
            
            webView.evaluateJavaScript(jsCode) { result, error in
                if let error = error {
                    print("Alternative rendering also failed: \(error)")
                } else {
                    print("FlipbookView: Pages rendered successfully (alternative method)")
                }
            }
        } catch {
            print("Error in alternative rendering: \(error)")
        }
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: FlipbookView
        var isReady = false
        weak var webView: WKWebView?
        
        init(_ parent: FlipbookView) {
            self.parent = parent
        }
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // WebView finished loading
            print("FlipbookView: WebView loaded successfully")
            print("FlipbookView: URL loaded: \(webView.url?.absoluteString ?? "unknown")")
            
            // DEBUG: Check WebView content after loading
            print("FlipbookView: WebView content size after loading: \(webView.scrollView.contentSize)")
            print("FlipbookView: WebView frame after loading: \(webView.frame)")
            print("FlipbookView: WebView bounds after loading: \(webView.bounds)")
            
            // DEBUG: Check if WebView can execute JavaScript
            webView.evaluateJavaScript("document.body.innerHTML") { result, error in
                if let error = error {
                    print("FlipbookView: Error getting HTML content: \(error)")
                } else if let html = result as? String {
                    print("FlipbookView: HTML content length: \(html.count)")
                    print("FlipbookView: HTML content preview: \(String(html.prefix(200)))")
                }
            }
            
            // DEBUG: Check if WebView is visible
            print("FlipbookView: WebView isHidden: \(webView.isHidden)")
            print("FlipbookView: WebView alpha: \(webView.alpha)")
            print("FlipbookView: WebView isUserInteractionEnabled: \(webView.isUserInteractionEnabled)")
            
            // DEBUG: Check WebView's parent view hierarchy
            var parentView = webView.superview
            var level = 0
            while parentView != nil {
                print("FlipbookView: Parent view level \(level): \(parentView?.description ?? "nil")")
                print("FlipbookView: Parent view level \(level) frame: \(parentView?.frame ?? CGRect.zero)")
                print("FlipbookView: Parent view level \(level) isHidden: \(parentView?.isHidden ?? true)")
                parentView = parentView?.superview
                level += 1
                if level > 5 { break } // Prevent infinite loop
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("FlipbookView: WebView failed to load: \(error)")
        }
        
        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "native",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }
            
            switch type {
            case "ready":
                isReady = true
                print("FlipbookView: JavaScript ready message received")
                
                // Check if there's an error in the ready message
                if let errorMessage = body["error"] as? String {
                    print("FlipbookView: JavaScript ready with error: \(errorMessage)")
                    // Still mark as ready but notify parent of error
                    parent.onFlip?(-1) // Signal error
                } else {
                    print("FlipbookView: JavaScript ready successfully")
                    parent.onReady?()
                    
                    // Don't force dimension updates to prevent recursion
                    print("FlipbookView: JavaScript ready, letting PageFlip handle dimensions")
                    
                    // Render pages if we have them
                    if !parent.pages.isEmpty, let webView = self.webView {
                        parent.renderPages(webView: webView)
                    }
                }
                
            case "flip":
                if let index = body["index"] as? Int {
                    parent.currentPage = index
                    parent.onFlip?(index)
                }
                
            case "pagesLoaded":
                if let count = body["count"] as? Int {
                    print("FlipbookView: Loaded \(count) pages")
                    
                    // Don't force dimension updates to prevent recursion
                    print("FlipbookView: Pages loaded, letting PageFlip handle dimensions")
                }
                
            case "error":
                if let errorMessage = body["message"] as? String {
                    print("FlipbookView JavaScript error: \(errorMessage)")
                    // Notify parent of error
                    parent.onFlip?(-1) // Use -1 to indicate error
                }
                
            case "stateChange":
                if let state = body["state"] as? String {
                    print("FlipbookView state change: \(state)")
                }
                
            case "resize":
                if let dimensions = body["dimensions"] as? [String: Any] {
                    print("FlipbookView resize: \(dimensions)")
                }
                
            case "dimensionsUpdated":
                if let dimensions = body["dimensions"] as? [String: Any] {
                    print("FlipbookView: Dimensions updated to: \(dimensions)")
                }
                
            case "pageTapped":
                if let index = body["pageIndex"] as? Int {
                    parent.onPageTap?(index)
                }
                
            case "photoFrameTapped":
                if let pageIndex = body["pageIndex"] as? Int,
                   let frameId = body["frameId"] as? String,
                   let frameIndex = body["frameIndex"] as? Int {
                    print("FlipbookView: Photo frame tapped - page: \(pageIndex), frame: \(frameId), index: \(frameIndex)")
                    parent.onPhotoFrameTap?(pageIndex, frameId, frameIndex)
                }
                
            case "zoomOpened":
                print("FlipbookView: Zoom opened")
                
            case "zoomClosed":
                print("FlipbookView: Zoom closed")
                
            case "downloadPDF":
                if let pages = body["pages"] as? [String],
                   let filename = body["filename"] as? String {
                    // Handle PDF download
                    handlePDFDownload(pages: pages, filename: filename)
                }
                
            default:
                print("FlipbookView: Unknown message type: \(type)")
            }
        }
        
        private func handlePDFDownload(pages: [String], filename: String) {
            print("FlipbookView: Handling PDF download with \(pages.count) pages")
            
            // Get the presenting view controller
            var presentingViewController: UIViewController?
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                presentingViewController = rootVC
            }
            
            // Use the BookDownloadHandler to handle the PDF with book type info
            BookDownloadHandler.handlePDFDownload(
                pages: pages,
                filename: filename,
                presentingView: presentingViewController,
                isKidsBook: parent.isKidsBook
            )
        }
    }
}

// MARK: - Flipbook Controller (for external control)
class FlipbookController: ObservableObject {
    @Published var currentPage: Int = 0
    @Published var isReady: Bool = false
    
    var onFlip: ((Int) -> Void)?
    
    func next(webView: WKWebView?) {
        guard let webView = webView else { return }
        webView.evaluateJavaScript("window.next()") { _, error in
            if let error = error {
                print("Error calling next: \(error)")
            }
        }
    }
    
    func prev(webView: WKWebView?) {
        guard let webView = webView else { return }
        webView.evaluateJavaScript("window.prev()") { _, error in
            if let error = error {
                print("Error calling prev: \(error)")
            }
        }
    }
}

// MARK: - Preview
struct FlipbookView_Previews: PreviewProvider {
    static var previews: some View {
        FlipbookView(
            pages: FlipPage.samplePages,
            currentPage: .constant(0),
            webView: .constant(nil)
        )
        .frame(width: 300, height: 400)
    }
} 