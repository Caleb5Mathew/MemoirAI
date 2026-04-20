# Code Flow Diagram: Memory to Image Generation

**Visual representation of function calls and data flow**

---

## 🎯 Complete Call Stack

```
USER INTERACTION
    │
    ├── RecordMemoryView.swift
    │   └── func saveMemory() [line 536]
    │       ├── Create MemoryEntry
    │       ├── Save to Core Data
    │       └── Post notification: .memorySaved
    │
    ├── User navigates to Story tab
    │
    └── StoryPage.swift
        └── func generateStorybookWithPaywallCheck() [line ~200]
            │
            ├── Check image allowance
            └── Call StoryPageViewModel
                │
                └── StoryPageViewModel.swift
                    └── func generateStoryBook() [line 900+]
                        │
                        ├── Step 1: Fetch memories
                        │   └── FetchRequest for MemoryEntry
                        │
                        ├── Step 2: Sort chronologically
                        │   └── func extractAge() [line 855]
                        │       └── OpenAI API: GPT-3.5-turbo
                        │           ├── Prompt: "Extract age from memory"
                        │           └── Response: Integer age
                        │
                        ├── Step 3: For each memory...
                        │   │
                        │   ├── 3a) ENHANCE MEMORY
                        │   │   └── func enrich(memory:) [line 787]
                        │   │       └── OpenAI API: GPT-4o-mini
                        │   │           ├── System: "You are a scene-enriching assistant..."
                        │   │           ├── User: [raw memory text]
                        │   │           └── Response: [enriched paragraph]
                        │   │
                        │   ├── 3b) GENERATE PROMPT
                        │   │   └── PromptGenerator.swift
                        │   │       └── func generatePrompts() [line 49]
                        │   │           └── OpenAI API: GPT-4o
                        │   │               ├── System: PromptTemplates.systemPrompt()
                        │   │               ├── User: PromptTemplates.userMessage()
                        │   │               └── Response: IMAGE_PROMPT + PAGE_TEXT
                        │   │
                        │   ├── 3c) BUILD CHARACTER CONTEXT
                        │   │   └── func buildCharacterContext() [line 656]
                        │   │       ├── Decode characterDetails JSON
                        │   │       └── Return: Character description string
                        │   │
                        │   ├── 3d) SANITIZE PROMPT
                        │   │   └── func sanitizeForDALLE3() [line 497]
                        │   │       └── func sanitizePromptWithLLM() [line 498]
                        │   │           └── OpenAI API: GPT-4o-mini
                        │   │               ├── System: "You are a DALL-E 3 sanitizer..."
                        │   │               ├── User: [image prompt from 3b]
                        │   │               └── Response: [sanitized prompt]
                        │   │
                        │   ├── 3e) CONSTRUCT FINAL PROMPT
                        │   │   └── [line 980]
                        │   │       ├── identityPrefix +
                        │   │       ├── characterContext +
                        │   │       ├── sanitizedImagePrompt +
                        │   │       └── (if realistic) "Camera pulled back..."
                        │   │
                        │   └── 3f) GENERATE IMAGE
                        │       └── OpenAIImageService.swift
                        │           └── func generateImages() [line 41]
                        │               └── OpenAI API: DALL-E 3
                        │                   ├── Request:
                        │                   │   ├── model: "dall-e-3"
                        │                   │   ├── prompt: [final combined prompt]
                        │                   │   ├── size: "1792x1024"
                        │                   │   ├── quality: "standard"
                        │                   │   └── n: 1
                        │                   └── Response:
                        │                       └── URL to generated image
                        │
                        └── Step 4: Assemble storybook
                            ├── Create cover page
                            ├── Add memory images
                            └── Return to UI
```

---

