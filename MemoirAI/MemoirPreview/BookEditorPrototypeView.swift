import SwiftUI
import PhotosUI
import CoreData

struct BookEditorPrototypeView: View {
    let profileID: UUID
    @State private var pages: [EditorPage]
    @State private var currentPageIndex = 0
    @State private var showPhotoBank = false
    @State private var selectedPhoto: IdentifiableImage?
    @State private var photoPositions: [UUID: CGPoint] = [:]
    @State private var draggedPhoto: UUID?
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var availablePhotos: [PhotoItem] = []
    @State private var showSaveSuccess = false
    
    init(profileID: UUID, pages: [EditorPage]) {
        self.profileID = profileID
        self._pages = State(initialValue: pages)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Soft background
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.95, blue: 0.94),
                        Color(red: 0.91, green: 0.90, blue: 0.89)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Navigation header
                    HStack {
                        Button("Done") {
                            // Handle done action
                        }
                        .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("Page \(currentPageIndex + 1) of \(pages.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Save") {
                            savePhotoLayout()
                        }
                        .foregroundColor(.primary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                                    // Book view
                BookView(
                    pages: pages,
                    currentPageIndex: $currentPageIndex,
                    photoPositions: $photoPositions,
                    draggedPhoto: $draggedPhoto,
                    selectedPhoto: $selectedPhoto,
                    availablePhotos: availablePhotos
                )
                    .frame(maxHeight: geometry.size.height * 0.7)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    Spacer()
                    
                    // Photo bank section
                    PhotoBankSection(
                        showPhotoBank: $showPhotoBank,
                        availablePhotos: $availablePhotos,
                        photoPickerItems: $photoPickerItems,
                        selectedPhoto: $selectedPhoto
                    )
                    .frame(height: showPhotoBank ? 200 : 60)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showPhotoBank)
                }
            }
        }
        .onAppear {
            loadAvailablePhotos()
            loadSavedPhotoLayout()
        }
        .onChange(of: photoPickerItems) { _ in
            loadNewPhotos()
        }
        .sheet(item: $selectedPhoto) { identifiablePhoto in
            PhotoDetailView(photo: identifiablePhoto.image)
        }
        .alert("Layout Saved!", isPresented: $showSaveSuccess) {
            Button("OK") { }
        } message: {
            Text("Your photo layout has been saved successfully.")
        }
        .navigationBarHidden(true)
    }
    
    private func loadAvailablePhotos() {
        // Load photos from all memory entries
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "profileID == %@", profileID as CVarArg)
        
        do {
            let entries = try context.fetch(request)
            var photos: [PhotoItem] = []
            
            for entry in entries {
                if let photoSet = entry.photos as? Set<Photo> {
                    for photo in photoSet {
                        if let data = photo.data, let image = UIImage(data: data) {
                            photos.append(PhotoItem(id: photo.id ?? UUID(), image: image, sourceMemory: entry))
                        }
                    }
                }
            }
            
            availablePhotos = photos
        } catch {
            print("Error loading photos:", error)
        }
    }
    
    private func loadNewPhotos() {
        Task {
            for item in photoPickerItems {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    let newPhoto = PhotoItem(id: UUID(), image: image, sourceMemory: nil)
                    await MainActor.run {
                        availablePhotos.append(newPhoto)
                    }
                }
            }
            await MainActor.run {
                photoPickerItems.removeAll()
            }
        }
    }
    
    private func savePhotoLayout() {
        // Save photo positions to UserDefaults
        let layoutKey = "photoLayout_\(profileID.uuidString)"
        let layoutData = photoPositions.mapKeys { $0.uuidString }
        
        if let data = try? JSONEncoder().encode(layoutData) {
            UserDefaults.standard.set(data, forKey: layoutKey)
        }
        
        // Show success feedback
        showSaveSuccess = true
    }
    
    private func loadSavedPhotoLayout() {
        let layoutKey = "photoLayout_\(profileID.uuidString)"
        
        if let data = UserDefaults.standard.data(forKey: layoutKey),
           let layoutData = try? JSONDecoder().decode([String: CGPoint].self, from: data) {
            photoPositions = layoutData.mapKeys { UUID(uuidString: $0) ?? UUID() }
        }
    }
}

// MARK: - Photo Item Model
struct PhotoItem: Identifiable {
    let id: UUID
    let image: UIImage
    let sourceMemory: MemoryEntry?
}

// MARK: - Book View
struct BookView: View {
    let pages: [EditorPage]
    @Binding var currentPageIndex: Int
    @Binding var photoPositions: [UUID: CGPoint]
    @Binding var draggedPhoto: UUID?
    @Binding var selectedPhoto: IdentifiableImage?
    let availablePhotos: [PhotoItem]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Book background
                BookBackground()
                
