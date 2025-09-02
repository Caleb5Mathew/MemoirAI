import SwiftUI
import PhotosUI

// MARK: - Photo Frame View
struct PhotoFrameView: View {
    @Binding var layout: PhotoLayout
    @State private var isSelected = false
    @State private var dragOffset: CGSize = .zero
    @State private var lastScaleValue: CGFloat = 1.0
    @State private var currentScale: CGFloat = 1.0
    @State private var showPhotoPicker = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    
    // Callbacks
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?
    
    var body: some View {
        ZStack {
            // Main frame
            frameContent
                .frame(width: layout.frame.width * currentScale, 
                       height: layout.frame.height * currentScale)
                .background(frameBackground)
                .overlay(frameBorder)
                .shadow(
                    color: layout.borderStyle.hasShadow ? Tokens.shadow.opacity(0.2) : .clear,
                    radius: layout.borderStyle.hasShadow ? 5 : 0,
                    x: 0,
                    y: 2
                )
                .rotationEffect(.degrees(layout.rotation))
                .position(
                    x: layout.frame.midX + dragOffset.width,
                    y: layout.frame.midY + dragOffset.height
                )
                .gesture(combinedGestures)
            
            // Selection handles
            if isSelected && !layout.isLocked {
                selectionHandles
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text("Select Photo")
            }
            .onChange(of: selectedItem) { newItem in
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        layout.imageData = data.base64EncodedString()
                        image = UIImage(data: data)
                    }
                }
            }
        }
    }
    
    // MARK: - Frame Content
    @ViewBuilder
    private var frameContent: some View {
        if let imageData = layout.imageData, 
           let data = Data(base64Encoded: imageData),
           let uiImage = UIImage(data: data) {
            // Show the photo
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            // Show placeholder
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Tokens.ink.opacity(0.3))
                
                Text("Tap to add photo")
                    .font(.system(size: 12))
                    .foregroundColor(Tokens.ink.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.8))
            .onTapGesture {
                showPhotoPicker = true
            }
        }
    }
    
    // MARK: - Frame Background
    private var frameBackground: some View {
        RoundedRectangle(cornerRadius: layout.borderStyle == .polaroid ? 0 : 8)
            .fill(layout.borderStyle.color)
            .padding(layout.borderStyle == .polaroid ? -20 : 0)
            .padding(.bottom, layout.borderStyle == .polaroid ? -40 : 0)
    }
    
    // MARK: - Frame Border
    private var frameBorder: some View {
        RoundedRectangle(cornerRadius: layout.borderStyle == .polaroid ? 0 : 8)
            .stroke(
                isSelected ? Tokens.accent : layout.borderStyle.color,
                lineWidth: isSelected ? 2 : layout.borderStyle.strokeWidth
            )
    }
    
    // MARK: - Selection Handles
    private var selectionHandles: some View {
        Group {
            // Corner resize handles
            ForEach(HandlePosition.allCases, id: \.self) { position in
                ResizeHandle(position: position)
                    .position(handlePosition(for: position))
                    .gesture(resizeGesture(for: position))
            }
            
            // Delete button
            Button(action: {
                onDelete?()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.red)
                    .background(Circle().fill(Color.white))
            }
            .position(
                x: layout.frame.minX + dragOffset.width - 10,
                y: layout.frame.minY + dragOffset.height - 10
            )
            
            // Rotation handle
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20))
                .foregroundColor(Tokens.accent)
                .background(Circle().fill(Color.white).frame(width: 30, height: 30))
                .position(
                    x: layout.frame.midX + dragOffset.width,
                    y: layout.frame.minY + dragOffset.height - 30
                )
                .gesture(rotationGesture)
        }
    }
    
    // MARK: - Gestures
    private var combinedGestures: some Gesture {
        SimultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSelected.toggle()
                        if layout.imageData == nil {
                            showPhotoPicker = true
                        }
                    }
                    onTap?()
                },
            DragGesture()
                .onChanged { value in
                    if !layout.isLocked {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if !layout.isLocked {
                        layout.frame.origin.x += value.translation.width
                        layout.frame.origin.y += value.translation.height
                        dragOffset = .zero
                    }
                }
        )
    }
    
    private var rotationGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let angle = atan2(value.location.y - layout.frame.height/2,
                                 value.location.x - layout.frame.width/2)
                layout.rotation = Double(angle) * 180 / .pi
            }
    }
    
    private func resizeGesture(for position: HandlePosition) -> some Gesture {
        DragGesture()
            .onChanged { value in
                var newFrame = layout.frame
                
                switch position {
                case .topLeft:
                    newFrame.origin.x += value.translation.width
                    newFrame.origin.y += value.translation.height
                    newFrame.size.width -= value.translation.width
                    newFrame.size.height -= value.translation.height
                case .topRight:
                    newFrame.origin.y += value.translation.height
                    newFrame.size.width += value.translation.width
                    newFrame.size.height -= value.translation.height
                case .bottomLeft:
                    newFrame.origin.x += value.translation.width
                    newFrame.size.width -= value.translation.width
                    newFrame.size.height += value.translation.height
                case .bottomRight:
                    newFrame.size.width += value.translation.width
                    newFrame.size.height += value.translation.height
                }
                
                // Maintain minimum size
                if newFrame.width > 50 && newFrame.height > 50 {
                    layout.frame = newFrame
                }
            }
    }
    
    // MARK: - Helper Methods
    private func handlePosition(for position: HandlePosition) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        
        switch position {
        case .topLeft:
            x = layout.frame.minX
            y = layout.frame.minY
        case .topRight:
            x = layout.frame.maxX
            y = layout.frame.minY
        case .bottomLeft:
            x = layout.frame.minX
            y = layout.frame.maxY
        case .bottomRight:
            x = layout.frame.maxX
            y = layout.frame.maxY
        }
        
        return CGPoint(x: x + dragOffset.width, y: y + dragOffset.height)
    }
}

// MARK: - Handle Position
enum HandlePosition: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

// MARK: - Resize Handle
struct ResizeHandle: View {
    let position: HandlePosition
    
    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 16, height: 16)
            .overlay(
                Circle()
                    .stroke(Tokens.accent, lineWidth: 2)
            )
            .shadow(radius: 2)
    }
}

// MARK: - Preview
struct PhotoFrameView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.2)
            
            PhotoFrameView(
                layout: .constant(
                    PhotoLayout(
                        type: .portrait,
                        frame: CGRect(x: 100, y: 100, width: 150, height: 200)
                    )
                )
            )
        }
        .frame(width: 400, height: 600)
    }
}