## 🔄 Data Transformation Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          USER INPUT LAYER                                │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    Audio Recording or Typed Text
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ MEMORY OBJECT (Core Data)                                               │
│                                                                          │
│ struct MemoryEntry {                                                    │
│     id: UUID                                                            │
│     prompt: "Tell me about your first job"                              │
│     text: "I was 17 when I got my first job..."                         │
│     audioData: Data?                                                    │
│     createdAt: Date                                                     │
│     profileID: UUID                                                     │
│ }                                                                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                  Generate Storybook Button Pressed
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PROFILE DATA LAYER                                                       │
│                                                                          │
│ Profile {                                                               │
│     ethnicity: "Hispanic"                                               │
│     gender: "Female"                                                    │
│     faceDescription: "warm brown skin, expressive dark eyes..."         │
│     headshotImage: UIImage?                                             │
│ }                                                                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ ENHANCEMENT LAYER (GPT-4o-mini)                                         │
│                                                                          │
│ Input:  "I was 17 when I got my first job..."                           │
│         + Profile identity                                              │
│                                                                          │
│ Output: "A 17-year-old with warm brown skin stands in a grocery         │
│          store wearing an employee uniform. An older woman with warm    │
│          brown skin demonstrates shelf stocking..."                     │
│                                                                          │
│ [~800 characters, rich detail]                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PROMPT GENERATION LAYER (GPT-4o)                                        │
│                                                                          │
│ Input:  [Enhanced memory] + Art style preferences                       │
│                                                                          │
│ Output: StoryPageContent {                                              │
│             imagePromptText: "A realistic illustration showing..."      │
│             pageDisplayText: "My first job taught me..."                │
│         }                                                               │
│                                                                          │
│ [~600 characters, structured for image generation]                     │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ CHARACTER CONTEXT LAYER (Optional)                                      │
│                                                                          │
│ IF memory has characterDetails:                                         │
│     Extract character descriptions from JSON                            │
│     Build context string: "Character Brandon: tall, athletic..."        │
│ ELSE:                                                                    │
│     Return empty string ""                                              │
│                                                                          │
│ [Usually empty - feature underutilized]                                │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ SANITIZATION LAYER (GPT-4o-mini)                                        │
│                                                                          │
│ Input:  [Image prompt from previous layer]                              │
│                                                                          │
│ Process: - Remove racial terms                                          │
│          - Convert specific ages to ranges                              │
│          - Remove names                                                 │
│          - Compress to ~200 characters                                  │
│                                                                          │
│ Output: "A teenager with warm brown skin in uniform. An older           │
│          woman demonstrates shelf stocking. Grocery store setting."     │
│                                                                          │
│ [~400 characters, DALL-E 3 compliant but simplified]                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ FINAL PROMPT ASSEMBLY                                                   │
│                                                                          │
│ Concatenate:                                                            │
│   1. Identity prefix: "A person with warm brown skin..."                │
│   2. Character context: [usually empty]                                 │
│   3. Sanitized prompt: [from previous layer]                            │
│   4. (if realistic) "Camera pulled back, face not discernible..."       │
│                                                                          │
│ Final: "A person with warm brown skin, expressive dark eyes,            │
│         straight dark hair. A teenager with warm brown skin in          │
│         uniform. An older woman demonstrates shelf stocking.            │
│         Grocery store setting. Camera pulled back, face not             │
│         discernible."                                                   │
│                                                                          │
│ [~600 characters total]                                                 │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ IMAGE GENERATION (DALL-E 3)                                             │
│                                                                          │
│ API Request:                                                            │
│   POST https://api.openai.com/v1/images/generations                     │
│   {                                                                     │
│     "model": "dall-e-3",                                                │
│     "prompt": "[final assembled prompt]",                               │
│     "size": "1792x1024",                                                │
│     "quality": "standard",                                              │
│     "n": 1                                                              │
│   }                                                                     │
│                                                                          │
│ Response:                                                               │
│   {                                                                     │
│     "data": [{                                                          │
│       "url": "https://oaidalleapiprodscus.blob.core..."                │
│     }]                                                                  │
│   }                                                                     │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ IMAGE DOWNLOAD & DISPLAY                                                │
│                                                                          │
│ - Download image from URL                                               │
│ - Convert to UIImage                                                    │
│ - Save to storybook data structure                                      │
│ - Display in FlipbookView                                               │
│ - Enable download as PDF                                                │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📁 File Responsibility Matrix

