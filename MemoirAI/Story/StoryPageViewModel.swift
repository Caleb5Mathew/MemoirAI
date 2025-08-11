import Foundation
import SwiftUI
import CoreData
import CoreImage.CIFilterBuiltins
import PDFKit
import UIKit

struct PersistablePageItem: Codable {
    let type: String // "illustration", "textPage", "qrCode"
    let imageData: Data?
    let caption: String?
    let textContent: String?
    let url: String?
    let pageIndex: Int?
    let totalPages: Int?
}

struct PersistableStorybook: Codable {
    let profileID: UUID
    let pageItems: [PersistablePageItem]
    let artStyle: String
    let createdAt: Date
}

@MainActor
class StoryPageViewModel: ObservableObject {

    enum PageItem {
        case illustration(image: UIImage, caption: String)
        case textPage(index: Int, total: Int, body: String)
        case qrCode(id: UUID, url: URL)
    }

    @Published var isLoading      : Bool = false
    @Published var errorMessage   : String?
    @Published var images         : [UIImage] = []
    @Published var progress       : Double    = 0
    @Published var pageItems      : [PageItem] = []

    @Published var subjectPhoto   : UIImage?
    @Published var subjectPhotoID : String?
    @Published var styleTile      : UIImage?
    @Published var styleTileID    : String?
    private  var subjectPhotoJPEG : Data?

    @AppStorage("memoirPageCount")          private var pageCountSetting      = 2
    @AppStorage("memoirArtStyle")           private var artStyleRaw           = ArtStyle.realistic.rawValue
    @AppStorage("memoirCustomArtStyleText") private var customArtStyleText    = ""
    @AppStorage("memoirEthnicity")          private var ethnicity             = ""
    @AppStorage("memoirGender")             private var gender                = ""
    @AppStorage("memoirOtherPersonalDetails") private var otherDetails        = ""
    
    // iCloud backup for critical settings
    private func backupSettingsToCloud() {
        NSUbiquitousKeyValueStore.default.set(pageCountSetting, forKey: "memoir_pageCount")
        NSUbiquitousKeyValueStore.default.set(artStyleRaw, forKey: "memoir_artStyle")
        NSUbiquitousKeyValueStore.default.set(customArtStyleText, forKey: "memoir_customArtStyleText")
        NSUbiquitousKeyValueStore.default.set(ethnicity, forKey: "memoir_ethnicity")
        NSUbiquitousKeyValueStore.default.set(gender, forKey: "memoir_gender")
        NSUbiquitousKeyValueStore.default.set(otherDetails, forKey: "memoir_otherPersonalDetails")
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    private func restoreSettingsFromCloud() {
        NSUbiquitousKeyValueStore.default.synchronize()
        
        let cloudPageCount = NSUbiquitousKeyValueStore.default.integer(forKey: "memoir_pageCount")
        if cloudPageCount > 0 {
            pageCountSetting = cloudPageCount
        }
        
        let cloudArtStyle = NSUbiquitousKeyValueStore.default.string(forKey: "memoir_artStyle")
        if let artStyle = cloudArtStyle, !artStyle.isEmpty {
            artStyleRaw = artStyle
        }
        
        let cloudCustomStyle = NSUbiquitousKeyValueStore.default.string(forKey: "memoir_customArtStyleText")
        if let customStyle = cloudCustomStyle {
            customArtStyleText = customStyle
        }
        
        let cloudEthnicity = NSUbiquitousKeyValueStore.default.string(forKey: "memoir_ethnicity")
        if let ethnicity = cloudEthnicity {
            self.ethnicity = ethnicity
        }
        
        let cloudGender = NSUbiquitousKeyValueStore.default.string(forKey: "memoir_gender")
        if let gender = cloudGender {
            self.gender = gender
        }
        
        let cloudOtherDetails = NSUbiquitousKeyValueStore.default.string(forKey: "memoir_otherPersonalDetails")
        if let otherDetails = cloudOtherDetails {
            self.otherDetails = otherDetails
        }
    }
    
    // NEW: Persistent storage for generated storybooks per profile
    @Published var hasGeneratedStorybook: Bool = false
    private var currentProfileID: UUID?

    // Make currentArtStyle public so StoryPage can access it
    var currentArtStyle : ArtStyle { ArtStyle(rawValue: artStyleRaw) ?? .realistic }
    private var faceDescription : String?

    private let promptGen : PromptGenerator
    private let imageCtx  : ImageContext
    private let imageSvc  : OpenAIImageService
    private let openAIKey : String

    // Toggle to bypass expensive LLM sanitization if it's over-sanitising prompts.
    private let useLLMSanitizer = false

    init() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
              !key.isEmpty, !key.contains("YOUR_API") else {
            fatalError("OPENAI_API_KEY missing or invalid")
        }
        openAIKey = key
        promptGen = PromptGenerator(apiKey: key)
        imageCtx  = ImageContext(apiKey: key)
        imageSvc  = OpenAIImageService(apiKey: key)
        
        // Restore settings from iCloud backup
        restoreSettingsFromCloud()
    }

