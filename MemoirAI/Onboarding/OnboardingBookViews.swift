import SwiftUI
import UIKit

/// The same spread stays mounted while its camera moves between details.
struct OnboardingBookStage: View {
    let focus: OnboardingFlow.AlexFocus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: OnboardingFlow.AlexFocus = .cover
    @State private var coverAngle = 0.0
    private let paper = BookInteriorStyle.paper

    var body: some View {
        GeometryReader { proxy in
            let coverFitWidth = max(120, proxy.size.height - 32) / (8.5 / 22 * 1.65)
            let width = max(120, min(proxy.size.width - 32, coverFitWidth))
            let height = width * 8.5 / 22
            let scale = cameraScale
            let target = camera == .voice
                ? UnitPoint(x: (1 - 50.0 / 792) / 2, y: 0.10 + 52.0 / 612)
                : cameraTarget
            ZStack(alignment: .trailing) {
                FieldnotesMemoryPage(
                    title: "Dad’s old radio",
                    text: "Dad brought the radio to the kitchen table and asked me to hold the torch. I must have been about eight.",
                    pageNumber: 2, frameWidth: 792, frameHeight: 612
                )
                .scaleEffect(width / 2 / 792, anchor: .topLeading)
                .frame(width: width / 2, height: height, alignment: .topLeading)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 8)
                OnboardingTurningLeaf(angle: coverAngle, front: cover, back: illustration)
                    .frame(width: width / 2, height: height)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: height, alignment: .trailing)
            .scaleEffect(scale)
            .offset(x: (0.5 - target.x) * width * scale, y: (0.5 - target.y) * height * scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(red: 0.94, green: 0.92, blue: 0.88))
        .task(id: focus) { await moveCamera() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(focus == .cover ? "Alex’s memoir cover" : "Alex’s memory: a childhood afternoon fixing Dad’s old radio")
    }

    private var cameraScale: CGFloat {
        switch camera { case .cover: return 1.65; case .spread: return 1; case .illustration: return 1.8; case .voice: return 4.1; case .story: return 1.85 }
    }
    private var cameraTarget: UnitPoint {
        switch camera { case .cover: return UnitPoint(x: 0.75, y: 0.5); case .spread: return .center; case .illustration: return UnitPoint(x: 0.25, y: 0.5); case .voice: return UnitPoint(x: 0.9, y: 0.16); case .story: return UnitPoint(x: 0.75, y: 0.5) }
    }

    @MainActor private func moveCamera() async {
        if reduceMotion { camera = focus; coverAngle = focus == .cover ? 0 : -180; return }
        do {
            if focus == .cover {
                withAnimation(.easeInOut(duration: 0.7)) { camera = .cover; coverAngle = 0 }
                return
            }
            if camera == .cover {
                withAnimation(.timingCurve(0.32, 0.05, 0.2, 1, duration: 1.65)) { coverAngle = -180; camera = .spread }
                try await Task.sleep(for: .milliseconds(1850))
            } else if camera != .spread && camera != focus {
                withAnimation(.easeInOut(duration: 0.65)) { camera = .spread }
                try await Task.sleep(for: .milliseconds(850))
            }
            try Task.checkCancellation()
            withAnimation(.timingCurve(0.22, 0.75, 0.25, 1, duration: 0.95)) { camera = focus }
        } catch { /* A newer focus owns the next camera movement. */ }
    }

    private var cover: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                Image("AlexOnboardingMemory").resizable().scaledToFill()
                    .frame(width: 792, height: 306).clipped()
                VStack(alignment: .leading, spacing: 24) {
                    Text("ALEX MORGAN").font(.system(size: 18, weight: .semibold)).tracking(3).opacity(0.65)
                    Text("Alex’s memoir").font(.custom("Baskerville", size: 72))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }.padding(48).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 792, height: 612)
            .foregroundStyle(paper).background(Color(red: 0.31, green: 0.40, blue: 0.33))
            .overlay(alignment: .leading) {
                LinearGradient(colors: [.black.opacity(0.17), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 15)
            }
            .scaleEffect(proxy.size.width / 792, anchor: .topLeading)
        }
    }

    private var illustration: some View {
        OnboardingIllustrationPage(
            title: "Dad’s old radio", image: UIImage(named: "AlexOnboardingMemory"),
            memoryID: nil, audioURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/memoirai-7db06.firebasestorage.app/o/onboarding-demo%2Falex-sample-v2.mp3?alt=media&token=2f8bde1e-546a-4825-a18a-74172b896d88")
        )
        .overlay(alignment: .trailing) {
            LinearGradient(colors: [.clear, .black.opacity(0.12)], startPoint: .leading, endPoint: .trailing).frame(width: 8)
        }
    }
}