| File | Purpose | Input | Output | API Calls |
|------|---------|-------|--------|-----------|
| **RecordMemoryView.swift** | Record audio/text | User audio/text | MemoryEntry | Speech-to-Text |
| **StoryPageViewModel.swift** | Orchestrate generation | MemoryEntry[] | UIImage[] | GPT-4o-mini (2x), GPT-3.5-turbo (1x) |
| **PromptGenerator.swift** | Create image prompts | Enhanced text | StoryPageContent | GPT-4o (1x) |
| **OpenAIImageService.swift** | Generate images | Image prompt | UIImage | DALL-E 3 (1x) |
| **PromptTemplates.swift** | Prompt templates | Art style | String template | None |
| **FlipbookView.swift** | Display storybook | Image array | Interactive book | None |

---

## 🔀 Decision Points

### 1. Should memory be enhanced?
```swift
// Location: StoryPageViewModel.swift line ~958
let raw = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
guard !raw.isEmpty else { continue }

let enrichedTranscript = try await enrich(memory: raw)
```

**Decision:** Always enhance. No option to skip.  
**Impact:** +1 API call, +$0.00015, +2-3s latency

---

### 2. Should prompt be sanitized?
```swift
// Location: StoryPageViewModel.swift line ~974
var sanitizedImagePrompt = await sanitizeForDALLE3(content.imagePromptText)
```

**Decision:** Always sanitize. No option to skip.  
**Impact:** +1 API call, +$0.00015, +2-3s latency  
**Alternative:** Could check for triggers first, only sanitize if needed

---

### 3. Should character context be added?
```swift
// Location: StoryPageViewModel.swift line ~971
let characterContext = buildCharacterContext(for: entry)
// Often returns "" - only used if memory has characterDetails JSON
```

**Decision:** Try to add, but usually empty  
**Impact:** Minimal - feature underutilized  
**Recommendation:** Always populate from enhanced text

---

### 4. Should face be obscured?
```swift
// Location: StoryPageViewModel.swift line ~976
if currentArtStyle == .realistic {
    sanitizedImagePrompt += " Camera pulled back, face partly turned away..."
}
```

**Decision:** Always obscure faces in realistic mode  
**Impact:** **Significantly reduces face accuracy**  
**Recommendation:** Remove this completely

---

## 🕐 Timing Breakdown

**For a single memory image:**

| Stage | Function | API | Duration | Cost |
|-------|----------|-----|----------|------|
| 1. Fetch memory | Core Data query | - | ~50ms | $0 |
| 2. Extract age | `extractAge()` | GPT-3.5 | ~2s | $0.00003 |
| 3. Enhance memory | `enrich()` | GPT-4o-mini | ~3s | $0.00015 |
| 4. Generate prompt | `generatePrompts()` | GPT-4o | ~5s | $0.0025 |
| 5. Build context | `buildCharacterContext()` | - | ~5ms | $0 |
| 6. Sanitize | `sanitizePromptWithLLM()` | GPT-4o-mini | ~3s | $0.00015 |
| 7. Generate image | `generateImages()` | DALL-E 3 | ~15s | $0.12 |
| **TOTAL** | | | **~28s** | **~$0.123** |

**For a 10-page storybook:**
- Time: ~4-5 minutes (with parallel processing)
- Cost: ~$1.23

---

## 🐛 Common Failure Points

### Failure Point #1: Invalid API Key
```
Location: Any API call
Error: "invalid_api_key"
Cause: Info.plist not updated or cached
Fix: Clean build folder, rebuild
```

### Failure Point #2: Content Policy Rejection
```
Location: DALL-E 3 image generation
Error: "content_policy_violation"
Cause: Sanitization failed to remove trigger
Fix: Improve sanitization prompt
```

### Failure Point #3: Empty Character Context
```
Location: buildCharacterContext()
Output: "" (empty string)
Cause: characterDetails JSON not saved to memory
Impact: Loses character-specific details
Fix: Always extract and save character details during enhancement
```