    func expectedPageCount() -> Int { pageCountSetting }
    var  styleTilePublic: UIImage? { styleTile }
    
    // Backup settings when they change
    private func backupSettingsIfNeeded() {
        backupSettingsToCloud()
    }
    
    // NEW: Load persisted storybook for a profile
    func loadStorybookForProfile(_ profileID: UUID) {
        currentProfileID = profileID
        loadPersistedStorybook(for: profileID)
    }
    
    // NEW: Clear current storybook (for regeneration)
    func clearCurrentStorybook() {
        pageItems.removeAll()
        images.removeAll()
        hasGeneratedStorybook = false
        errorMessage = nil
        
        // Clear persisted data for current profile
        if let profileID = currentProfileID {
            clearPersistedStorybook(for: profileID)
        }
    }
    
    // NEW: Download storybook as PDF – pixel-perfect snapshot of SwiftUI pages
    func downloadStorybook() -> URL? {
        guard !pageItems.isEmpty else { return nil }

        // 1. Decide a render size consistent with on-screen look
        let bookWidth: CGFloat = 768
        let isKids = currentArtStyle == .kidsBook
        let aspect: CGFloat = isKids ? (9.0/16.0) : (4.0/3.0)
        let bookHeight: CGFloat = bookWidth * aspect

        let pdfBounds = CGRect(x: 0, y: 0, width: bookWidth, height: bookHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pdfBounds)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("MemoirAI_Storybook_\(Date().timeIntervalSince1970).pdf")

        do {
            try renderer.writePDF(to: url) { ctx in
                for (idx, item) in pageItems.enumerated() {
                    ctx.beginPage(withBounds: pdfBounds, pageInfo: [:])

                    // Build the same SwiftUI view used on-screen
                    let view: AnyView
                    switch item {
                    case .illustration(let image, let caption):
                        if isKids {
                            view = AnyView(KidsBookIllustrationPage(
                                image: image,
                                caption: caption,
                                frameWidth: bookWidth,
                                frameHeight: bookHeight,
                                pageNumber: idx + 1))
                        } else {
                            view = AnyView(VerticalBookIllustrationPage(
                                image: image,
                                caption: caption,
                                frameWidth: bookWidth,
                                frameHeight: bookHeight,
                                pageNumber: idx + 1,
                                totalPages: pageItems.count))
                        }
                    case .textPage(let pIdx, let total, let body):
                        if isKids {
                            view = AnyView(KidsBookTextPage(
                                index: pIdx,
                                total: total,
                                text: body,
                                frameWidth: bookWidth,
                                frameHeight: bookHeight,
                                pageNumber: idx + 1))
                        } else {
                            view = AnyView(VerticalBookTextPage(
                                index: pIdx,
                                total: total,
                                text: body,
                                frameWidth: bookWidth,
                                frameHeight: bookHeight,
                                pageNumber: idx + 1))
                        }
                    case .qrCode(_, let url):
                        view = AnyView(EnhancedQRCodePage(
                            url: url,
                            frameWidth: bookWidth,
                            frameHeight: bookHeight,
                            pageNumber: idx + 1,
                            isKidsBook: isKids))
                    }

                    // Snapshot & draw full-bleed
                    let img = view.snapshot(width: bookWidth, height: bookHeight)
                    img.draw(in: pdfBounds)
                }
            }
            return url
        } catch {
            print("❌ Failed to create PDF: \(error)")
            return nil
        }
    }
    
    private func persistStorybook(for profileID: UUID) {
        guard !pageItems.isEmpty else { return }
        
        let encoder = JSONEncoder()
        do {
            // Convert PageItems to a persistable format
            let persistableItems = pageItems.map { item -> PersistablePageItem in
                switch item {
                case .illustration(let image, let caption):
                    return PersistablePageItem(
                        type: "illustration",
                        imageData: image.jpegData(compressionQuality: 0.8),
                        caption: caption,
                        textContent: nil,
                        url: nil,
                        pageIndex: nil,
                        totalPages: nil
                    )
                case .textPage(let index, let total, let body):
                    return PersistablePageItem(
                        type: "textPage",
                        imageData: nil,
                        caption: nil,
                        textContent: body,
                        url: nil,
                        pageIndex: index,
                        totalPages: total
                    )
                case .qrCode(_, let url):
                    return PersistablePageItem(
                        type: "qrCode",
                        imageData: nil,
                        caption: nil,
                        textContent: nil,
                        url: url.absoluteString,
                        pageIndex: nil,
                        totalPages: nil
                    )
                }
            }
            
            let storybookData = PersistableStorybook(
                profileID: profileID,
                pageItems: persistableItems,
                artStyle: artStyleRaw,
                createdAt: Date()
            )
            
            let data = try encoder.encode(storybookData)
            // Overwrite the "current" key for quick resume
            UserDefaults.standard.set(data, forKey: "storybook_\(profileID.uuidString)")

            // 🔄 Append to history array so multiple books are saved
            let historyKey = "storybook_history_\(profileID.uuidString)"
            var historyDataArray: [Data] = UserDefaults.standard.array(forKey: historyKey) as? [Data] ?? []
            historyDataArray.append(data)
            UserDefaults.standard.set(historyDataArray, forKey: historyKey)

            hasGeneratedStorybook = true
            
            print("✅ Storybook persisted for profile: \(profileID)")
        } catch {
            print("❌ Failed to persist storybook: \(error)")
        }
    }
    
