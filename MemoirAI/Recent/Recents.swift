import SwiftUI
import AVFoundation

struct RecentMemoriesView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)],
        animation: .easeInOut
    )
    private var entries: FetchedResults<MemoryEntry>

    @State private var audioPlayer: AVAudioPlayer?
    @State private var sortAscending = false
    @State private var showSortOptions = false

    var sortedEntries: [MemoryEntry] {
        entries.sorted {
            guard let date1 = $0.createdAt, let date2 = $1.createdAt else { return false }
            return sortAscending ? date1 < date2 : date1 > date2
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                if entries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.4))

                        Text("No memories yet")
                            .font(.customSerifFallback(size: 24))
                            .foregroundColor(.black.opacity(0.8))

                        Text("Start recording or writing your stories. They’ll appear here.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 120)
                } else {
                    List {
                        ForEach(sortedEntries) { entry in
                            MemoryCard(entry: entry)
                                .onTapGesture {
                                    if let urlString = entry.audioFileURL, let url = URL(string: urlString) {
                                        playAudio(from: url)
                                    }
                                }
                                .listRowInsets(EdgeInsets()) // Remove default padding
                                .listRowSeparator(.hidden)
                                .padding(.horizontal)
                                .padding(.top, 8)
                                .padding(.bottom, 12)
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
                }
            }
            .navigationTitle("Recent Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSortOptions.toggle()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .confirmationDialog("Sort Memories", isPresented: $showSortOptions, titleVisibility: .visible) {
                        Button("Newest to Oldest") {
                            sortAscending = false
                        }
                        Button("Oldest to Newest") {
                            sortAscending = true
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .background(Color(red: 1.0, green: 0.96, blue: 0.89).ignoresSafeArea())
        }
    }

    func delete(_ entry: MemoryEntry) {
        context.delete(entry)
        try? context.save()
    }

    func playAudio(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            print("🔊 Playing audio from \(url)")
        } catch {
            print("❌ Failed to play audio: \(error.localizedDescription)")
        }
    }
}

// MARK: - Card View
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

            if let createdAt = entry.createdAt {
                Text(createdAt, format: .dateTime.month().day().year().hour().minute())
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

// MARK: - Preview
struct RecentMemoriesView_Previews: PreviewProvider {
    static var previews: some View {
        RecentMemoriesView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
