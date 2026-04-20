import SwiftUI

// MARK: - Photo Layout Overlay View
/// Overlay component that renders photo layouts on top of WebView flipbook
/// This allows native drag gestures without conflicting with page flip animation
struct PhotoLayoutOverlayView: View {
    let page: FlipPage
    let pageIndex: Int
    let bookSize: CGSize
    let isKidsBook: Bool
    let onLayoutTap: (UUID) -> Void
    let onLayoutMoved: (UUID, CGPoint) -> Void
    
    // Base page coordinate space used by layout frames.
    private var pageWidth: CGFloat { isKidsBook ? 428.8 : 321.6 }
    private var pageHeight: CGFloat { isKidsBook ? 321.6 : 428.8 }
    
    // Scale factor to convert from page coordinates to book size
    private var scaleFactor: CGFloat {
        min(bookSize.width / pageWidth, bookSize.height / pageHeight)
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let layouts = page.photoLayouts, !layouts.isEmpty {
                ForEach(layouts) { layout in
                    PhotoLayoutInteractiveView(
                        layout: layout,
                        scaleFactor: scaleFactor,
                        pageWidth: pageWidth,
                        pageHeight: pageHeight,
                        onTap: {
                            onLayoutTap(layout.id)
                        },
                        onMoved: { newMidPoint in
                            // Convert back to page coordinates (from center point to origin)
                            let pageMidX = newMidPoint.x / scaleFactor
                            let pageMidY = newMidPoint.y / scaleFactor
                            let pageOriginX = pageMidX - (layout.frame.width / 2)
                            let pageOriginY = pageMidY - (layout.frame.height / 2)
                            onLayoutMoved(layout.id, CGPoint(x: pageOriginX, y: pageOriginY))
                        }
                    )
                    .offset(
                        x: layout.frame.origin.x * scaleFactor,
                        y: layout.frame.origin.y * scaleFactor
                    )
                }
            }
        }
        .frame(width: bookSize.width, height: bookSize.height)
        .allowsHitTesting(true) // Enable touches for photo layouts
    }
}

// MARK: - Photo Layout Interactive View
/// Individual photo layout view with drag and tap gestures
struct PhotoLayoutInteractiveView: View {
    let layout: PhotoLayout
    let scaleFactor: CGFloat
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let onTap: () -> Void
    let onMoved: (CGPoint) -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    
    // Scaled frame dimensions
    private var scaledFrame: CGRect {
        CGRect(
            x: layout.frame.origin.x * scaleFactor,
            y: layout.frame.origin.y * scaleFactor,
            width: layout.frame.width * scaleFactor,
            height: layout.frame.height * scaleFactor
        )
    }
    
    var body: some View {
        ZStack {
            // Frame background
            RoundedRectangle(cornerRadius: layout.borderStyle == .polaroid ? 0 : 4)
                .fill(Color.white)
                .frame(width: scaledFrame.width, height: scaledFrame.height)
                .overlay(
                    RoundedRectangle(cornerRadius: layout.borderStyle == .polaroid ? 0 : 4)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                )
                .shadow(color: isDragging ? Color.black.opacity(0.3) : Color.black.opacity(0.1),
                       radius: isDragging ? 8 : 4,
                       x: 0,
                       y: isDragging ? 4 : 2)
            
            // Photo or placeholder
            if let imageData = layout.imageData,
               let data = Data(base64Encoded: imageData.replacingOccurrences(of: "data:image/jpeg;base64,", with: "")),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: scaledFrame.width, height: scaledFrame.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: layout.borderStyle == .polaroid ? 0 : 4))
            } else {
                // Placeholder
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 20))
                        .foregroundColor(Color.gray.opacity(0.5))
                    
                    Text("TEST: Tap to add photo")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.gray.opacity(0.6))
                }
                .frame(width: scaledFrame.width, height: scaledFrame.height)
                .background(Color.gray.opacity(0.1))
            }
        }
        .frame(width: scaledFrame.width, height: scaledFrame.height)
        .offset(
            x: dragOffset.width,
            y: dragOffset.height
        )
        .rotationEffect(.degrees(layout.rotation))
        .opacity(isDragging ? 0.9 : 1.0)
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        // Start drag
                        isDragging = true
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }
                    
                    // Update drag offset
                    dragOffset = value.translation
                }
                .onEnded { value in
                    isDragging = false
                    
                    // Calculate new position (from origin, not center)
                    let newOriginX = scaledFrame.origin.x + dragOffset.width
                    let newOriginY = scaledFrame.origin.y + dragOffset.height
                    
                    // Constrain to bounds (with margin)
                    let margin: CGFloat = 10 * scaleFactor
                    let maxX = (pageWidth * scaleFactor) - scaledFrame.width - margin
                    let maxY = (pageHeight * scaleFactor) - scaledFrame.height - margin
                    let constrainedX = max(margin, min(newOriginX, maxX))
                    let constrainedY = max(margin, min(newOriginY, maxY))
                    
                    // Reset drag offset
                    dragOffset = .zero
                    
                    // Notify parent of new position (convert to center point for callback)
                    let constrainedMidX = constrainedX + scaledFrame.width / 2
                    let constrainedMidY = constrainedY + scaledFrame.height / 2
                    onMoved(CGPoint(x: constrainedMidX, y: constrainedMidY))
                    
                    // Haptic feedback
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    // Only trigger tap if not dragging
                    if !isDragging {
                        onTap()
                    }
                }
        )
    }
}