    private func loadPersistedStorybook(for profileID: UUID) {
        guard let data = UserDefaults.standard.data(forKey: "storybook_\(profileID.uuidString)") else {
            hasGeneratedStorybook = false
            return
        }
        
        let decoder = JSONDecoder()
        do {
            let storybookData = try decoder.decode(PersistableStorybook.self, from: data)
            
            // Convert back to PageItems
            pageItems = storybookData.pageItems.compactMap { persistableItem in
                switch persistableItem.type {
                case "illustration":
                    guard let imageData = persistableItem.imageData,
                          let image = UIImage(data: imageData),
                          let caption = persistableItem.caption else { return nil }
                    return PageItem.illustration(image: image, caption: caption)
                    
                case "textPage":
                    guard let textContent = persistableItem.textContent else { return nil }
                    return PageItem.textPage(
                        index: persistableItem.pageIndex ?? 1,
                        total: persistableItem.totalPages ?? 1,
                        body: textContent
                    )
                    
                case "qrCode":
                    guard let urlString = persistableItem.url,
                          let url = URL(string: urlString) else { return nil }
                    return PageItem.qrCode(id: UUID(), url: url)
                    
                default:
                    return nil
                }
            }
            
            // Extract images for the images array
            images = pageItems.compactMap { item in
                if case .illustration(let image, _) = item {
                    return image
                }
                return nil
            }
            
            hasGeneratedStorybook = true
            print("✅ Storybook loaded for profile: \(profileID)")
        } catch {
            print("❌ Failed to load persisted storybook: \(error)")
            hasGeneratedStorybook = false
        }
    }
    
    private func clearPersistedStorybook(for profileID: UUID) {
        UserDefaults.standard.removeObject(forKey: "storybook_\(profileID.uuidString)")
        print("🗑️ Cleared persisted storybook for profile: \(profileID)")
    }
    
    private func ensureSubjectPhotoIsRegistered() async {
        guard subjectPhotoID == nil, let shot = subjectPhoto else { return }
        do {
            let (fid, jpeg) = try await imageCtx.createReference(from: shot)
            subjectPhotoID   = fid
            subjectPhotoJPEG = jpeg
            print("✅ head-shot uploaded →", fid)
        } catch {
            print("🚫 head-shot upload failed:", error.localizedDescription)
        }
    }

    private func ensureFaceDescription() async {
        guard faceDescription == nil,
              let fid = subjectPhotoID else { return }
        do {
            faceDescription = try await imageCtx.faceDescriptor(
                fileID: fid,
                jpegData: subjectPhotoJPEG,
                race: self.ethnicity,
                gender: self.gender
            )
            
            if let desc = faceDescription {
                print("✅ face descriptor →", desc)
            } else {
                print("⚠️ Face descriptor was nil after successful API call.")
            }
        } catch {
            print("🚫 face descriptor failed:", error.localizedDescription)
            faceDescription = nil
        }
    }

    private let traitOpposites: [String : [String]] = [
        "light skin": ["dark brown skin", "very dark skin"], "pale skin": ["medium-brown skin", "dark skin"],
        "fair skin": ["brown skin", "dark skin"], "dark skin": ["pale caucasian skin", "light skin"],
        "brown skin": ["very light skin", "pale skin"], "blond hair": ["jet-black hair", "dark-brown hair"],
        "light-blond hair": ["black hair", "dark-brown hair"], "brown hair": ["blond hair", "jet-black hair"],
        "black hair": ["light-blond hair", "gray hair"], "gray hair": ["blond hair", "black hair", "vibrant red hair"],
        "straight texture": ["tight coils", "kinky curly texture"], "wavy texture": ["pin-straight hair"],
        "curly texture": ["pin-straight hair"], "tight coils": ["straight texture"], "male": ["female presentation"],
        "female": ["male presentation"]
    ]

