import SwiftUI
import AVFoundation
import CoreData

struct MockMemoryEntry: Identifiable {
    let id: UUID
    let prompt: String
    let text: String?
    let audioURL: URL?
    let date: Date
    let tag: String
    let profileID: UUID
}

//struct ScrollOffsetKey: PreferenceKey {
//    static var defaultValue: CGFloat = 0
//    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
//        value = nextValue()
//    }
//}
//
//struct MemoryView: View {
//
//    @AppStorage("userBirthday") private var birthday: Date?
//    @State private var showBirthdayPrompt = false
//    @State private var selectedEntry: MockMemoryEntry?
//    @State private var zoomLevel: Double = 20
//    @State private var scrollOffset: CGFloat = 0
//    @State private var preserveMidAge: Int?
//    @State private var scrollProxyRef: ScrollViewProxy?
//
//    @EnvironmentObject var profileVM: ProfileViewModel // Access selected profile
//    @Environment(\.managedObjectContext) private var context // Add this to get the context from Core Data
//
//    // Declare FetchRequest at the property level
//    @FetchRequest(
//        entity: MemoryEntry.entity(),
//        sortDescriptors: [],
//        predicate: NSPredicate(format: "profileID == %@", "")
//    ) var entries: FetchedResults<MemoryEntry> // This will be populated dynamically with the selected profile
//
//    var currentAge: Int? {
//        guard let birthday else { return nil }
//        let age = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
//        return max(0, age)
//    }
//
//    var allAges: [Int] {
//        guard let age = currentAge else { return [] }
//        return Array(0...age)
//    }
//
//    var dotSpacing: CGFloat {
//        guard let age = currentAge else { return 20 }
//        let screenWidth = UIScreen.main.bounds.width
//        let minSpacing = screenWidth / CGFloat(age + 1)
//        let maxSpacing = screenWidth / 3
//        let progress = pow(zoomLevel / Double(age), 2.2)
//        return minSpacing + (maxSpacing - minSpacing) * CGFloat(progress)
//    }
//
//    var labelStep: Int {
//        switch Int(zoomLevel) {
//        case 0..<15: return 10
//        case 15..<35: return 5
//        case 35..<60: return 2
//        default: return 1
//        }
//    }
//
//    var body: some View {
//        NavigationStack {
//            VStack(spacing: 12) {
//                ZStack {
//                    Text("Memory Timeline")
//                        .font(.customSerifFallback(size: 30))
//                        .frame(maxWidth: .infinity, alignment: .center)
//                    HStack {
//                        Spacer()
//                        Button {
//                            showBirthdayPrompt = true
//                        } label: {
//                            Image(systemName: "birthday.cake.fill")
//                                .font(.title2)
//                                .foregroundColor(.orange)
//                        }
//                    }
//                }
//                .padding(.horizontal)
//
//                if allAges.isEmpty {
//                    Text("Let’s get started by adding your birthday.")
//                        .font(.body)
//                        .foregroundColor(.gray)
//                        .padding()
//                } else {
//                    ScrollViewReader { proxy in
//                        ScrollView(.horizontal, showsIndicators: false) {
//                            HStack(spacing: 0) {
//                                GeometryReader { geo in
//                                    Color.clear
//                                        .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minX)
//                                }
//                                .frame(width: 0, height: 0) // make it invisible, but it still tracks
//
//                                LifelineView(
//                                    allYears: allAges,
//                                    spacing: dotSpacing,
//                                    selectedEntry: $selectedEntry,
//                                    memoriesFor: memories,
//                                    colorForAge: colorForAge,
//                                    labelStep: labelStep
//                                )
//                                .frame(width: CGFloat(allAges.count) * dotSpacing, height: 100)
//                            }
//                        }
//                        .coordinateSpace(name: "scroll")
//                        .onPreferenceChange(ScrollOffsetKey.self) { value in
//                            scrollOffset = value
//                            let offset = -value
//                            let centerX = offset + UIScreen.main.bounds.width / 2
//                            let midAge = Int(centerX / dotSpacing)
//                            preserveMidAge = max(0, min(currentAge ?? 0, midAge))
//
//                            print("[DEBUG] scrollOffset =", scrollOffset)
//                            print("[DEBUG] dotSpacing =", dotSpacing)
//                            print("[DEBUG] centerX =", centerX)
//                            print("[DEBUG] Calculated Mid Age =", midAge)
//                        }
//
//                        .onAppear {
//                            scrollProxyRef = proxy
//                            if let age = currentAge {
//                                proxy.scrollTo(age, anchor: .center)
//                            }
//                        }
//                        .onChange(of: zoomLevel) { old, new in
//                            guard let mid = preserveMidAge else { return }
//                            print("[DEBUG ZOOM] zoomLevel changed to \(new), scrolling to \(mid)")
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
//                                scrollProxyRef?.scrollTo(mid, anchor: .center)
//                                print("[DEBUG] scrollOffset = \(scrollOffset)")
//                                print("[DEBUG] dotSpacing = \(dotSpacing)")
//                                print("[DEBUG] centerX = \(-scrollOffset + UIScreen.main.bounds.width / 2)")
//                            }
//                        }
//                    }
//                }
//
//                ScrollView(.horizontal, showsIndicators: false) {
//                    HStack(alignment: .top, spacing: 32) {
//                        ForEach(allAges, id: \.self) { age in
//                            VStack(spacing: 12) {
//                                ForEach(memories(for: age)) { memory in
//                                    MemoryCardView(memory: memory) {
//                                        selectedEntry = memory
//                                    }
//                                }
//                            }
//                            .frame(width: 220)
//                        }
//                    }
//                    .padding(.horizontal)
//                }
//
//                Spacer()
//            }
//            .overlay(
//                VStack(spacing: 4) {
//                    Text("Zoom Timeline View")
//                        .font(.footnote)
//                        .foregroundColor(.gray)
//                    HStack(spacing: 8) {
//                        Text("−")
//                            .font(.subheadline)
//                            .foregroundColor(.gray)
//                        let maxAge = max(currentAge ?? 0, 10)
//                        Slider(value: $zoomLevel, in: 0...Double(maxAge), step: 1)
//                            .accentColor(.orange)
//                            .frame(width: 160)
//                        Text("+")
//                            .font(.subheadline)
//                            .foregroundColor(.gray)
//                    }
//                }
//                .padding(.trailing, 20)
//                .padding(.bottom, 40),
//                alignment: .bottomTrailing
//            )
//            .sheet(item: $selectedEntry) { entry in
//                MemoryDetailView(entry: entry)
//            }
//            .sheet(isPresented: $showBirthdayPrompt) {
//                BirthdayOnboardingFlow()
//            }
//            .onAppear {
//                if birthday == nil {
//                    showBirthdayPrompt = true
//                }
//            }
//            .background(Color(red: 0.98, green: 0.94, blue: 0.86).ignoresSafeArea())
//        }
//    }
//
//    func colorForAge(_ age: Int) -> Color {
//        switch age {
//        case 0..<13: return .yellow
//        case 13..<20: return .orange
//        case 20..<35: return .red
//        case 35..<60: return .purple
//        default: return .blue
//        }
//    }
//
//    func formattedMonth(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "MMMM"
//        return formatter.string(from: date)
//    }
//
//    func memories(for age: Int) -> [MockMemoryEntry] {
//        guard let birthday else { return [] }
//        return entries.map { entry in
//            MockMemoryEntry(
//                id: entry.id!,
//                prompt: entry.prompt ?? "",
//                text: entry.text ?? "",
//                audioURL: entry.audioFileURL != nil ? URL(string: entry.audioFileURL!) : nil,
//                date: entry.createdAt ?? Date(),
//                tag: entry.chapter ?? ""
//            )
//        }.filter {
//            Calendar.current.dateComponents([.year], from: birthday, to: $0.date).year == age
//        }
//    }
//
//    func fetchEntries() {
//        guard let selectedProfileId = profileVM.selectedProfile.id.uuidString else { return }
//
//        let fetchRequest: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
//        fetchRequest.sortDescriptors = [] // Add any sort descriptors here
//        fetchRequest.predicate = NSPredicate(format: "profileID == %@", selectedProfileId)
//        
//        do {
//            try context.fetch(fetchRequest)
//        } catch {
//            print("Error fetching entries: \(error)")
//        }
//    }
//
//    // Call fetchEntries when view appears
//    .onAppear {
//        fetchEntries()
//    }
//}
//
//struct MemoryCardView: View {
//    let memory: MockMemoryEntry
//    let onSelect: () -> Void
//
//    var body: some View {
//        Button(action: onSelect) {
//            VStack(alignment: .leading, spacing: 6) {
//                Text(memory.prompt)
//                    .font(.subheadline)
//                    .foregroundColor(.black)
//                if let text = memory.text {
//                    Text(text)
//                        .font(.caption)
//                        .foregroundColor(.black.opacity(0.7))
//                        .lineLimit(2)
//                } else if memory.audioURL != nil {
//                    HStack(spacing: 4) {
//                        Image(systemName: "waveform")
//                        Text("Audio Memory")
//                    }
//                    .font(.caption)
//                    .foregroundColor(.gray)
//                }
//                Text(formattedMonth(memory.date))
//                    .font(.caption2)
//                    .foregroundColor(.black.opacity(0.5))
//            }
//            .padding()
//            .background(Color(red: 0.98, green: 0.93, blue: 0.80))
//            .cornerRadius(12)
//            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
//        }
//    }
//
//    func formattedMonth(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "MMMM"
//        return formatter.string(from: date)
//    }
//}
//
//struct MemoryDetailView: View {
//    let entry: MockMemoryEntry
//    @State private var player: AVAudioPlayer?
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            Text(entry.prompt)
//                .font(.customSerifFallback(size: 22))
//            if let text = entry.text {
//                Text(text)
//                    .font(.body)
//                    .foregroundColor(.black.opacity(0.9))
//            }
//            if let audioURL = entry.audioURL {
//                Button {
//                    playAudio(url: audioURL)
//                } label: {
//                    HStack {
//                        Image(systemName: "play.circle.fill")
//                        Text("Play Audio")
//                    }
//                    .font(.title3)
//                    .padding()
//                    .background(Color.orange.opacity(0.1))
//                    .cornerRadius(12)
//                }
//            }
//            Spacer()
//        }
//        .padding()
//        .background(Color(red: 0.98, green: 0.94, blue: 0.86).ignoresSafeArea())
//    }
//
//    func playAudio(url: URL) {
//        do {
//            player = try AVAudioPlayer(contentsOf: url)
//            player?.play()
//        } catch {
//            print("Error playing audio: \(error.localizedDescription)")
//        }
//    }
//}