                // Page content
                TabView(selection: $currentPageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        BookPageView(
                            page: page,
                            pageIndex: index,
                            photoPositions: $photoPositions,
                            draggedPhoto: $draggedPhoto,
                            selectedPhoto: $selectedPhoto,
                            availablePhotos: availablePhotos
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Navigation arrows
                if pages.count > 1 {
                    HStack {
                        Button(action: previousPage) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .padding(12)
                                .background(.regularMaterial, in: Circle())
                                .shadow(radius: 4)
                        }
                        .disabled(currentPageIndex == 0)
                        .opacity(currentPageIndex == 0 ? 0.3 : 1.0)
                        
                        Spacer()
                        
                        Button(action: nextPage) {
                            Image(systemName: "chevron.right")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .padding(12)
                                .background(.regularMaterial, in: Circle())
                                .shadow(radius: 4)
                        }
                        .disabled(currentPageIndex == pages.count - 1)
                        .opacity(currentPageIndex == pages.count - 1 ? 0.3 : 1.0)
                    }
                    .padding(.horizontal, 32)
                }
            }
        }
    }
    
    private func previousPage() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            currentPageIndex = max(0, currentPageIndex - 1)
        }
    }
    
    private func nextPage() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            currentPageIndex = min(pages.count - 1, currentPageIndex + 1)
        }
    }
}

// MARK: - Book Background
struct BookBackground: View {
    var body: some View {
        ZStack {
            // Book shadow
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.15))
                .offset(x: 6, y: 8)
                .blur(radius: 8)
            
            // Book cover
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.27, blue: 0.07),
                            Color(red: 0.63, green: 0.32, blue: 0.18),
                            Color(red: 0.40, green: 0.26, blue: 0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.black.opacity(0.1), lineWidth: 1)
                )
            
            // Page stack effect
            ForEach(0..<6) { i in
                let offset = CGFloat(i) * 1.5
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.98),
                                Color.white.opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .offset(x: offset, y: CGFloat(i) * -1.5)
                    .shadow(color: .black.opacity(i % 2 == 0 ? 0.08 : 0.04), radius: 2, x: 1, y: 1)
            }
        }
    }
}

// MARK: - Book Page View
struct BookPageView: View {
    let page: EditorPage
    let pageIndex: Int
    @Binding var photoPositions: [UUID: CGPoint]
    @Binding var draggedPhoto: UUID?
    @Binding var selectedPhoto: IdentifiableImage?
    let availablePhotos: [PhotoItem]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Page background
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.96, blue: 0.94),
                                Color(red: 0.96, green: 0.94, blue: 0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.black.opacity(0.05), lineWidth: 0.5)
                    )
                
                // Page content
                VStack(spacing: 16) {
                    // Title
                    if let title = page.title, !title.isEmpty {
                        Text(title)
                            .font(.custom("Georgia", size: 18).weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(red: 0.17, green: 0.24, blue: 0.31))
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                    }
                    
                    // Existing photo from memory
                    if let existingPhoto = page.photoUIImage {
                        Image(uiImage: existingPhoto)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            .padding(.horizontal, 24)
                    }
                    
                    // Text content
                    ScrollView {
                        Text(page.bodyText)
                            .font(.custom("Georgia", size: 14))
                            .lineSpacing(4)
                            .foregroundColor(Color(red: 0.17, green: 0.24, blue: 0.31))
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    }
                    
                    Spacer()
                }
                
                // Dragged photos on this page
                ForEach(Array(photoPositions.keys), id: \.self) { photoId in
                    if let position = photoPositions[photoId],
                       let photo = getPhotoById(photoId) {
                        DraggablePhotoView(
                            photo: photo,
                            position: position,
                            isDragging: draggedPhoto == photoId
                        )
                        .onTapGesture {
                            selectedPhoto = IdentifiableImage(image: photo.image)
                        }
                        .onDrag {
                            draggedPhoto = photoId
                            return NSItemProvider(object: photoId.uuidString as NSString)
                        }
                        .onLongPressGesture {
                            // Remove photo from page
                            photoPositions.removeValue(forKey: photoId)
                        }
                    }
                }
                
                // Help text when no photos
                if photoPositions.isEmpty {
                    VStack {
                        Spacer()
                        Text("Drag photos from the photo bank below to add them to this page")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                        Spacer()
                    }
                }
                
                // Drop zone for photos
                Color.clear
                    .contentShape(Rectangle())
                    .onDrop(of: [.text], delegate: PhotoDropDelegate(
                        photoPositions: $photoPositions,
                        draggedPhoto: $draggedPhoto,
                        pageId: page.id,
                        availablePhotos: availablePhotos
                    ))
                    .overlay(
                        // Grid lines for visual reference
                        GridOverlay()
                            .opacity(0.1)
                    )
            }
        }
    }
    
    private func getPhotoById(_ id: UUID) -> PhotoItem? {
        return availablePhotos.first { $0.id == id }
    }
}

