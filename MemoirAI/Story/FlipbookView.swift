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
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        
        // Store reference to webView in coordinator
        context.coordinator.webView = webView
        
        // Load the local HTML file
        if let bundleURL = Bundle.main.url(forResource: "FlipbookBundle", withExtension: nil) {
            let indexURL = bundleURL.appendingPathComponent("index.html")
            print("FlipbookView: Bundle URL found: \(bundleURL)")
            print("FlipbookView: Index URL: \(indexURL)")
            webView.loadFileURL(indexURL, allowingReadAccessTo: bundleURL)
        } else {
            print("FlipbookView: ERROR - FlipbookBundle not found in app bundle!")
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
        
        // If the webview is ready and we have pages, render them
        if context.coordinator.isReady && !pages.isEmpty {
            renderPages(webView: webView)
        }
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
            
            webView.evaluateJavaScript("window.renderPages('\(jsonString)')") { _, error in
                if let error = error {
                    print("Error rendering pages: \(error)")
                }
            }
        } catch {
            print("Error encoding pages: \(error)")
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
                parent.onReady?()
                
                // Render pages if we have them
                if !parent.pages.isEmpty {
                    parent.renderPages(webView: message.webView)
                }
                
            case "flip":
                if let index = body["index"] as? Int {
                    parent.currentPage = index
                    parent.onFlip?(index)
                }
                
            case "pagesLoaded":
                if let count = body["count"] as? Int {
                    print("FlipbookView: Loaded \(count) pages")
                }
                
            case "error":
                if let errorMessage = body["message"] as? String {
                    print("FlipbookView JavaScript error: \(errorMessage)")
                }
                
            case "stateChange":
                if let state = body["state"] as? String {
                    print("FlipbookView state change: \(state)")
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
        // This will be called from the parent view
    }
    
    func prev(webView: WKWebView?) {
        guard let webView = webView else { return }
        // This will be called from the parent view
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