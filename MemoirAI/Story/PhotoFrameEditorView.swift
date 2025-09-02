import SwiftUI
import PhotosUI

// MARK: - Photo Frame Editor View
struct PhotoFrameEditorView: View {
    @Binding var isPresented: Bool
    let frameLayout: PhotoLayout?
    let pageIndex: Int
    var onPhotoSelected: ((UIImage) -> Void)?
    
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImage: UIImage?
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    
    private var frameAspectRatio: CGFloat {
        guard let layout = frameLayout else { return 1.0 }
        switch layout.type {
        case .portrait:
            return 3.0 / 4.0
        case .landscape:
            return 4.0 / 3.0
        case .square:
            return 1.0
        case .custom:
            return layout.frame.width / layout.frame.height
        }
    }
    
    private var frameDimensions: CGSize {
        let maxWidth: CGFloat = 300
        let maxHeight: CGFloat = 400
        
        if frameAspectRatio > 1 { // Landscape
            let width = min(maxWidth, maxHeight * frameAspectRatio)
            return CGSize(width: width, height: width / frameAspectRatio)
        } else { // Portrait or Square
            let height = min(maxHeight, maxWidth / frameAspectRatio)
            return CGSize(width: height * frameAspectRatio, height: height)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Title
                Text(selectedImage != nil ? "Adjust Your Photo" : "Add a Photo")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(Tokens.ink)
                
                // Frame preview with photo
                ZStack {
                    // Frame background
                    RoundedRectangle(cornerRadius: frameLayout?.borderStyle == .polaroid ? 0 : 8)
                        .fill(frameLayout?.borderStyle.color ?? Color.white)
                        .frame(width: frameDimensions.width + borderPadding,
                               height: frameDimensions.height + borderPadding + bottomPadding)
                        .shadow(
                            color: frameLayout?.borderStyle.hasShadow ?? false ? Color.black.opacity(0.2) : .clear,
                            radius: frameLayout?.borderStyle.hasShadow ?? false ? 5 : 0,
                            x: 0, y: 2
                        )
                    
                    // Photo area
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: frameDimensions.width, height: frameDimensions.height)
                        
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .scaleEffect(imageScale)
                                .offset(imageOffset)
                                .frame(width: frameDimensions.width, height: frameDimensions.height)
                                .clipped()
                                .gesture(dragGesture)
                                .gesture(magnificationGesture)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "photo")
                                    .font(.system(size: 40))
                                    .foregroundColor(Tokens.ink.opacity(0.3))
                                
                                Text("Tap to select photo")
                                    .font(.caption)
                                    .foregroundColor(Tokens.ink.opacity(0.5))
                            }
                        }
                    }
                    .frame(width: frameDimensions.width, height: frameDimensions.height)
                    .clipShape(RoundedRectangle(cornerRadius: frameLayout?.borderStyle == .polaroid ? 0 : 4))
                }
                
                // Photo picker button
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 1,
                    matching: .images
                ) {
                    HStack {
                        Image(systemName: selectedImage != nil ? "photo.badge.arrow.down" : "photo.badge.plus")
                        Text(selectedImage != nil ? "Change Photo" : "Select Photo")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Tokens.accent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Tokens.accentSoft.opacity(0.2))
                    )
                }
                
                // Instructions
                if selectedImage != nil {
                    VStack(spacing: 8) {
                        Label("Pinch to zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                            .foregroundColor(Tokens.ink.opacity(0.6))
                        
                        Label("Drag to position", systemImage: "hand.draw")
                            .font(.caption)
                            .foregroundColor(Tokens.ink.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: savePhoto) {
                        Text("Save Photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Tokens.accent)
                            )
                    }
                    .disabled(selectedImage == nil)
                    .opacity(selectedImage == nil ? 0.5 : 1.0)
                    
                    Button(action: { isPresented = false }) {
                        Text("Cancel")
                            .font(.system(size: 16))
                            .foregroundColor(Tokens.ink.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .background(Tokens.bgPrimary)
            .navigationBarHidden(true)
        }
        .onChange(of: selectedItems) { newItems in
            guard let newItem = newItems.first else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    // Reset transform when new image is selected
                    imageScale = 1.0
                    imageOffset = .zero
                    lastScale = 1.0
                    lastOffset = .zero
                }
            }
        }
        .onAppear {
            loadExistingImage()
        }
    }
    
    // MARK: - Gestures
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                imageOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = imageOffset
            }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                imageScale *= delta
                imageScale = max(0.5, min(imageScale, 3.0)) // Limit scale
            }
            .onEnded { _ in
                lastScale = 1.0
            }
    }
    
    // MARK: - Helper Properties
    private var borderPadding: CGFloat {
        guard let style = frameLayout?.borderStyle else { return 0 }
        switch style {
        case .polaroid:
            return 40
        case .vintage:
            return 16
        case .thick:
            return 12
        case .thin:
            return 4
        default:
            return 0
        }
    }
    
    private var bottomPadding: CGFloat {
        frameLayout?.borderStyle == .polaroid ? 40 : 0
    }
    
    // MARK: - Methods
    private func loadExistingImage() {
        guard let layout = frameLayout,
              let imageDataString = layout.imageData else { return }
        
        // Handle base64 encoded image
        if imageDataString.hasPrefix("data:image") {
            // Remove data URL prefix
            let base64String = imageDataString
                .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
                .replacingOccurrences(of: "data:image/png;base64,", with: "")
            
            if let data = Data(base64Encoded: base64String),
               let image = UIImage(data: data) {
                selectedImage = image
            }
        } else if let data = Data(base64Encoded: imageDataString),
                  let image = UIImage(data: data) {
            selectedImage = image
        }
    }
    
    private func savePhoto() {
        guard let image = selectedImage else { return }
        
        // Create a cropped version of the image based on current transform
        let croppedImage = cropImage(image)
        
        onPhotoSelected?(croppedImage)
        isPresented = false
    }
    
    private func cropImage(_ image: UIImage) -> UIImage {
        // For now, return the original image
        // In a full implementation, this would apply the crop based on scale and offset
        return image
    }
}

// MARK: - Tokens Extension
extension PhotoFrameEditorView {
    struct Tokens {
        static let accent = Color(hex: "C9652F")
        static let accentSoft = Color(hex: "F5E6D8")
        static let ink = Color(hex: "2C2C2C")
        static let bgPrimary = Color(hex: "FFF9F3")
    }
}