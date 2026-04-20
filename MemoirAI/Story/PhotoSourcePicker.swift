import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Photo Source Picker
struct PhotoSourcePicker: View {
    @Binding var isPresented: Bool
    var onPhotoSelected: ((UIImage) -> Void)?
    
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Tokens.ink)
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Tokens.ink.opacity(0.5))
                }
            }
            .padding()
            
            Divider()
            
            // Options
            VStack(spacing: 0) {
                // Camera Roll / Photo Library
                Button(action: {
                    showPhotoLibrary = true
                }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                            .foregroundColor(Tokens.accent)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Photo Library")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Tokens.ink)
                            
                            Text("Choose from your photos")
                                .font(.system(size: 14))
                                .foregroundColor(Tokens.ink.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(Tokens.ink.opacity(0.3))
                    }
                    .padding()
                }
                .buttonStyle(.plain)
                
                Divider()
                    .padding(.leading, 64)
                
                // Take Photo
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(action: {
                        showCamera = true
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .foregroundColor(Tokens.accent)
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Take Photo")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Tokens.ink)
                                
                                Text("Capture a new photo")
                                    .font(.system(size: 14))
                                    .foregroundColor(Tokens.ink.opacity(0.6))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(Tokens.ink.opacity(0.3))
                        }
                        .padding()
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .padding(.leading, 64)
                }
                
                // Files
                Button(action: {
                    showFiles = true
                }) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Tokens.accent)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Files")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Tokens.ink)
                            
                            Text("Choose from Files app")
                                .font(.system(size: 14))
                                .foregroundColor(Tokens.ink.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(Tokens.ink.opacity(0.3))
                    }
                    .padding()
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .background(Tokens.bgPrimary)
        .sheet(isPresented: $showPhotoLibrary) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                EmptyView()
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(source: .camera, allowsCropping: true) { image in
                handlePhotoSelected(image)
            }
        }
        .sheet(isPresented: $showFiles) {
            DocumentPicker(allowedContentTypes: [.image]) { url in
                handleFileSelected(url: url)
            }
        }
        .onChange(of: selectedPhotoItem) { newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    handlePhotoSelected(image)
                }
            }
        }
    }
    
    private func handlePhotoSelected(_ image: UIImage) {
        selectedImage = image
        onPhotoSelected?(image)
        isPresented = false
    }
    
    private func handleFileSelected(url: URL) {
        guard let imageData = try? Data(contentsOf: url),
              let image = UIImage(data: imageData) else {
            return
        }
        handlePhotoSelected(image)
    }
}

// MARK: - Image Picker (reusable)
private struct CameraImagePicker: UIViewControllerRepresentable {
    var source: UIImagePickerController.SourceType
    var allowsCropping: Bool
    var onPicked: (UIImage) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.allowsEditing = allowsCropping
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onPicked: (UIImage) -> Void
        
        init(onPicked: @escaping (UIImage) -> Void) {
            self.onPicked = onPicked
        }
        
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let key: UIImagePickerController.InfoKey = picker.allowsEditing ? .editedImage : .originalImage
            if let img = info[key] as? UIImage {
                onPicked(img)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    var allowedContentTypes: [UTType]
    var onDocumentPicked: (URL) -> Void
    
    func makeCoordinator() -> DocumentPickerCoordinator {
        DocumentPickerCoordinator(onDocumentPicked: onDocumentPicked)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
        var onDocumentPicked: (URL) -> Void
        
        init(onDocumentPicked: @escaping (URL) -> Void) {
            self.onDocumentPicked = onDocumentPicked
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onDocumentPicked(url)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // Handle cancellation if needed
        }
    }
}

// MARK: - Tokens Extension
extension PhotoSourcePicker {
    struct Tokens {
        static let accent = Color(hex: "C9652F")
        static let accentSoft = Color(hex: "F5E6D8")
        static let ink = Color(hex: "2C2C2C")
        static let bgPrimary = Color(hex: "FFF9F3")
    }
}

// Note: Color(hex:) extension is defined in CoverSettings.swift
// This file uses that existing extension