/// Front cover and illustrated reverse are two faces of one leaf, sharing one spine.
private struct OnboardingTurningLeaf<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        ZStack {
            front.opacity(angle > -90 ? 1 : 0)
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(angle <= -90 ? 1 : 0)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.25)
    }
}

struct OnboardingPersonalPages: View {
    let title: String
    let story: String
    let image: UIImage?
    let memoryID: UUID
    let hasAudio: Bool
    private var passages: [String] { OnboardingPagePagination.bookPages(story) }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                OnboardingIllustrationPage(
                    title: title, image: image, memoryID: hasAudio ? memoryID : nil, audioURL: nil
                )
                .aspectRatio(22.0 / 17.0, contentMode: .fit)
                .shadow(color: .black.opacity(0.09), radius: 15, y: 8)
                pageLabel("PAGE 1")
            }
            ForEach(Array(passages.enumerated()), id: \.offset) { index, passage in
                VStack(spacing: 10) {
                    GeometryReader { proxy in
                        FieldnotesMemoryPage(
                            title: title, text: passage, pageNumber: index + 2,
                            frameWidth: 792, frameHeight: 612
                        )
                        .scaleEffect(proxy.size.width / 792, anchor: .topLeading)
                    }
                    .aspectRatio(22.0 / 17.0, contentMode: .fit)
                    .background(BookInteriorStyle.paper)
                    .shadow(color: .black.opacity(0.09), radius: 15, y: 8)
                    pageLabel("PAGE \(index + 2)")
                }
            }
        }
        .foregroundStyle(BookInteriorStyle.ink)
    }

    private func pageLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 8, weight: .medium)).tracking(1.6).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }
}

/// Uses the same landscape illustration geometry and recording placement as exported books.
private struct OnboardingIllustrationPage: View {
    let title: String
    let image: UIImage?
    let memoryID: UUID?
    let audioURL: URL?

    var body: some View {
        GeometryReader { proxy in
            let layout = BookPageCanonicalLayout.illustration(isLandscape: true, isPrecomposed: false)
            ZStack(alignment: .topLeading) {
                BookInteriorStyle.paper
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 792 * layout.imageFrame.width, height: 612 * layout.imageFrame.height)
                        .clipped()
                        .offset(x: 792 * layout.imageFrame.x, y: 612 * layout.imageFrame.y)
                }
                if let titleFrame = layout.titleFrame {
                    Text(title).font(.custom("GillSans", size: 612 * 0.040))
                        .foregroundStyle(BookInteriorStyle.ink)
                        .lineLimit(2).minimumScaleFactor(0.6)
                        .frame(width: 792 * titleFrame.width, height: 612 * titleFrame.height, alignment: .leading)
                        .offset(x: 792 * titleFrame.x, y: 612 * titleFrame.y)
                }
                BookPageDocumentChrome(memoryID: memoryID, pageNumber: 1, isLandscape: true, isIllustration: true)
                if let audioURL {
                    Image(uiImage: QRCodeCache.image(for: audioURL.absoluteString, size: 420))
                        .interpolation(.none).resizable().frame(width: 60, height: 60)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .offset(x: 792 - 12 - 76, y: 612 * 0.10 + 14)
                }
            }
            .frame(width: 792, height: 612)
            .clipped()
            .scaleEffect(proxy.size.width / 792, anchor: .topLeading)
        }
    }
}

/// Pagination is measured in print points, so a smaller screen cannot add artificial pages.
enum OnboardingPagePagination {
    static func bookPages(_ story: String) -> [String] {
        let layout = BookPageCanonicalLayout.text(isLandscape: true, hasTitle: true, hasSubtitle: false)
        return pages(story, width: 792 * layout.bodyFrame.width, height: 612 * layout.bodyFrame.height - 1)
    }

    static func pages(_ story: String, width: CGFloat, height: CGFloat) -> [String] {
        guard !story.isEmpty else { return [""] }
        let font = UIFont(name: "Georgia", size: 612 * BookInteriorStyle.bodySize) ?? UIFont.systemFont(ofSize: 612 * BookInteriorStyle.bodySize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 612 * BookInteriorStyle.lineSpacing
        let attributed = NSAttributedString(string: story, attributes: [.font: font, .paragraphStyle: paragraph])
        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        var result: [String] = []
        var consumed = 0
        while consumed < storage.length {
            let container = NSTextContainer(size: CGSize(width: max(40, width), height: max(font.lineHeight + paragraph.lineSpacing, height)))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            let glyphs = manager.glyphRange(for: container)
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard characters.length > 0 else {
                result.append((story as NSString).substring(from: consumed))
                break
            }
            result.append((story as NSString).substring(with: characters))
            consumed = NSMaxRange(characters)
        }
        return result
    }
}
