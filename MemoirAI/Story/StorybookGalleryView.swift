//
//  StorybookGalleryView.swift
//  MemoirAI
//
//  Created by user941803 on 7/4/25.
//


import SwiftUI

// MARK: - Filter and Sort Options
enum BookSortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    
    var id: String { rawValue }
}

enum BookStyleFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case realistic = "Realistic"
    case comic = "Comic"
    case kidsBook = "Kids"
    
    var id: String { rawValue }
    
    var symbolName: String {
        switch self {
        case .all: return "books.vertical"
        case .realistic: return "photo.artframe"
        case .comic: return "book.pages"
        case .kidsBook: return "book.closed.fill"
        }
    }
    
    func matches(artStyle: String) -> Bool {
        switch self {
        case .all:
            return true
        case .realistic:
            return artStyle.lowercased().contains("realistic")
        case .comic:
            return artStyle.lowercased().contains("comic")
        case .kidsBook:
            return artStyle.lowercased().contains("kid")
        }
    }
}

// Displays all previously generated storybooks for the currently selected profile.
struct StorybookGalleryView: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var allBooks: [BookVersionRecord] = []
    @State private var legacyBooksById: [String: PersistableStorybook] = [:]
    @State private var legacyCoverByBookId: [String: UIImage] = [:]
    @State private var selectedBook: BookVersionRecord?
    @State private var sortOrder: BookSortOrder = .newest
    @State private var styleFilter: BookStyleFilter = .all
    @State private var debugSessionID: String = String(UUID().uuidString.prefix(8))
    @State private var isLoadingBooks: Bool = true
    
    // Optional callback for when a book is selected (for loading into editor).
    // Passes (record, optional legacy PersistableStorybook for local-migration books with embedded imageData).
    var onBookSelected: ((BookVersionRecord, PersistableStorybook?) -> Void)?
    
    private enum Palette {
        static let background = Color(red: 0.975, green: 0.948, blue: 0.892)
        static let surface = Color.white.opacity(0.94)
        static let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
        static let primaryText = Color(red: 0.2, green: 0.2, blue: 0.2)
        static let secondaryText = Color(red: 0.46, green: 0.46, blue: 0.46)
        static let mutedStroke = Color.black.opacity(0.06)
    }

    private enum Metrics {
        static let screenPadding: CGFloat = 18
        static let gridSpacing: CGFloat = 16
        static let cardCorner: CGFloat = 20
        static let coverCorner: CGFloat = 14
    }
    
    // Computed filtered and sorted books
    private var filteredBooks: [BookVersionRecord] {
        let filtered = allBooks.filter { book in
            styleFilter.matches(artStyle: book.artStyle)
        }
        
        switch sortOrder {
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private var gridColumns: [GridItem] {
        let minimum = horizontalSizeClass == .compact ? 150.0 : 190.0
        return [GridItem(.adaptive(minimum: minimum, maximum: 260), spacing: Metrics.gridSpacing, alignment: .top)]
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                customHeader
                    .padding(.top, 8)
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, 6)

                filterPillsView
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, 12)

                if isLoadingBooks {
                    loadingStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredBooks.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: gridColumns, spacing: Metrics.gridSpacing) {
                            ForEach(filteredBooks) { book in
                                BookCardItem(
                                    book: book,
                                    legacyCoverImage: legacyCoverByBookId[book.bookVersionId],
                                    terracotta: Palette.terracotta,
                                    textPrimary: Palette.primaryText,
                                    textSecondary: Palette.secondaryText,
                                    cardColor: Palette.surface,
                                    cardCornerRadius: Metrics.cardCorner,
                                    coverCornerRadius: Metrics.coverCorner,
                                    onTap: {
                                        print("🧭 Gallery[\(debugSessionID)] card tapped: id=\(book.bookVersionId), source=\(book.source), pages=\(book.pageCount), style=\(book.artStyle)")
                                        if let callback = onBookSelected {
                                            let legacy = legacyBooksById[book.bookVersionId]
                                            print("🧭 Gallery[\(debugSessionID)] forwarding selection to StoryPage callback; legacyMatched=\(legacy != nil)")
                                            callback(book, legacy)
                                        } else {
                                            // Otherwise, use the old behavior (open reader)
                                            print("🧭 Gallery[\(debugSessionID)] opening standalone reader sheet")
                                            selectedBook = book
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.top, 4)
                        .padding(.bottom, 36)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            print("🧭 Gallery[\(debugSessionID)] onAppear; profile=\(profileVM.selectedProfile.id.uuidString)")
            Task {
                await loadBooks()
            }
        }
        .onDisappear {
            print("🧭 Gallery[\(debugSessionID)] onDisappear")
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookCoverBackfillComplete)) { note in
            guard let bookVersionId = note.userInfo?["bookVersionId"] as? String,
                  let updated = note.userInfo?["record"] as? BookVersionRecord else { return }
            if let idx = allBooks.firstIndex(where: { $0.bookVersionId == bookVersionId }) {
                allBooks[idx] = updated
            }
        }
        .sheet(item: $selectedBook) { book in
            StorybookReaderView(book: book)
        }
    }
    
    // MARK: - Custom Header
    private var customHeader: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 0) {
                circleIconButton(systemName: "chevron.left", action: {
                    print("🧭 Gallery[\(debugSessionID)] back button tapped")
                    dismiss()
                })
                Spacer()

                VStack(spacing: 2) {
                    Text("My Library")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundColor(Palette.primaryText)
                        .tracking(-0.7)

                    Text("\(filteredBooks.count) \(filteredBooks.count == 1 ? "book" : "books")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.secondaryText)
                }

                Spacer()

                Menu {
                    ForEach(BookSortOrder.allCases) { order in
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                sortOrder = order
                            }
                        }) {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    circleIconLabel(systemName: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func circleIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            circleIconLabel(systemName: systemName)
        }
    }

    private func circleIconLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Palette.primaryText.opacity(0.8))
            .frame(width: 42, height: 42)
            .background(
                Circle()
                    .fill(Palette.surface)
                    .overlay(
                        Circle()
                            .stroke(Palette.mutedStroke, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
            )
    }
    
    // MARK: - Filter Pills
    private var filterPillsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(BookStyleFilter.allCases) { filter in
                    FilterPillButton(
                        title: filter.rawValue,
                        icon: filter.symbolName,
                        isSelected: styleFilter == filter,
                        terracotta: Palette.terracotta,
                        textSecondary: Palette.secondaryText
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            styleFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.trailing, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Palette.mutedStroke, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Spacer()

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Palette.surface)
                .overlay(
                    Image(systemName: styleFilter == .all ? "books.vertical" : styleFilter.symbolName)
                        .font(.system(size: 42, weight: .regular))
                        .foregroundColor(Palette.terracotta.opacity(0.7))
                )
                .frame(width: 132, height: 132)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Palette.mutedStroke, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 5)

            VStack(spacing: 12) {
                Text(styleFilter == .all ? "No storybooks yet" : "No \(styleFilter.rawValue.lowercased()) books")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundColor(Palette.primaryText)

                Text(styleFilter == .all 
                     ? "Generate a book and it will appear here."
                     : "Try creating a \(styleFilter.rawValue.lowercased()) style book.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 80)
    }

    private var loadingStateView: some View {
        VStack(spacing: 18) {
            Spacer()

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Palette.surface)
                .overlay(
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Palette.terracotta)
                        .scaleEffect(1.25)
                )
                .frame(width: 132, height: 132)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Palette.mutedStroke, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 5)

            VStack(spacing: 10) {
                Text("Loading your library...")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundColor(Palette.primaryText)

                Text("Fetching your saved storybooks.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Palette.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 80)
    }

    @MainActor
    private func loadBooks() async {
        isLoadingBooks = true
        let profileID = profileVM.selectedProfile.id
        let cloudBooks = await FirestoreSyncService.shared.fetchBookVersions(profileID: profileID)
        print("🧭 Gallery[\(debugSessionID)] loadBooks profile=\(profileID.uuidString), cloudCount=\(cloudBooks.count)")
        
        // Always load local PersistableStorybooks for imageData fallback (file-backed + legacy migration)
        let localHistory = StorybookLocalStore.readHistoryDataArray(profileID: profileID)
        let decoder = JSONDecoder()
        let localBooks = localHistory.compactMap { try? decoder.decode(PersistableStorybook.self, from: $0) }
        var localByTimestamp: [Int: PersistableStorybook] = [:]
        for book in localBooks {
            localByTimestamp[Int(book.createdAt.timeIntervalSince1970)] = book
        }
        
        if !cloudBooks.isEmpty {
            allBooks = cloudBooks
            // Match cloud books to local PersistableStorybooks by timestamp
            var legacyMap: [String: PersistableStorybook] = [:]
            var coverMap: [String: UIImage] = [:]
            for book in cloudBooks {
                let ts = Int(book.createdAt.timeIntervalSince1970)
                if let local = localByTimestamp[ts] {
                    legacyMap[book.bookVersionId] = local
                    if let cover = legacyCoverImage(from: local) {
                        coverMap[book.bookVersionId] = cover
                    }
                }
            }
            legacyBooksById = legacyMap
            legacyCoverByBookId = coverMap
            print("🧭 Gallery[\(debugSessionID)] using cloud books; legacyMatches=\(legacyMap.count), coverFallbacks=\(coverMap.count)")
            isLoadingBooks = false
            return
        }
        
        // Local-only fallback (no cloud books)
        guard !localBooks.isEmpty else {
            allBooks = []
            legacyBooksById = [:]
            legacyCoverByBookId = [:]
            print("🧭 Gallery[\(debugSessionID)] no cloud or local books found")
            isLoadingBooks = false
            return
        }
        
        var legacyMap: [String: PersistableStorybook] = [:]
        var coverMap: [String: UIImage] = [:]
        allBooks = localBooks.map { legacy in
            let bookVersionId = "\(legacy.profileID.uuidString)_\(Int(legacy.createdAt.timeIntervalSince1970))_local"
            legacyMap[bookVersionId] = legacy
            if let cover = legacyCoverImage(from: legacy) {
                coverMap[bookVersionId] = cover
            }
            return BookVersionRecordFactory.fromPersistable(
                legacy,
                bookVersionId: bookVersionId,
                source: .localMigration
            )
        }
        legacyBooksById = legacyMap
        legacyCoverByBookId = coverMap
        print("🧭 Gallery[\(debugSessionID)] using local-only fallback books=\(allBooks.count)")
        isLoadingBooks = false
    }

    private func legacyCoverImage(from legacyBook: PersistableStorybook) -> UIImage? {
        guard let data = legacyBook.pageItems.first(where: { $0.type == "illustration" })?.imageData else {
            return nil
        }
        return UIImage(data: data)
    }
}

// MARK: - Filter Pill Button
private struct FilterPillButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let terracotta: Color
    let textSecondary: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected 
                          ? LinearGradient(
                              colors: [terracotta, terracotta.opacity(0.9)],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing
                          )
                          : LinearGradient(
                              colors: [Color.white.opacity(0.95), Color.white.opacity(0.88)],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing
                          )
                    )
                    .shadow(
                        color: isSelected ? terracotta.opacity(0.3) : Color.black.opacity(0.04),
                        radius: isSelected ? 8 : 4,
                        x: 0,
                        y: isSelected ? 4 : 2
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.clear : Color.black.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0)
    }
}

