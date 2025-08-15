import SwiftUI
import WebKit

// MARK: - Flipbook View (WKWebView wrapper)
struct FlipbookView: UIViewRepresentable {
    let pages: [FlipPage]
    @Binding var currentPage: Int
    let onReady: (() -> Void)?
    let onFlip: ((Int) -> Void)?
    
    init(pages: [FlipPage], currentPage: Binding<Int>, onReady: (() -> Void)? = nil, onFlip: ((Int) -> Void)? = nil) {
        self.pages = pages
        self._currentPage = currentPage
        self.onReady = onReady
        self.onFlip = onFlip
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
        
        // Store reference to webView in coordinator
        context.coordinator.webView = webView
        
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
            // Try to set a reasonable default size
            let defaultFrame = CGRect(x: 0, y: 0, width: 280, height: 374) // Conservative default size
            webView.frame = defaultFrame
            print("FlipbookView: Set default frame: \(defaultFrame)")
            
            // Don't call dimension updates to prevent recursion
            print("FlipbookView: Set default frame, letting PageFlip handle dimensions")
        }
        
        // If the webview is ready and we have pages, render them
        if context.coordinator.isReady && !pages.isEmpty {
            renderPages(webView: webView)
        }
    }
    
    // CRITICAL: Add this method to handle SwiftUI frame updates
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WKWebView, context: Context) -> CGSize? {
        // Return the proposed size to ensure the WebView matches the SwiftUI frame
        let size = proposal.replacingUnspecifiedDimensions()
        print("FlipbookView: sizeThatFits called with proposal: \(proposal), returning: \(size)")
        
        // Also update the WebView frame directly
        if size.width > 0 && size.height > 0 {
            let newFrame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            if uiView.frame != newFrame {
                print("FlipbookView: Updating WebView frame in sizeThatFits from \(uiView.frame) to \(newFrame)")
                uiView.frame = newFrame
            }
        }
        
        return size
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
            let jsonData = try JSONEncoder().encode(pages)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            
            print("FlipbookView: JSON data to render: \(jsonString)")
            
            // Use a safer approach to pass JSON data
            let escapedJSON = jsonString.replacingOccurrences(of: "\\", with: "\\\\")
                                        .replacingOccurrences(of: "'", with: "\\'")
                                        .replacingOccurrences(of: "\"", with: "\\\"")
                                        .replacingOccurrences(of: "\n", with: "\\n")
                                        .replacingOccurrences(of: "\r", with: "\\r")
            
            let jsCode = "window.renderPages('\(escapedJSON)')"
            print("FlipbookView: Executing JS: \(jsCode)")
            
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
        // Alternative approach using base64 encoding
        if let jsonData = jsonString.data(using: .utf8) {
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
                
            default:
                print("FlipbookView: Unknown message type: \(type)")
            }
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
            currentPage: .constant(0)
        )
        .frame(width: 300, height: 400)
    }
} 