    // Enhanced race descriptor mapping with more accurate translations
    private let raceDescriptorMap: [String: String] = [
        // South Asian descriptors - more specific for Indian
        "indian": "warm brown skin, expressive dark eyes, straight dark hair",
        "south asian": "warm brown skin, expressive dark eyes, straight dark hair",
        "pakistani": "warm brown skin, expressive dark eyes, straight dark hair",
        "bengali": "warm brown skin, expressive dark eyes, straight dark hair",
        "tamil": "warm brown skin, expressive dark eyes, straight dark hair",
        
        // East Asian descriptors
        "asian": "light brown skin, dark almond-shaped eyes, straight black hair",
        "east asian": "light brown skin, dark almond-shaped eyes, straight black hair",
        "chinese": "light brown skin, dark almond-shaped eyes, straight black hair",
        "japanese": "light brown skin, dark almond-shaped eyes, straight black hair",
        "korean": "light brown skin, dark almond-shaped eyes, straight black hair",
        
        // Other descriptors
        "hispanic": "warm olive skin, expressive brown eyes, dark wavy hair",
        "latino": "warm olive skin, expressive brown eyes, dark wavy hair",
        "mexican": "warm olive skin, expressive brown eyes, dark wavy hair",
        "black": "rich dark skin, expressive brown eyes, textured dark hair",
        "african american": "rich dark skin, expressive brown eyes, textured dark hair",
        "african": "rich dark skin, expressive brown eyes, textured dark hair",
        "caucasian": "fair skin, varied eye color, straight to wavy hair",
        "white": "fair skin, varied eye color, straight to wavy hair",
        "european": "fair skin, varied eye color, straight to wavy hair",
        "middle eastern": "olive skin, expressive dark eyes, dark hair",
        "arabic": "olive skin, expressive dark eyes, dark hair",
        "persian": "olive skin, expressive dark eyes, dark hair",
        "native american": "bronze skin, dark eyes, long dark hair",
        "indigenous": "bronze skin, dark eyes, long dark hair",
        "mixed": "unique features, expressive eyes, distinctive hair texture",
        "biracial": "unique features, expressive eyes, distinctive hair texture"
    ]

    private func translateRaceToDescriptor(_ text: String) -> String {
        var translated = text
        let lowercaseText = text.lowercased()
        
        for (race, descriptor) in raceDescriptorMap {
            // Create patterns for more comprehensive matching
            let patterns = [
                race,
                "\(race) heritage",
                "\(race) background",
                "\(race) ancestry",
                "\(race) ethnicity",
                "of \(race) descent",
                "\(race) features",
                "\(race) appearance"
            ]
            
            for pattern in patterns {
                if lowercaseText.contains(pattern) {
                    translated = translated.replacingOccurrences(
                        of: pattern,
                        with: descriptor,
                        options: .caseInsensitive
                    )
                }
            }
        }
        
        // Also handle some common problematic phrases
        translated = translated.replacingOccurrences(of: "race", with: "features", options: .caseInsensitive)
        translated = translated.replacingOccurrences(of: "ethnicity", with: "appearance", options: .caseInsensitive)
        translated = translated.replacingOccurrences(of: "racial", with: "physical", options: .caseInsensitive)
        
        return translated
    }

