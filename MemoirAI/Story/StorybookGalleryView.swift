//
//  StorybookGalleryView.swift
//  MemoirAI
//
//  Created by user941803 on 7/4/25.
//


import SwiftUI

// Displays all previously generated storybooks for the currently selected profile.
struct StorybookGalleryView: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    @State private var books: [PersistableStorybook] = []
    @State private var selectedBook: PersistableStorybook?

    private let cols: [GridItem] = Array(repeating: .init(.flexible(), spacing: 16), count: 2)
    private let bgColor = Color(red: 0.98, green: 0.96, blue: 0.89)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            if books.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 56))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("No storybooks yet")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.black)
                    Text("Generate a book and it will appear here.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 20) {
                        ForEach(books.indices, id: \.self) { idx in
                            let book = books[idx]
                            BookCard(book: book)
                                .onTapGesture { selectedBook = book }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("My Storybooks")
        .onAppear { loadBooks() }
        .sheet(item: $selectedBook) { book in
            StorybookReaderView(book: book)
        }
    }

    private func loadBooks() {
        let key = "storybook_history_\(profileVM.selectedProfile.id.uuidString)"
        guard let arr = UserDefaults.standard.array(forKey: key) as? [Data] else {
            books = []
            return
        }
        let decoder = JSONDecoder()
        books = arr.compactMap { try? decoder.decode(PersistableStorybook.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

private struct BookCard: View {
    let book: PersistableStorybook
    private var cover: UIImage? {
        book.pageItems.compactMap { item in
            if let data = item.imageData { return UIImage(data: data) } else { return nil }
        }.first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let img = cover {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 140)
                    .clipped()
            } else {
                Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 140)
                    .overlay(Image(systemName: "photo").font(.largeTitle).foregroundColor(.gray))
            }
            Text(book.createdAt, style: .date)
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(book.artStyle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.9))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// Simple reader that shows each illustration page full-screen with swipe.
private struct StorybookReaderView: View, Identifiable {
    let id = UUID()
    let book: PersistableStorybook
    @Environment(\.dismiss) private var dismiss

    private var images: [UIImage] {
        book.pageItems.compactMap { item in
            if item.type == "illustration", let data = item.imageData { return UIImage(data: data) } else { return nil }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if images.isEmpty {
                Text("No pages found").foregroundColor(.white)
            } else {
                TabView {
                    ForEach(images.indices, id: \.self) { idx in
                        Image(uiImage: images[idx])
                            .resizable()
                            .scaledToFit()
                            .tag(idx)
                            .padding()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.8))
                    .padding()
            }
        }
    }
}

// Identifiable conformance so we can use sheet(item:)
extension PersistableStorybook: Identifiable {
    public var id: Date { createdAt }
} 