### Failure Point #4: Rate Limiting
```
Location: Any API call
Error: 429 Too Many Requests
Cause: Too many requests in short time
Fix: Add exponential backoff retry logic
```

### Failure Point #5: Prompt Too Long
```
Location: DALL-E 3 generation
Error: "invalid_prompt_length"
Cause: Final prompt exceeds 4000 characters
Fix: Already has fallback truncation
```

---

## 🔧 Key Functions Reference

### Most Important Functions

#### 1. `generateStoryBook()`
**File:** StoryPageViewModel.swift (~line 900)  
**Purpose:** Main orchestrator - coordinates entire generation pipeline  
**Calls:** `extractAge()`, `enrich()`, `generatePrompts()`, `buildCharacterContext()`, `sanitizeForDALLE3()`, `generateImages()`

#### 2. `enrich(memory:)`
**File:** StoryPageViewModel.swift (line 787)  
**Purpose:** Transform raw memory into detailed scene description  
**API:** GPT-4o-mini  
**Key Prompt:** "You are a scene-enriching assistant..."

#### 3. `generatePrompts()`
**File:** PromptGenerator.swift (line 49)  
**Purpose:** Create structured image prompts from enhanced memory  
**API:** GPT-4o  
**Returns:** `StoryPageContent` with imagePromptText + pageDisplayText

#### 4. `sanitizePromptWithLLM()`
**File:** StoryPageViewModel.swift (line 498)  
**Purpose:** Make prompts DALL-E 3 compliant  
**API:** GPT-4o-mini  
**Key Prompt:** "You are a DALL-E 3 prompt sanitizer..."

#### 5. `generateImages()`
**File:** OpenAIImageService.swift (line 41)  
**Purpose:** Call DALL-E 3 API and download image  
**API:** DALL-E 3  
**Returns:** `UIImage`

---

## 🎯 Critical Code Locations

### Where Identity Is Added
```swift
// Line ~710-730 in StoryPageViewModel.swift
var identityParts: [String] = []

if let vision = faceDescription, !vision.isEmpty {
    identityParts.append(vision)
}

if !ethnicity.isEmpty {
    let translatedEthnicity = translateRaceToDescriptor(ethnicity)
    identityParts.append(translatedEthnicity)
}

let identityPrefix = identityParts.joined(separator: ", ")
```

### Where Sanitization Happens
```swift
// Line ~497-545 in StoryPageViewModel.swift
private func sanitizePromptWithLLM(_ prompt: String) async -> String {
    let systemPrompt = """
    You are a DALL-E 3 prompt sanitizer...
    """
    // GPT-4o-mini call
}
```

### Where Face Is Obscured
```swift
// Line ~976-978 in StoryPageViewModel.swift
if currentArtStyle == .realistic {
    sanitizedImagePrompt += " Camera pulled back, face partly turned away..."
}
```

### Where Final Prompt Is Assembled
```swift
// Line ~980 in StoryPageViewModel.swift
let promptToSend = identityPrefix + characterContext + sanitizedImagePrompt
print("🖼️ FULL PROMPT (\(promptToSend.count) chars) ►", promptToSend)
```

---

## 📊 API Usage Statistics

### Tokens Per Image

| API Call | Model | Input Tokens | Output Tokens | Cost |
|----------|-------|--------------|---------------|------|
| Age extraction | GPT-3.5-turbo | ~200 | ~5 | $0.00003 |
| Enhancement | GPT-4o-mini | ~300 | ~500 | $0.00015 |
| Prompt generation | GPT-4o | ~600 | ~400 | $0.0025 |
| Sanitization | GPT-4o-mini | ~400 | ~200 | $0.00015 |
| Image generation | DALL-E 3 | - | - | $0.12 |
| **Total per image** | | **~1,500** | **~1,105** | **~$0.123** |

### Annual Usage (Hypothetical)

If 1,000 users each create 5 storybooks with 10 images:
- Total images: 50,000
- Total cost: ~$6,150
- Average per user: $6.15

---

*Diagram created: 2025-10-30*  
*Version: 1.0*