// MARK: - Draggable Photo View
struct DraggablePhotoView: View {
    let photo: PhotoItem
    let position: CGPoint
    let isDragging: Bool
    
    var body: some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFit()
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(isDragging ? 0.3 : 0.1), radius: isDragging ? 8 : 4)
            .scaleEffect(isDragging ? 1.1 : 1.0)
            .opacity(isDragging ? 0.8 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDragging ? Color.blue : Color.clear, lineWidth: 2)
            )
            .position(position)
    }
}

// MARK: - Photo Drop Delegate
struct PhotoDropDelegate: DropDelegate {
    @Binding var photoPositions: [UUID: CGPoint]
    @Binding var draggedPhoto: UUID?
    let pageId: UUID
    let availablePhotos: [PhotoItem]
    
    func performDrop(info: DropInfo) -> Bool {
        // Handle dragged photo from page
        if let draggedPhoto = draggedPhoto {
            // Check if the photo exists in available photos
            guard availablePhotos.contains(where: { $0.id == draggedPhoto }) else { return false }
            
            // Snap to grid for better organization
            let snappedLocation = snapToGrid(info.location)
            photoPositions[draggedPhoto] = snappedLocation
            self.draggedPhoto = nil
            return true
        }
        
        // Handle new photo from photo bank
        guard let itemProvider = info.itemProviders(for: [.text]).first else { return false }
        
        itemProvider.loadObject(ofClass: NSString.self) { string, error in
            DispatchQueue.main.async {
                if let photoIdString = string as? String,
                   let photoId = UUID(uuidString: photoIdString),
                   availablePhotos.contains(where: { $0.id == photoId }) {
                    let snappedLocation = self.snapToGrid(info.location)
                    photoPositions[photoId] = snappedLocation
                }
            }
        }
        
        return true
    }
    
    private func snapToGrid(_ location: CGPoint) -> CGPoint {
        let gridSize: CGFloat = 100 // Grid spacing
        let x = round(location.x / gridSize) * gridSize
        let y = round(location.y / gridSize) * gridSize
        return CGPoint(x: x, y: y)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Photo Bank Section
struct PhotoBankSection: View {
    @Binding var showPhotoBank: Bool
    @Binding var availablePhotos: [PhotoItem]
    @Binding var photoPickerItems: [PhotosPickerItem]
    @Binding var selectedPhoto: IdentifiableImage?
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    
    var body: some View {
        VStack(spacing: 0) {
            // Photo bank button
            Button(action: {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showPhotoBank.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20))
                    Text("Photo Bank")
                        .font(.headline)
                    Spacer()
                    Image(systemName: showPhotoBank ? "chevron.down" : "chevron.up")
                        .font(.system(size: 16))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.regularMaterial)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Photo grid
            if showPhotoBank {
                VStack(spacing: 12) {
                    // Add new photos button
                    PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 10, matching: .images) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                            Text("Add Photos")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Photo grid
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(availablePhotos) { photo in
                                PhotoGridItem(photo: photo, selectedPhoto: $selectedPhoto)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(maxHeight: 120)
                }
                .padding(.bottom, 16)
            }
        }
        .background(.regularMaterial)
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Photo Grid Item
struct PhotoGridItem: View {
    let photo: PhotoItem
    @Binding var selectedPhoto: IdentifiableImage?
    
    var body: some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFill()
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .onTapGesture {
                selectedPhoto = IdentifiableImage(image: photo.image)
            }
            .onDrag {
                return NSItemProvider(object: photo.id.uuidString as NSString)
            }
    }
}

// MARK: - Photo Detail View
struct PhotoDetailView: View {
    let photo: UIImage
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .padding()
                
                Spacer()
            }
            .navigationTitle("Photo Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Grid Overlay
struct GridOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let gridSize: CGFloat = 100
                
                // Vertical lines
                for x in stride(from: 0, through: geometry.size.width, by: gridSize) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
                
                // Horizontal lines
                for y in stride(from: 0, through: geometry.size.height, by: gridSize) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(Color.gray, lineWidth: 0.5)
        }
    }
}

// MARK: - Dictionary Extension
extension Dictionary {
    func mapKeys<T>(_ transform: (Key) -> T) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[transform(key)] = value
        }
        return result
    }
}

// MARK: - UIImage Wrapper for Identifiable
struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