    /// Intelligent LLM-based prompt sanitizer that preserves character details while ensuring DALL-E 3 compliance
    private func sanitizePromptWithLLM(_ prompt: String) async -> String {
        let systemPrompt = """
        You are a DALL-E 3 prompt sanitizer. Your job is to rewrite prompts to be DALL-E 3 compliant while preserving ALL character details and visual information.

        DALL-E 3 TRIGGERS TO AVOID:
        - Explicit racial terms: "Caucasian", "Black", "Indian", "Asian", "Hispanic"
        - Age + race combinations: "17 year old Indian", "21 Black person"
        - Personal names with detailed descriptions
        - Negative emotional states: "anxious", "angry", "sad"
        - Harsh instructional language: "must", "never", "forbidden"
        - Ancestry references: "of Indian descent", "suggesting ancestry"

        SAFE ALTERNATIVES:
        - Visual descriptors: "warm brown skin", "dark hair", "light eyes"
        - General age ranges: "teenager", "young adult", "middle-aged"
        - Positive emotions: "focused", "determined", "thoughtful"
        - Gentle instructions: "showing", "featuring", "with"

        PRESERVE THESE:
        - All physical appearance details (hair, eyes, skin tone, build)
        - Clothing and accessories
        - Scene setting and activities
        - Character relationships and roles
        - Art style preferences

        REWRITE RULES:
        1. Replace racial terms with visual descriptors
        2. Convert specific ages to age ranges when combined with appearance
        3. Remove personal names or make them generic
        4. Soften harsh language
        5. Keep the prompt under 200 characters when possible
        6. Maintain all essential visual information

        Return ONLY the rewritten prompt, nothing else.
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "max_tokens": 300
        ]

        do {
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, _) = try await URLSession.shared.data(for: req)
            
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg
            }
            struct Root: Decodable { let choices: [Choice] }
            
            let sanitized = try JSONDecoder().decode(Root.self, from: data).choices.first?.message.content ?? prompt
            
            print("🧹 LLM SANITIZED PROMPT:")
            print("ORIGINAL: \(prompt)")
            print("SANITIZED: \(sanitized)")
            
            return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            print("⚠️ LLM sanitization failed, using original prompt: \(error)")
            return prompt
        }
    }

    /// Enhanced sanitization that combines LLM intelligence with fallback rules
    private func sanitizeForDALLE3(_ prompt: String) async -> String {
        let llmSanitized: String
        if useLLMSanitizer {
            llmSanitized = await sanitizePromptWithLLM(prompt)
        } else {
            llmSanitized = prompt // skip LLM step
        }
        
        // Apply additional safety checks as fallback
        var finalSanitized = llmSanitized
        
        // Emergency fallback replacements for any missed terms
        let emergencyReplacements = [
            ("Caucasian", "light-skinned"),
            ("Black person", "person with dark skin"),
            ("Indian", "South Asian"),
            ("Hispanic", "Latino"),
            ("age 17", "teenage"),
            ("age 21", "young adult"),
            ("years old", "year old"),
            ("NEGATIVE:", "Style note:"),
            ("Avoid:", "Preferring:"),
            ("must not", "should avoid"),
            ("never", "rarely")
        ]
        
        for (problematic, safe) in emergencyReplacements {
            finalSanitized = finalSanitized.replacingOccurrences(of: problematic, with: safe, options: .caseInsensitive)
        }
        
        // Final cleanup
        finalSanitized = finalSanitized.replacingOccurrences(of: "  ", with: " ")
        finalSanitized = finalSanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return finalSanitized
    }

    private func negativesOpposite(to identity: [String]) -> String {
        let idLower = identity.joined(separator: ", ").lowercased()
        var bans: Set<String> = []
        for (trait, oppo) in traitOpposites where idLower.contains(trait) { bans.formUnion(oppo) }
        
        // Use softer, less triggering negative terms
        bans.formUnion(["different gender", "inconsistent features", "different skin tone"])
        
        if bans.isEmpty { bans.insert("different facial features") }
        return "Avoid: " + bans.joined(separator: ", ") + "."
    }

    // Enhanced identity prompt builder that enforces main character consistency
    private func buildIdentityPrompt() -> String {
        var identityBits: [String] = []
        
        // Get the main character's description from face analysis
        if let vision = faceDescription, !vision.isEmpty {
            identityBits.append(translateRaceToDescriptor(vision))
        }
        
        // Add user-specified details from settings
        if !ethnicity.isEmpty {
            let translatedEthnicity = translateRaceToDescriptor(ethnicity)
            identityBits.append(translatedEthnicity)
        }
        
        if !gender.isEmpty {
            identityBits.append("presenting as \(gender.lowercased())")
        }
        
        if !otherDetails.isEmpty {
            identityBits.append(translateRaceToDescriptor(otherDetails))
        }
        
        guard !identityBits.isEmpty else { return "" }
        
        let mainCharacterDescription = identityBits.joined(separator: ", ")
        
        let positive = "MAIN CHARACTER: The narrator is a person with \(mainCharacterDescription). By default, family members and close friends should share similar skin tone and features, UNLESS specific descriptions are provided for them in SCENE CHARACTERS below."
        
        return positive + " "
    }
    
    // Enhanced character context builder with better race handling
    private func buildCharacterContext(for entry: MemoryEntry) -> String {
        guard let detailsString = entry.value(forKey: "characterDetails") as? String,
              !detailsString.isEmpty,
              let data = detailsString.data(using: .utf8),
              let characterDetails = try? JSONDecoder().decode(CharacterDetails.self, from: data),
              !characterDetails.characters.isEmpty else {
            print("ℹ️ No character details found for memory: \(entry.prompt ?? "Untitled")")
            return ""
        }
        
        var characterDescriptions: [String] = []
        
        for character in characterDetails.characters {
            var description = ""
            
            // Character name or role
            if !character.name.isEmpty {
                description += character.name
            } else {
                description += "A person"
            }
            
            var traits: [String] = []
            
            // Age handling - convert specific ages to ranges for DALL-E 3 safety
            if !character.age.isEmpty {
                let safeAge = convertAgeToSafeRange(character.age)
                traits.append(safeAge)
            }
            
            // Race handling - translate and ensure consistency
            if !character.race.isEmpty {
                let translatedRace = translateRaceToDescriptor(character.race)
                traits.append(translatedRace)
            } else {
                // If no race specified, inherit from main character
                if !ethnicity.isEmpty {
                    let inheritedRace = translateRaceToDescriptor(ethnicity)
                    traits.append(inheritedRace)
                }
            }
            
            // Physical description
            if !character.physicalDescription.isEmpty {
                let translatedDescription = translateRaceToDescriptor(character.physicalDescription)
                traits.append(translatedDescription)
            }
            
            // Clothing
            if !character.clothing.isEmpty {
                traits.append("wearing \(character.clothing)")
            }
            
            // Relationship
            if !character.relationshipToNarrator.isEmpty {
                traits.append("(\(character.relationshipToNarrator))")
            }
            
            if !traits.isEmpty {
                description += " - " + traits.joined(separator: ", ")
            }
            
            characterDescriptions.append(description)
        }
        
        let characterContext = "SCENE CHARACTERS: " + characterDescriptions.joined(separator: "; ") + ". "
        print("🎭 Enhanced character context: \(characterContext)")
        return characterContext
    }
    
    // Helper function to convert specific ages to DALL-E 3 safe ranges
    private func convertAgeToSafeRange(_ age: String) -> String {
        let ageInt = Int(age.trimmingCharacters(in: CharacterSet.letters.union(.whitespaces))) ?? 0
        
        switch ageInt {
        case 0...12: return "child"
        case 13...17: return "teenager"
        case 18...25: return "young adult"
        case 26...40: return "adult"
        case 41...60: return "middle-aged adult"
        case 61...100: return "older adult"
        default: return age.lowercased().contains("teen") ? "teenager" : "adult"
        }
    }
    
    /// Create a simplified prompt that's more likely to work with OpenAI API
    private func createSimplifiedPrompt(from originalPrompt: String) -> String {
        // Extract the core scene and apply race translation
        var simplified = "Children's book illustration: "
        
        // Find the main scene description (usually after the character setup)
        let sentences = originalPrompt.components(separatedBy: ". ")
        var sceneDescription = ""
        
        for sentence in sentences {
            let clean = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            // Look for the main scene description
            if clean.lowercased().contains("illustration shows") ||
               clean.lowercased().contains("visual description") ||
               (clean.count > 50 && !clean.lowercased().contains("characters:") && !clean.lowercased().contains("negative:")) {
                sceneDescription = translateRaceToDescriptor(clean)
                break
            }
        }
        
        // If we found a good scene description, use it
        if !sceneDescription.isEmpty {
            simplified += sceneDescription + ". "
        } else {
            // Fallback: extract key elements and translate races
            let keyWords = ["sitting", "park", "making", "playing", "together", "friends"]
            for sentence in sentences {
                let clean = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if keyWords.contains(where: { clean.lowercased().contains($0) }) && clean.count > 30 {
                    simplified += translateRaceToDescriptor(clean) + ". "
                    break
                }
            }
            
            // Final fallback
            if simplified.count < 100 {
                simplified += "A group of friends enjoying time together in a beautiful outdoor setting. "
            }
        }
        
        // Add style instruction without repeating "illustration"
        simplified += "Soft watercolor children's book art style."
        
        return simplified
    }
    
    private func enrich(memory rawText: String) async throws -> String {
        // Build a comprehensive identity description
        var identityParts: [String] = []
        
        if let vision = faceDescription, !vision.isEmpty {
            identityParts.append(vision)
        }
        
        if !ethnicity.isEmpty {
            let translatedEthnicity = translateRaceToDescriptor(ethnicity)
            identityParts.append(translatedEthnicity)
        }
        
        if !gender.isEmpty {
            identityParts.append("presenting as \(gender.lowercased())")
        }
        
        let identity = identityParts.isEmpty ? "the narrator" : identityParts.joined(separator: ", ")
        
        let systemPrompt = """
        You are a scene-enriching assistant. Your job is to rewrite a user's memory into a rich, detailed paragraph suitable for generating a detailed image prompt.

        RULES:
        1. The main character of the story is: "\(identity)". Always refer to them using this exact description.
        2. From the context of the memory, infer a plausible age for every character and add it to their description.
        3. For **any other characters**, handle their description as follows:
            a. First, you **must** use any specific descriptions from the text (e.g., "Brandon was black", "a girl with blonde hair").
           b. If the text does **not** specify a race or ethnicity for a character, you **must** assume they share the same features and skin tone as the main character.
            c. After establishing their appearance, invent other plausible details like clothing and expression if they are not mentioned.
        4. Describe the **setting and the specific actions** in clear, unambiguous detail.
        5. Do not change the core events of the memory. Your goal is to make the description more vivid and explicit, **honoring and preserving all details from the original text.**
        6. Your entire response must be ONLY the rewritten paragraph. No extra text or explanation.
        """
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": rawText]
            ],
            "temperature": 0.3 // Lower temperature for more consistent results
        ]
        
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("✍️ Enriching memory with identity: \(identity)")
        let (data, _) = try await URLSession.shared.data(for: req)
        
        struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
        struct Root: Decodable { let choices: [Choice] }
        
        let enrichedText = try JSONDecoder().decode(Root.self, from: data).choices.first?.message.content ?? rawText
        print("📝 Enriched text → \(enrichedText)")
        return enrichedText
    }

    
    /// A temporary struct to hold a memory and its inferred chronological age.
    private struct ChronologicalMemory {
        let entry: MemoryEntry
        let age: Int
    }

    /// Uses an LLM to extract the user's age from the memory text.
    private func extractAge(from memoryText: String) async -> Int? {
        let systemPrompt = """
        You are a data extraction expert. Your task is to read a user's memory and determine the user's age at the time of the event.
        - Look for explicit mentions of age like "I was 13", "when I turned ten", "at age seven".
        - If no age is explicitly mentioned, infer a plausible age based on the context (e.g., "my first day of high school" -> 14, "learning to drive" -> 16, "graduating college" -> 22, "my first grandchild was born" -> 55).
        - You MUST respond with ONLY a single integer number and nothing else. For example: 13.
        - If you cannot determine an age with reasonable confidence, respond with 999.
        """
        
        let body: [String: Any] = [
            // ✅ UPDATED to the cheaper, faster model for this simple task.
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": memoryText]
            ],
            "temperature": 0.0,
            "max_tokens": 5
        ]
        
        do {
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: req)
            
            struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
            struct Root: Decodable { let choices: [Choice] }
            
            if let responseText = try JSONDecoder().decode(Root.self, from: data).choices.first?.message.content,
               let age = Int(responseText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return age
            }
        } catch {
            print("🚫 Age extraction failed:", error.localizedDescription)
        }
        
        return nil // Return nil on failure
    }

    func generateStorybook(forProfileID id: UUID) async {
        currentProfileID = id // Set current profile
        isLoading = true
        errorMessage = nil
        progress = 0
        images.removeAll()
        pageItems.removeAll()

        await ensureSubjectPhotoIsRegistered()
        await ensureFaceDescription()

        do {
            let entries = try await fetchMemoryEntries(for: id)
            let chosen  = await rankMemoriesWithLLM(entries, top: pageCountSetting)
            
            guard !chosen.isEmpty else {
                throw NSError(domain: "MemoirAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "No memories were selected to generate the story."])
            }

            // --- SORT THE CHOSEN MEMORIES CHRONOLOGICALLY ---
            print("🕥 Starting chronological sorting of \(chosen.count) memories...")
            var chronologicalMemories: [ChronologicalMemory] = []
            
            // Use a TaskGroup to run age extraction in parallel for efficiency
            await withTaskGroup(of: ChronologicalMemory?.self) { group in
                for entry in chosen {
                    group.addTask {
                        guard let text = entry.text, !text.isEmpty else { return nil }
                        // Default to a high age (999) if extraction fails, to sort them last.
                        let age = await self.extractAge(from: text) ?? 999
                        print(" -> Memory inferred age: \(age) for entry: \(entry.id?.uuidString ?? "N/A")")
                        return ChronologicalMemory(entry: entry, age: age)
                    }
                }
                
                for await chronoMemory in group {
                    if let memory = chronoMemory {
                        chronologicalMemories.append(memory)
                    }
                }
            }
            
            // Sort the temporary array by the extracted age
            chronologicalMemories.sort { $0.age < $1.age }
            
            // Create the final, sorted list of entries to be generated
            let sortedEntries = chronologicalMemories.map { $0.entry }
            print("✅ Chronological sorting complete.")
            
            // --- USE THE NEWLY SORTED ARRAY FOR GENERATION ---
            let identityPrefix = buildIdentityPrompt()
            var generated: [UIImage] = []

            for (idx, entry) in sortedEntries.enumerated() { // <-- Use sortedEntries here
                guard let entryID = entry.id else { continue }
                let raw = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !raw.isEmpty else { continue }

                let enrichedTranscript = try await enrich(memory: raw)

                guard let content = try await promptGen.generatePrompts(
                    from: enrichedTranscript,
                    pageCount: 1,
                    chosenArtStyle: currentArtStyle,
                    customArtStyleDetails: customArtStyleText
                ).first else {
                    print("⚠️ Could not generate content for memory entry. Skipping.")
                    continue
                }

                // Build character details context for this specific memory
                let characterContext = buildCharacterContext(for: entry)
                
                // Sanitize ONLY the image prompt portion so explicit character context stays intact
                var sanitizedImagePrompt = await sanitizeForDALLE3(content.imagePromptText)

                if currentArtStyle == .realistic {
                    sanitizedImagePrompt += " Camera pulled back, face partly turned away or softly out of focus so exact features are not discernible. Or another method where the face isn't perfectly clear."
                }

                let promptToSend = identityPrefix + characterContext + sanitizedImagePrompt

                print("🖼️ FULL PROMPT (\(promptToSend.count) chars) ►", promptToSend)

                let img: UIImage
                do {
                    // Try with full prompt first
                    img = try await imageSvc.generateImages(
                    prompt: promptToSend, n: 1, size: "1792x1024"
                ).first ?? UIImage()
                } catch {
                    // If full prompt fails, try simplified approach
                    print("⚠️ Full prompt failed, trying simplified approach...")
                    
                    // Create a much simpler prompt focusing only on the core scene
                    var simplifiedPrompt = createSimplifiedPrompt(from: content.imagePromptText)
                    simplifiedPrompt = await sanitizeForDALLE3(simplifiedPrompt)
                    print("🖼️ SIMPLIFIED PROMPT (\(simplifiedPrompt.count) chars) ►", simplifiedPrompt)
                    
                    do {
                        img = try await imageSvc.generateImages(
                            prompt: simplifiedPrompt, n: 1, size: "1792x1024"
                        ).first ?? UIImage()
                        print("✅ Simplified prompt succeeded!")
                    } catch {
                        print("⏳ Both full and simplified prompts failed on image \(idx + 1)/\(sortedEntries.count). Continuing with next memory...")
                        print("⏳ Error details: \(error.localizedDescription)")
                        continue
                    }
                }

                generated.append(img)

                pageItems.append(.illustration(image: img, caption: content.pageDisplayText))
                let chunks = raw.paginated()
                for (i, chunk) in chunks.enumerated() {
                    pageItems.append(.textPage(index: i + 1, total: chunks.count, body: chunk))
                }
                pageItems.append(.qrCode(id: entryID, url: URL(string: "memoirai://memory/\(entryID.uuidString)")!))

                progress = Double(idx + 1) / Double(sortedEntries.count)
            }

            images = generated
            
            // NEW: Persist the generated storybook
            if let profileID = currentProfileID {
                persistStorybook(for: profileID)
            }
            
        } catch {
            // Handle rate limiting with user-friendly message
            if let nsError = error as? NSError, nsError.code == 429 {
                errorMessage = "Too many requests to OpenAI. Please wait a few minutes and try again."
                print("StoryPageViewModel ERROR: Rate limited (429)")
            } else {
            errorMessage = error.localizedDescription
            print("StoryPageViewModel ERROR:", error.localizedDescription)
            }
        }

        isLoading = false
    }

    private func fetchMemoryEntries(for profileID: UUID) async throws -> [MemoryEntry] {
        let ctx = PersistenceController.shared.container.viewContext
        return try await ctx.perform {
            let req: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
            req.predicate = NSPredicate(format: "profileID == %@", profileID as CVarArg)
            return try ctx.fetch(req)
        }
    }

    private struct MemoryStub: Codable { let id: UUID; let summary: String }
    private struct ChatMessage: Encodable { let role: String; let content: String }
    private struct ChatCompletionRequest: Encodable {
        let model: String; let messages: [ChatMessage]
        let max_tokens: Int; let temperature: Double
    }

    private func rankMemoriesWithLLM(_ all: [MemoryEntry], top n: Int) async -> [MemoryEntry] {
        guard n < all.count else { return all }
        let stubs = all.compactMap { mem -> MemoryStub? in
            guard let id = mem.id, let txt = mem.text?.trimmingCharacters(in: .whitespacesAndNewlines), !txt.isEmpty else { return nil }
            // Safely truncate to avoid string index crashes
            let words = txt.split(separator: " ")
            let summary = words.prefix(25).joined(separator: " ")
            return MemoryStub(id: id, summary: String(summary))
        }
        guard let stubJSON = try? JSONEncoder().encode(stubs), let stubStr = String(data: stubJSON, encoding: .utf8) else {
            return Array(all.prefix(n))
        }
        let system = ChatMessage(role: "system", content: "You are a memoir editor. Pick the \(n) most emotionally significant memories.")
        let user = ChatMessage(role: "user", content: "Return ONLY JSON { \"top\": [\"uuid1\",\"uuid2\"] }. \nMemories: \(stubStr)")
        let req = ChatCompletionRequest(model: "gpt-4o-mini", messages: [system, user], max_tokens: 256, temperature: 0)
        var urlReq = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        urlReq.httpMethod = "POST"
        urlReq.httpBody   = try? JSONEncoder().encode(req)
        urlReq.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        urlReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, _) = try await URLSession.shared.data(for: urlReq)
            
            guard let content = extractContent(from: data) else {
                print("⚠️ LLM ranking failed to extract content.")
                return Array(all.prefix(n))
            }
            
            guard let idsDict = try? JSONDecoder().decode([String:[UUID]].self, from: Data(content.utf8)),
                  let ids = idsDict["top"] else {
                print("⚠️ LLM ranking failed to decode UUIDs from content: \(content)")
                return Array(all.prefix(n))
            }

            let idOrder = ids.enumerated().reduce(into: [UUID: Int]()) { $0[$1.element] = $1.offset }
            return all.filter { $0.id.map(ids.contains) ?? false }
                      .sorted {
                          guard let id1 = $0.id, let id2 = $1.id,
                                let order1 = idOrder[id1], let order2 = idOrder[id2] else { return false }
                          return order1 < order2
                      }
        } catch {
            print("LLM ranking failed:", error.localizedDescription)
            return Array(all.prefix(n))
        }
    }
    
    private func extractContent(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let msgDict = choices.first?["message"] as? [String: Any],
              let content = msgDict["content"] as? String else {
            return nil
        }
        
        // COMPLETELY SAFE VERSION: Use string methods instead of dangerous indexing
        guard !content.isEmpty else { return content }
        
        // Find the first { and last } using safe string methods
        if let startIndex = content.firstIndex(of: "{"),
           let endIndex = content.lastIndex(of: "}"),
           startIndex < endIndex {
            
            // Use safe substring extraction
            let substring = content[startIndex...endIndex]
            return String(substring)
        }
        
        // If no JSON brackets found, return the original content
        return content
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale  = maxSide / longest
        let newSz  = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSz, false, 0)
        draw(in: CGRect(origin: .zero, size: newSz))
        let out = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return out
    }
    static func qrCode(from text: String, size: CGFloat = 300) -> UIImage {
        let ctx = CIContext()
        let f   = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        guard let ci = f.outputImage else { return UIImage() }
        let scaleX = size / ci.extent.size.width
        let scaleY = size / ci.extent.size.height
        let scaled = ci.transformed(by: .init(scaleX: scaleX, y: scaleY))
        if let cg = ctx.createCGImage(scaled, from: scaled.extent) {
            return UIImage(cgImage: cg)
        }
        return UIImage()
    }
}

extension String {
    func paginated(wordsPerPage: Int = 130) -> [String] {
        let words = split { $0.isWhitespace }
        guard words.count > wordsPerPage else { return [self] }
        var pages: [String] = []
        var i = 0
        while i < words.count {
            let j = min(i + wordsPerPage, words.count)
            pages.append(words[i..<j].joined(separator: " "))
            i += wordsPerPage
        }
        return pages
    }
}