// MARK: - Book Card Item Component
private struct BookCardItem: View {
    let book: BookVersionRecord
    let legacyCoverImage: UIImage?
    let terracotta: Color
    let textPrimary: Color
    let textSecondary: Color
    let cardColor: Color
    let cardCornerRadius: CGFloat
    let coverCornerRadius: CGFloat
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    private var coverAspectRatio: CGFloat {
        let width = CGFloat(book.pageWidth)
        let height = CGFloat(book.pageHeight)
        if width > 0, height > 0 {
            return min(max(width / height, 0.68), 1.35)
        }
        let fallback = BookPrintSpec.forArtStyle(book.artStyle).aspectRatio
        return min(max(fallback, 0.68), 1.35)
    }

    private var trimLabel: String {
        if !book.trimSizeInches.isEmpty {
            return "\(book.trimSizeInches) in"
        }
        return book.orientation.lowercased() == "landscape" ? "11x8.5 in" : "8.5x11 in"
    }

    private var coverImageURL: URL? {
        let candidates: [String?] = [
            book.coverURL,
            book.pages.first(where: { $0.type == "illustration" })?.imageURL,
            book.pages.first(where: { $0.type == "illustration" })?.renderedPageURL
        ]
        for raw in candidates {
            guard let raw, let url = URL(string: raw) else { continue }
            if !isLikelyPDF(url) {
                return url
            }
        }
        return nil
    }

