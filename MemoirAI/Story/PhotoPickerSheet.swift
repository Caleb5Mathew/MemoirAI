import SwiftUI
import PhotosUI

// MARK: - Photo Picker Sheet
struct PhotoPickerSheet: View {
    @Binding var isPresented: Bool
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    
    var onPhotosSelected: (([UIImage]) -> Void)?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    Text("Add Photos to Your Story")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.ink)
                        .multilineTextAlignment(.center)
                    
                    Text("Select photos that will bring your memories to life")
                        .font(Tokens.Typography.subtitle)
                        .foregroundColor(Tokens.ink.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 20)
                .padding(.bottom, 30)
                
                // Photo picker
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 50))
                            .foregroundColor(Tokens.accent)
                        
                        Text("Select Photos")
                            .font(Tokens.Typography.button)
                            .foregroundColor(Tokens.ink)
                        
                        Text("Choose up to 10 photos")
                            .font(Tokens.Typography.subtitle)
                            .foregroundColor(Tokens.ink.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                            .fill(Tokens.bgWash)
                            .overlay(
                                                            RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                                .stroke(Tokens.accentSoft.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                }
                
                // Selected images preview
                if !selectedImages.isEmpty {
                    VStack(spacing: 16) {
                        Text("Selected Photos (\(selectedImages.count))")
                            .font(Tokens.Typography.subtitle)
                            .foregroundColor(Tokens.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            Button(action: {
                                                selectedImages.remove(at: index)
                                                selectedItems.remove(at: index)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.white)
                                                    .background(Color.black.opacity(0.6))
                                                    .clipShape(Circle())
                                            }
                                            .padding(4),
                                            alignment: .topTrailing
                                        )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 20)
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        onPhotosSelected?(selectedImages)
                        isPresented = false
                    }) {
                        Text("Add to Story")
                            .font(Tokens.Typography.button)
                            .foregroundColor(Tokens.paper)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                                    .fill(
                                        LinearGradient(
                                            colors: Tokens.primaryOutlineGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                    }
                    .disabled(selectedImages.isEmpty)
                    .opacity(selectedImages.isEmpty ? 0.5 : 1.0)
                    
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("Cancel")
                            .font(Tokens.Typography.subtitle)
                            .foregroundColor(Tokens.ink.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                                    .fill(Tokens.bgWash)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                                            .stroke(Tokens.accentSoft.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Tokens.bgPrimary)
            .navigationBarHidden(true)
        }
        .onChange(of: selectedItems) { newItems in
            Task {
                selectedImages.removeAll()
                
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImages.append(image)
                    }
                }
            }
        }
    }
} 