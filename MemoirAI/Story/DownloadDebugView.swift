import SwiftUI
import WebKit

/// Debug view to test and diagnose book download functionality
struct DownloadDebugView: View {
    @State private var debugLog: [String] = []
    @State private var isHtml2CanvasLoaded = false
    @State private var pageCount = 0
    @State private var currentPage = 0
    @State private var containerSize: CGSize = .zero
    @State private var bookSize: CGSize = .zero
    @State private var isTestingDownload = false
    @State private var capturedPageCount = 0
    
    let webView: WKWebView?
    
    var body: some View {
        ZStack {
            DevDashboardBackground()

            VStack(spacing: 16) {
                Text("Download Debug Console")
                    .font(.headline)
                    .foregroundStyle(DevDashboardPalette.primaryText)
                    .padding()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Status Section
                        debugGroupCard(title: "System Status", icon: "checkmark.circle") {
                            VStack(alignment: .leading, spacing: 8) {
                                StatusRow(label: "html2canvas", value: isHtml2CanvasLoaded ? "Loaded" : "Not Loaded")
                                StatusRow(label: "WebView", value: webView != nil ? "Available" : "Missing")
                                StatusRow(label: "Total Pages", value: "\(pageCount)")
                                StatusRow(label: "Current Page", value: "\(currentPage)")
                                StatusRow(label: "Container Size", value: "\(Int(containerSize.width))×\(Int(containerSize.height))")
                                StatusRow(label: "Book Size", value: "\(Int(bookSize.width))×\(Int(bookSize.height))")
                            }
                        }
                        
                        // Test Actions
                        debugGroupCard(title: "Test Actions", icon: "wrench.and.screwdriver") {
                            VStack(spacing: 8) {
                                Button(action: checkHtml2Canvas) {
                                    Label("Check html2canvas", systemImage: "magnifyingglass")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(DevDashboardPalette.accentA)
                                
                                Button(action: getPageInfo) {
                                    Label("Get Page Info", systemImage: "book")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(DevDashboardPalette.accentA)
                                
                                Button(action: testSinglePageCapture) {
                                    Label("Test Single Page Capture", systemImage: "camera")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(DevDashboardPalette.accentA)
                                
                                Button(action: testFullDownload) {
                                    Label(isTestingDownload ? "Testing..." : "Test Full Download", systemImage: "arrow.down.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(DevDashboardPalette.accentB)
                                .disabled(isTestingDownload)
                                
                                if isTestingDownload {
                                    ProgressView("Capturing page \(capturedPageCount) of \(pageCount)")
                                        .foregroundStyle(DevDashboardPalette.secondaryText)
                                        .tint(DevDashboardPalette.accentA)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        
                        // Debug Log
                        debugGroupCard(title: "Debug Log", icon: "terminal") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    if debugLog.isEmpty {
                                        Text("No logs yet. Run a test action above.")
                                            .foregroundStyle(DevDashboardPalette.tertiaryText)
                                            .italic()
                                    } else {
                                        ForEach(debugLog.indices, id: \.self) { index in
                                            Text(debugLog[index])
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(DevDashboardPalette.primaryText)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            }
                            .frame(height: 200)
                        }
                        
                        Button(action: { debugLog.removeAll() }) {
                            Label("Clear Log", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            addLog("Debug console initialized")
            checkHtml2Canvas()
            getPageInfo()
        }
    }
    
    // MARK: - Debug Actions
    
    private func checkHtml2Canvas() {
        guard let webView = webView else {
            addLog("❌ WebView not available")
            return
        }
        
        addLog("Checking html2canvas...")
        
        let jsCode = """
        (function() {
            return {
                loaded: typeof html2canvas !== 'undefined',
                version: typeof html2canvas !== 'undefined' ? html2canvas.version || 'unknown' : null,
                pageFlip: typeof window.pageFlip !== 'undefined'
            };
        })();
        """
        
        webView.evaluateJavaScript(jsCode) { result, error in
            if let error = error {
                addLog("❌ Error checking html2canvas: \(error.localizedDescription)")
                return
            }
            
            if let dict = result as? [String: Any] {
                let loaded = dict["loaded"] as? Bool ?? false
                let pageFlipExists = dict["pageFlip"] as? Bool ?? false
                
                isHtml2CanvasLoaded = loaded
                
                if loaded {
                    addLog("✅ html2canvas is loaded")
                    if let version = dict["version"] as? String {
                        addLog("   Version: \(version)")
                    }
                } else {
                    addLog("❌ html2canvas NOT loaded")
                    addLog("   Check: MemoirAI/Resources/FlipbookBundle/html2canvas.min.js")
                }
                
                if pageFlipExists {
                    addLog("✅ PageFlip initialized")
                } else {
                    addLog("❌ PageFlip not initialized")
                }
            }
        }
    }
    
    private func getPageInfo() {
        guard let webView = webView else {
            addLog("❌ WebView not available")
            return
        }
        
        addLog("Getting page info...")
        
        let jsCode = """
        (function() {
            if (!window.pageFlip) return { error: 'PageFlip not initialized' };
            
            const container = document.getElementById('book-container');
            const book = document.getElementById('book');
            
            return {
                totalPages: window.pageFlip.getPageCount ? window.pageFlip.getPageCount() : 0,
                currentPage: window.pageFlip.getCurrentPageIndex ? window.pageFlip.getCurrentPageIndex() : 0,
                containerWidth: container ? container.offsetWidth : 0,
                containerHeight: container ? container.offsetHeight : 0,
                bookWidth: book ? book.offsetWidth : 0,
                bookHeight: book ? book.offsetHeight : 0
            };
        })();
        """
        
        webView.evaluateJavaScript(jsCode) { result, error in
            if let error = error {
                addLog("❌ Error getting page info: \(error.localizedDescription)")
                return
            }
            
            if let dict = result as? [String: Any] {
                if let errorMsg = dict["error"] as? String {
                    addLog("❌ \(errorMsg)")
                    return
                }
                
                pageCount = dict["totalPages"] as? Int ?? 0
                currentPage = dict["currentPage"] as? Int ?? 0
                
                let containerW = dict["containerWidth"] as? CGFloat ?? 0
                let containerH = dict["containerHeight"] as? CGFloat ?? 0
                containerSize = CGSize(width: containerW, height: containerH)
                
                let bookW = dict["bookWidth"] as? CGFloat ?? 0
                let bookH = dict["bookHeight"] as? CGFloat ?? 0
                bookSize = CGSize(width: bookW, height: bookH)
                
                addLog("✅ Page info retrieved:")
                addLog("   Total pages: \(pageCount)")
                addLog("   Current page: \(currentPage)")
                addLog("   Container: \(Int(containerW))×\(Int(containerH))")
                addLog("   Book: \(Int(bookW))×\(Int(bookH))")
            }
        }
    }
    
    private func testSinglePageCapture() {
        guard let webView = webView else {
            addLog("❌ WebView not available")
            return
        }
        
        guard isHtml2CanvasLoaded else {
            addLog("❌ html2canvas not loaded. Cannot capture.")
            return
        }
        
        addLog("Testing single page capture...")
        
        let jsCode = """
        (async function() {
            try {
                const bookElement = document.getElementById('book');
                if (!bookElement) return { error: 'Book element not found' };
                
                const canvas = await html2canvas(bookElement, {
                    backgroundColor: '#faf8f3',
                    scale: 2,
                    logging: true,
                    useCORS: true
                });
                
                const imageData = canvas.toDataURL('image/jpeg', 0.95);
                
                return {
                    success: true,
                    width: canvas.width,
                    height: canvas.height,
                    dataLength: imageData.length,
                    dataSample: imageData.substring(0, 50)
                };
            } catch (error) {
                return { error: error.toString() };
            }
        })();
        """
        
        webView.evaluateJavaScript(jsCode) { result, error in
            if let error = error {
                addLog("❌ JavaScript error: \(error.localizedDescription)")
                return
            }
            
            if let dict = result as? [String: Any] {
                if let errorMsg = dict["error"] as? String {
                    addLog("❌ Capture failed: \(errorMsg)")
                    return
                }
                
                if dict["success"] as? Bool == true {
                    let width = dict["width"] as? Int ?? 0
                    let height = dict["height"] as? Int ?? 0
                    let dataLength = dict["dataLength"] as? Int ?? 0
                    
                    addLog("✅ Capture successful!")
                    addLog("   Canvas: \(width)×\(height)")
                    addLog("   Data size: \(dataLength / 1024)KB")
                    addLog("   Expected ~500KB-1MB per page")
                }
            }
        }
    }
    
    private func testFullDownload() {
        guard let webView = webView else {
            addLog("❌ WebView not available")
            return
        }
        
        guard isHtml2CanvasLoaded else {
            addLog("❌ html2canvas not loaded. Cannot download.")
            return
        }
        
        guard pageCount > 0 else {
            addLog("❌ No pages to download")
            return
        }
        
        addLog("Starting full download test...")
        addLog("This will capture \(pageCount) pages")
        
        isTestingDownload = true
        capturedPageCount = 0
        
        // Trigger the actual download function
        let jsCode = "window.downloadPDF(false)" // false = regular book
        
        webView.evaluateJavaScript(jsCode) { result, error in
            if let error = error {
                addLog("❌ Download failed: \(error.localizedDescription)")
                isTestingDownload = false
                return
            }
            
            addLog("✅ Download triggered")
            addLog("Watch console for capture progress...")
            
            // Reset after a delay (download takes time)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(pageCount) * 1.0) {
                isTestingDownload = false
            }
        }
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("[\(timestamp)] \(message)")
        print("[DownloadDebug] \(message)")
    }

    @ViewBuilder
    private func debugGroupCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DevDashboardPalette.primaryText)
            content()
        }
        .padding(12)
        .devGlassCard(radius: 14, fillOpacity: 0.1)
    }
}

// MARK: - Supporting Views

struct StatusRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(DevDashboardPalette.secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(DevDashboardPalette.primaryText)
        }
        .font(.caption)
    }
}

// MARK: - Preview

struct DownloadDebugView_Previews: PreviewProvider {
    static var previews: some View {
        DownloadDebugView(webView: nil)
    }
}