    private var coverPDFURL: URL? {
        book.printCoverPDFURL
    }

    private func isLikelyPDF(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return true
        }
        return url.absoluteString.lowercased().contains(".pdf")
    }
    
    // Format date nicely
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: book.createdAt)
    }
    
    // Art style display name
    private var styleDisplayName: String {
        if book.artStyle.lowercased().contains("realistic") {
            return "Realistic"
        } else if book.artStyle.lowercased().contains("comic") {
            return "Comic"
        } else if book.artStyle.lowercased().contains("kid") {
            return "Kids"
        }
        return "Classic"
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                coverView

                VStack(alignment: .leading, spacing: 6) {
                    Text(formattedDate)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Label("\(book.pageCount)", systemImage: "doc.text")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(textSecondary)

                        Text("•")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(textSecondary.opacity(0.45))

                        Text(styleDisplayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(terracotta)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: book.orientation.lowercased() == "landscape" ? "rectangle.split.2x1" : "rectangle.portrait")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(textSecondary.opacity(0.9))
                        Text(trimLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(textSecondary.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(cardColor)
                    .shadow(color: Color.black.opacity(0.07), radius: 11, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.985 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    private var coverView: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                ZStack {
                    if let legacyCoverImage {
                        Image(uiImage: legacyCoverImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else if let pdfURL = coverPDFURL {
                        RemotePDFThumbnailView(
                            url: pdfURL,
                            targetSize: CGSize(width: max(geo.size.width * 2, 120), height: max(geo.size.height * 2, 120)),
                            layout: book.coverFlatLayoutKind,
                            panel: .front,
                            cacheRevision: book.coverThumbnailCacheRevision
                        ) {
                            placeholderCover
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    } else if let url = coverImageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .empty:
                                ProgressView()
                                    .progressViewStyle(.circular)
                            default:
                                placeholderCover
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    } else {
                        placeholderCover
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .aspectRatio(coverAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: coverCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: coverCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )

            Text(styleDisplayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.58))
                )
                .padding(.top, 10)
                .padding(.leading, 12)
        }
    }

    private var placeholderCover: some View {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.94, blue: 0.90),
                Color(red: 0.92, green: 0.89, blue: 0.84)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            VStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(terracotta.opacity(0.45))
                Text("Cover Unavailable")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(textSecondary.opacity(0.7))
            }
        )
    }
}

// Full reader that shows all page types (illustrations, text pages, QR codes).
private struct StorybookReaderView: View, Identifiable {
    let id = UUID()
    let book: BookVersionRecord
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    @State private var showOrderSheet = false
    
    // Design tokens
    private let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    private let textPrimary = Color(red: 0.2, green: 0.2, blue: 0.2)
    private let textSecondary = Color(red: 0.5, green: 0.5, blue: 0.5)
    private let backgroundColor = Color(red: 0.12, green: 0.12, blue: 0.14)

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            if book.pages.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 56, weight: .thin))
                        .foregroundColor(.white.opacity(0.4))
                    Text("No pages found")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.white.opacity(0.15)))
                        }
                        
                        Spacer()
                        
                        Text("\(currentPage + 1) of \(book.pages.count)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Spacer()
                        
                        if book.renderStatus == "rendered", book.pdfURL != nil, book.coverURL != nil {
                            Button(action: { showOrderSheet = true }) {
                                Text("Order Print")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(terracotta)
                                    .clipShape(Capsule())
                            }
                        } else {
                            Color.clear.frame(width: 36, height: 36)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    
                    // Page content
                    TabView(selection: $currentPage) {
                        ForEach(book.pages.indices, id: \.self) { idx in
                            pageView(for: book.pages[idx], index: idx)
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    
                    // Custom page dots
                    if book.pages.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(0..<min(book.pages.count, 10), id: \.self) { idx in
                                Circle()
                                    .fill(currentPage == idx ? terracotta : Color.white.opacity(0.3))
                                    .frame(width: currentPage == idx ? 8 : 6, height: currentPage == idx ? 8 : 6)
                                    .animation(.spring(response: 0.3), value: currentPage)
                            }
                            if book.pages.count > 10 {
                                Text("...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showOrderSheet) {
            OrderBookView(book: book)
        }
    }
    
    /// Prefer JPEG `imageURL`, then pre-rendered PNG `renderedPageURL` (matches main book loader).
    private func illustrationDisplayURL(for item: BookVersionPageRecord) -> URL? {
        let candidates = [item.imageURL, item.renderedPageURL].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().contains(".pdf") }
        for raw in candidates {
            if let u = URL(string: raw) { return u }
        }
        return nil
    }

    @ViewBuilder
    private func pageView(for item: BookVersionPageRecord, index: Int) -> some View {
        switch item.type {
        case "illustration":
            // Image page with caption
            if let url = illustrationDisplayURL(for: item) {
                VStack(spacing: 20) {
                    Spacer()
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .empty:
                            ProgressView()
                        default:
                            Color.gray.opacity(0.2)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 10)
                    
                    // Caption if present
                    if let caption = item.textContent, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 32)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Image unavailable")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
        case "textPage":
            // Text/memory page - clean card design
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Page number badge
                    Text("Page \(item.pageIndex + 1) of \(max(1, book.pageCount))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(terracotta)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(terracotta.opacity(0.15))
                            )
                    
                    // Main text content
                    Text(item.textContent ?? "")
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundColor(textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(8)
                }
                .padding(28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.99, green: 0.98, blue: 0.96),
                                Color(red: 0.97, green: 0.95, blue: 0.92)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
        case "qrCode":
            // QR code page - clean modern design
            VStack(spacing: 28) {
                Spacer()
                
                // QR icon with glow
                ZStack {
                    Circle()
                        .fill(terracotta.opacity(0.15))
                        .frame(width: 140, height: 140)
                    
                    Image(systemName: "qrcode")
                        .font(.system(size: 64, weight: .thin))
                        .foregroundColor(terracotta)
                }
                
                VStack(spacing: 12) {
                    Text("Scan to Listen")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor(textPrimary)
                    
                    Text("This QR code links to the audio\nrecording of this memory")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                
                if let urlString = item.imageURL {
                    Text(urlString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(terracotta.opacity(0.8))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }
                
                Spacer()
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.99, green: 0.98, blue: 0.96),
                                Color(red: 0.97, green: 0.95, blue: 0.92)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
        default:
            VStack(spacing: 16) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundColor(.white.opacity(0.3))
                Text("Unknown page type")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

// Identifiable conformance so we can use sheet(item:)
extension PersistableStorybook: Identifiable {
    public var id: Date { createdAt }
} 