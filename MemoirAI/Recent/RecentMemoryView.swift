import SwiftUI
import CoreData

struct RecentMemoriesView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel

    @State private var entries: [MemoryEntry] = []
    @State private var sortAscending = false
    @State private var showSortOptions = false

    // App's warm, cream background
    let backgroundColor = Color(red: 1.0, green: 0.96, blue: 0.89)

    // Sort entries by date
    var sortedEntries: [MemoryEntry] {
        entries.sorted {
            guard let d1 = $0.createdAt, let d2 = $1.createdAt else { return false }
            return sortAscending ? d1 < d2 : d1 > d2
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                backgroundColor.ignoresSafeArea()

                VStack {
                    if entries.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 48))
                                .foregroundColor(.gray.opacity(0.4))

                            Text("No memories yet")
                                .font(.customSerifFallback(size: 24))
                                .foregroundColor(.black.opacity(0.8))

                            Text("Start recording or writing your stories. They'll appear here.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 120)
                    } else {
                        // List of memories
                        List {
                            ForEach(sortedEntries) { entry in
                                NavigationLink(destination: MemoryDetailView(memory: entry)) {
                                    MemoryCard(entry: entry)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(backgroundColor)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .listRowBackground(backgroundColor)
                        .background(backgroundColor)
                        .padding(.horizontal, 0)
                    }
                }
                .navigationTitle("Recent Memories")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showSortOptions.toggle() } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .confirmationDialog("Sort Memories", isPresented: $showSortOptions, titleVisibility: .visible) {
                            Button("Newest to Oldest") { sortAscending = false }
                            Button("Oldest to Newest") { sortAscending = true }
                            Button("Cancel", role: .cancel) {}
                        }
                    }
                }
                .onAppear { fetchEntries(for: profileVM.selectedProfile.id) }
                .onChange(of: profileVM.selectedProfile.id) { newID in
                    print("🔄 Switched to profile: \(profileVM.selectedProfile.name ?? "Unnamed") (ID: \(newID))")
                    fetchEntries(for: newID)
                }
                .onReceive(NotificationCenter.default.publisher(for: .memorySaved)) { _ in
                    print("🟢 Memory saved, reloading for \(profileVM.selectedProfile.name ?? "Unnamed")")
                    fetchEntries(for: profileVM.selectedProfile.id)
                }
            }
        }
    }

    // MARK: - Data Operations
    private func fetchEntries(for profileID: UUID) {
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "profileID == %@", profileID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]

        do {
            entries = try context.fetch(request)
            print("📂 Fetched \(entries.count) memories for profile \(profileVM.selectedProfile.name ?? "Unnamed")")
        } catch {
            print("❌ Failed to fetch: \(error)")
        }
    }

    private func delete(_ entry: MemoryEntry) {
        context.delete(entry)
        try? context.save()
        fetchEntries(for: profileVM.selectedProfile.id)
    }
}

// MARK: - MemoryCard Preview
struct MemoryCard: View {
    let entry: MemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.prompt ?? "Untitled")
                    .font(.headline)
                    .foregroundColor(Color(red: 0.15, green: 0.25, blue: 0.18))

                Spacer()

                if entry.audioFileURL != nil {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundColor(.orange)
                } else if let text = entry.text, !text.isEmpty {
                    Image(systemName: "text.alignleft")
                        .foregroundColor(.blue)
                }
            }

            if let text = entry.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.black)
                    .lineLimit(3)
            }

            if let date = entry.createdAt {
                Text(date, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(red: 0.98, green: 0.93, blue: 0.80))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Notification
extension Notification.Name {
    static let memorySaved = Notification.Name("memorySaved")
}
