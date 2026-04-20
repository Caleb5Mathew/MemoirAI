# Memory to Image Generation Workflow

**Complete documentation of how memories transform from audio recording to AI-generated storybook images**

*Last Updated: 2025-10-30*

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Step-by-Step Workflow](#step-by-step-workflow)
3. [Example Memory Journey](#example-memory-journey)
4. [Prompt Transformations](#prompt-transformations)
5. [Why Images Might Not Match Expectations](#why-images-might-not-match-expectations)
6. [Technical Details](#technical-details)

---

## Overview

The MemoirAI app transforms user memories from audio recordings into beautiful, personalized storybook images through a 7-stage AI pipeline. Understanding this workflow helps identify where accuracy might be lost and how to improve it.

### The Full Pipeline

```
1. RECORD → 2. TRANSCRIBE → 3. SAVE → 4. ENHANCE → 5. GENERATE PROMPT → 6. SANITIZE → 7. CREATE IMAGE
```

---

## Step-by-Step Workflow

### Stage 1: Recording Memory 🎙️

**File:** `MemoirAI/Home/RecordMemoryView.swift` (lines 453-526)

**What Happens:**
- User selects a prompt (e.g., "Tell me about your first job")
- Records audio (44.1kHz, 32-bit PCM)
- Real-time transcription starts during recording
- Can type text instead of or in addition to audio

**Output:**
```swift
MemoryEntry {
    id: UUID()
    prompt: "Tell me about your first job"
    audioData: Data (audio file)
    audioFileURL: "file:///.../recording.m4a"
    text: nil // Will be filled by transcription
    createdAt: Date()
    profileID: UUID
}
```

---

### Stage 2: Transcription 🎧

**File:** `MemoirAI/Recent/SpeechTranscriber.swift` or `RealTimeTranscriptionManager.swift`

**What Happens:**
- Audio is sent to speech recognition API
- Transcription saved to memory entry
- User can edit transcription if needed

**Example Input (Audio):**
```
"I was 17 when I got my first job at a local grocery store. 
My manager was this really kind older lady named Mrs. Johnson. 
She taught me how to stock shelves and work the cash register."
```

**Example Output (Text):**
```
Memory.text = "I was 17 when I got my first job at a local grocery store. My manager was this really kind older lady named Mrs. Johnson. She taught me how to stock shelves and work the cash register."
```

---

### Stage 3: Saving Memory 💾

**File:** `MemoirAI/Home/RecordMemoryView.swift` (lines 536-620)

**What Happens:**
- Memory saved to Core Data
- Photos attached if provided
- Notification sent that memory was saved
- Memory marked as "incomplete" (not enhanced yet)

**Data Model:**
```swift
MemoryEntry {
    id: UUID
    prompt: String
    text: String?
    audioData: Data?
    audioFileURL: String?
    photos: Set<Photo>?
    createdAt: Date
    profileID: UUID
    isIncomplete: Bool // true until enhanced
}
```

---

### Stage 4: Memory Enhancement ✨

**File:** `MemoirAI/Story/StoryPageViewModel.swift` (lines 787-845)

**What Happens:**
- When generating storybook, system "enriches" raw memory text
- Adds character descriptions from profile
- Infers age and adds vivid details
- Makes memory more suitable for image generation

**Enhancement Prompt (sent to GPT-4o-mini):**

```
SYSTEM: You are a scene-enriching assistant. Your job is to rewrite a user's memory into a rich, detailed paragraph suitable for generating a detailed image prompt.

RULES:
1. The main character of the story is: "[warm brown skin, expressive dark eyes, straight dark hair, presenting as female]". Always refer to them using this exact description.
2. From the context of the memory, infer a plausible age for every character and add it to their description.
3. For any other characters, handle their description as follows:
   a. First, you must use any specific descriptions from the text
   b. If the text does not specify a race or ethnicity for a character, you must assume they share the same features and skin tone as the main character.
   c. After establishing their appearance, invent other plausible details like clothing and expression if they are not mentioned.
4. Describe the setting and the specific actions in clear, unambiguous detail.
5. Do not change the core events of the memory. Your goal is to make the description more vivid and explicit, honoring and preserving all details from the original text.
6. Your entire response must be ONLY the rewritten paragraph. No extra text or explanation.

USER: I was 17 when I got my first job at a local grocery store. My manager was this really kind older lady named Mrs. Johnson. She taught me how to stock shelves and work the cash register.
```

**Enhanced Output:**

```
"A 17-year-old young woman with warm brown skin, expressive dark eyes, and straight dark hair stands in the bustling aisles of a neighborhood grocery store, wearing a crisp employee uniform. Beside her, an older woman in her early 60s with warm brown skin and gray-streaked hair tied in a neat bun—Mrs. Johnson, the store manager—demonstrates with patient gestures how to arrange canned goods on metal shelves. The fluorescent lights overhead cast a steady glow on rows of colorful product labels. Mrs. Johnson points to the cash register with a kind smile, showing the young woman which buttons to press, while shoppers with carts move past in the background."
```

**Key Transformation:**
- ✅ Added specific age (17)
- ✅ Added physical descriptions from profile
- ✅ Added setting details (fluorescent lights, metal shelves)
- ✅ Added action details (demonstrating, pointing)
- ✅ Assumed Mrs. Johnson shares same features (warm brown skin)

---

### Stage 5: Prompt Generation 🎨

**File:** `MemoirAI/Backend/PromptGenerator.swift` (lines 49-139)

**What Happens:**
- Enhanced memory sent to GPT-4o
- Generates structured image prompt + page text
- Uses art style templates (realistic, cartoon, kids book)
- Returns separated image prompt and display text

**Prompt Generation Request (to GPT-4o):**

```json
{
  "model": "gpt-4o",
  "messages": [
    {
      "role": "system",
      "content": "You are a professional storybook illustrator... [template for realistic style]"
    },
    {
      "role": "user",
      "content": "Create 1 illustrated page from this memory:\n\n[Enhanced memory text]\n\nFor each page provide:\nIMAGE_PROMPT_START\n[description for image]\nIMAGE_PROMPT_END\nPAGE_TEXT_START\n[text for page]\nPAGE_TEXT_END\n---SCENE_DIVIDER---"
    }
  ]
}
```

**Generated Output:**

```
IMAGE_PROMPT_START
A realistic illustration showing a 17-year-old young woman with warm brown skin, expressive dark eyes, and straight dark hair in a grocery store uniform. She stands beside an older woman manager with warm brown skin and gray-streaked hair demonstrating how to stock shelves. The setting shows metal shelving units with colorful products, fluorescent overhead lighting, and shoppers with carts in the background. The composition captures a mentorship moment with both women focused on the shelves, conveying patience and learning.
IMAGE_PROMPT_END

PAGE_TEXT_START
My first job at seventeen taught me more than just how to stock shelves—Mrs. Johnson showed me what kindness in leadership looks like.
PAGE_TEXT_END
```

---

### Stage 6: Prompt Sanitization 🧹

**File:** `MemoirAI/Story/StoryPageViewModel.swift` (lines 497-545, 973-980)

**What Happens:**
- Image prompt from Stage 5 is "sanitized" for DALL-E 3 compliance
- Removes words that trigger content policy
- Adds character context from profile
- Adds style modifiers for realistic mode

**Sanitization Process:**

**Input (from Stage 5):**
```
"A realistic illustration showing a 17-year-old young woman with warm brown skin, expressive dark eyes, and straight dark hair in a grocery store uniform..."
```

**Sanitization Prompt (sent to GPT-4o-mini):**

```
SYSTEM: You are a DALL-E 3 prompt sanitizer. Your job is to rewrite prompts to be DALL-E 3 compliant while preserving ALL character details and visual information.

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

Return ONLY the rewritten prompt, nothing else.

USER: [Image prompt from Stage 5]
```

**Sanitized Output:**
```
"A teenager with warm brown skin, expressive dark eyes, and straight dark hair wearing a grocery store uniform. An older woman with warm brown skin and gray-streaked hair in a neat bun demonstrates shelf stocking techniques. Metal shelving with colorful products, fluorescent lighting overhead, shoppers with carts in background. Mentorship moment showing patience and learning."
```

**Then Additional Context Added:**

```swift
// Identity prefix (from profile headshot analysis)
let identityPrefix = "A person with warm brown skin, expressive dark eyes, straight dark hair. "

// Character context (from memory's character details if any)
let characterContext = buildCharacterContext(for: entry) // Usually empty

// If realistic style, add face obscuring instruction
if currentArtStyle == .realistic {
    sanitizedImagePrompt += " Camera pulled back, face partly turned away or softly out of focus so exact features are not discernible. Or another method where the face isn't perfectly clear."
}

// FINAL PROMPT sent to DALL-E 3:
let promptToSend = identityPrefix + characterContext + sanitizedImagePrompt
```

---

### Stage 7: Image Generation 🖼️

**File:** `MemoirAI/Backend/OpenAIImageService.swift` (lines 41-140)

**What Happens:**
- Final prompt sent to DALL-E 3 API
- Request parameters: model=dall-e-3, size=1792x1024, quality=standard
- Image URL returned, downloaded, and attached to memory

**Final DALL-E 3 Request:**

```json
{
  "model": "dall-e-3",
  "prompt": "A person with warm brown skin, expressive dark eyes, straight dark hair. A teenager with warm brown skin, expressive dark eyes, and straight dark hair wearing a grocery store uniform. An older woman with warm brown skin and gray-streaked hair in a neat bun demonstrates shelf stocking techniques. Metal shelving with colorful products, fluorescent lighting overhead, shoppers with carts in background. Mentorship moment showing patience and learning. Camera pulled back, face partly turned away or softly out of focus so exact features are not discernible.",
  "n": 1,
  "size": "1792x1024",
  "response_format": "url",
  "quality": "standard"
}
```

**Response:**
```json
{
  "created": 1761795944,
  "data": [
    {
      "url": "https://oaidalleapiprodscus.blob.core.windows.net/..."
    }
  ]
}
```

**Final Output:**
- ✅ Image downloaded and saved to memory
- ✅ Displayed in storybook
- ✅ User can view/edit

---

## Example Memory Journey

### Original Memory (User Input)

**Audio Recording:**
> "I remember my 8th birthday party. My mom made this huge chocolate cake with blue frosting. All my friends from school came over and we played tag in the backyard. My best friend Michael gave me a toy dinosaur that I still have."

### After Transcription
```
text = "I remember my 8th birthday party. My mom made this huge chocolate cake with blue frosting. All my friends from school came over and we played tag in the backyard. My best friend Michael gave me a toy dinosaur that I still have."
```

### After Enhancement (GPT-4o-mini)
```
"An 8-year-old child with warm brown skin, bright eyes, and curly dark hair stands excitedly in a sunny backyard decorated with colorful balloons and streamers. On a table covered with a patterned cloth sits an enormous chocolate cake with bright blue frosting and lit candles. The child's mother, a woman in her mid-30s with warm brown skin and curly hair, stands proudly beside the cake. Six or seven children of similar age run and play tag across the green grass, their laughter filling the air. In the foreground, a boy around 8 years old with warm brown skin and short hair—Michael—holds out a wrapped gift containing a toy dinosaur, smiling widely."
```

### After Prompt Generation (GPT-4o)
```
IMAGE_PROMPT:
"A realistic illustration of an 8-year-old child with warm brown skin and curly dark hair standing in a backyard with colorful balloons. A chocolate cake with bright blue frosting sits on a table. Several children play tag on green grass. A boy holds a wrapped gift. Sunny afternoon, joyful celebration atmosphere."

PAGE_TEXT:
"Eight years old, blue frosting, and the gift of a toy dinosaur from my best friend—some birthday memories last forever."
```

### After Sanitization (GPT-4o-mini)
```
"A young child with warm brown skin and curly dark hair in a backyard decorated with colorful balloons. A chocolate cake with bright blue frosting on a table. Multiple children playing tag on green grass. A child offering a wrapped gift. Sunny afternoon, joyful celebration atmosphere."
```

### Final DALL-E 3 Prompt
```
"A person with warm brown skin, expressive dark eyes, curly dark hair. A young child with warm brown skin and curly dark hair in a backyard decorated with colorful balloons. A chocolate cake with bright blue frosting on a table. Multiple children playing tag on green grass. A child offering a wrapped gift. Sunny afternoon, joyful celebration atmosphere. Camera pulled back, face partly turned away or softly out of focus so exact features are not discernible."
```

---

## Why Images Might Not Match Expectations

### 1. **Too Many Transformation Stages** ⚠️

**Issue:** Memory goes through 4 AI rewrites before becoming an image
- Enhancement (GPT-4o-mini) 
- Prompt Generation (GPT-4o)
- Sanitization (GPT-4o-mini)
- Image Generation (DALL-E 3)

**Result:** Each stage can drift from the original, losing specificity

**Solution:** 
- Reduce transformation stages
- Keep original memory details more prominent
- Add verification step

---

### 2. **Identity Context Gets Diluted** ⚠️

**Issue:** Profile identity added at the very beginning but gets rewritten multiple times

**Current Flow:**
```
Profile: "warm brown skin, dark eyes"
  → Enhancement adds this to memory
    → Prompt generation may simplify it  
      → Sanitization may change it further
        → DALL-E 3 interprets it loosely
```

**Result:** Final image may not match profile photo accurately

**Solution:**
- Add identity context AFTER sanitization (closer to DALL-E)
- Make identity description more persistent through stages
- Use stronger language like "must feature" instead of descriptive

---

### 3. **Over-Sanitization** ⚠️

**Issue:** Sanitization removes too much specificity to avoid DALL-E 3 triggers

**Example:**
```
Before: "A 17-year-old South Asian girl with long black hair"
After:  "A teenager with dark hair"
```

**Result:** Image becomes too generic, loses accuracy

**Solution:**
- Less aggressive sanitization
- Keep visual descriptors like hair length, style
- Test which terms actually trigger DALL-E vs which are safe

---

### 4. **Character Context Not Always Used** ⚠️

**Issue:** `buildCharacterContext()` function often returns empty string

**Code Location:** StoryPageViewModel.swift (line 971)

```swift
let characterContext = buildCharacterContext(for: entry)
// This is often empty!
```

**Result:** Loses character-specific details from memory

**Solution:**
- Always populate character context
- Extract character details from enhanced memory
- Add to final prompt more reliably

---

### 5. **Face Obscuring in Realistic Mode** ⚠️

**Issue:** Added instruction actively makes faces unclear

**Code:**
```swift
if currentArtStyle == .realistic {
    sanitizedImagePrompt += " Camera pulled back, face partly turned away or softly out of focus so exact features are not discernible."
}
```

**Result:** Faces intentionally blurred/obscured, reducing accuracy

**Solution:**
- Remove this instruction
- Or make it optional based on user preference
- Trust DALL-E 3's interpretation instead

---

### 6. **Prompt Length Limits** ⚠️

**Issue:** Sanitization tries to keep prompts under 200 characters

**Code:** StoryPageViewModel.swift line 528
```
5. Keep the prompt under 200 characters when possible
```

**Result:** Important details truncated

**Solution:**
- Increase limit to 500-800 characters (DALL-E 3 supports up to 4000)
- Prioritize accuracy over brevity
- Only truncate if absolutely necessary

---

## Technical Details

### File Structure

```
MemoirAI/
├── Home/
│   └── RecordMemoryView.swift          # Stage 1: Recording
├── Recent/
│   └── SpeechTranscriber.swift         # Stage 2: Transcription
├── Story/
│   ├── StoryPageViewModel.swift        # Stage 4, 6: Enhancement & Sanitization
│   └── PromptGenerator.swift           # Stage 5: Prompt Generation
└── Backend/
    └── OpenAIImageService.swift        # Stage 7: Image Generation
```

### API Calls Per Image

| Stage | API | Model | Purpose | Cost/Call |
|-------|-----|-------|---------|-----------|
| 2 | Speech-to-Text | Whisper | Transcribe audio | $0.006/min |
| 4 | Chat | GPT-4o-mini | Enhance memory | $0.00015 |
| 5 | Chat | GPT-4o | Generate prompt | $0.0025 |
| 6 | Chat | GPT-4o-mini | Sanitize prompt | $0.00015 |
| 7 | Images | DALL-E 3 | Create image | $0.12 |
| **Total** | | | **Per image** | **~$0.123** |

### Prompt Character Counts

| Stage | Average Length | Max Length |
|-------|---------------|------------|
| Original Memory | 100-500 chars | ~2000 |
| Enhanced Memory | 400-800 chars | ~3000 |
| Generated Prompt | 300-600 chars | ~2000 |
| Sanitized Prompt | 200-400 chars | ~1000 |
| Final DALL-E Prompt | 300-600 chars | ~4000 |

---

## Recommendations for Improvement

### High Priority 🔴

1. **Reduce transformation stages**
   - Combine enhancement + prompt generation into one step
   - Skip sanitization for safe prompts (detect triggers first)

2. **Strengthen identity persistence**
   - Add profile identity AFTER sanitization
   - Use reinforcing language: "The main subject MUST have [features]"
   - Repeat key features twice in prompt

3. **Remove face obscuring**
   - Delete the "camera pulled back" instruction
   - Trust DALL-E 3's natural interpretation

### Medium Priority 🟡

4. **Increase prompt length limits**
   - Change from 200 to 800 characters
   - Prioritize accuracy over brevity

5. **Better character context**
   - Always extract and use character details
   - Build richer character descriptions

6. **Test sanitization necessity**
   - Identify which terms actually trigger DALL-E
   - Only sanitize when truly needed

### Low Priority 🟢

7. **Add verification step**
   - After image generation, check if it matches profile
   - Regenerate if accuracy is low

8. **User feedback loop**
   - Let users mark images as "accurate" or "inaccurate"
   - Learn from patterns

---

## Code Locations Reference

### Key Functions

| Function | File | Lines | Purpose |
|----------|------|-------|---------|
| `saveMemory()` | RecordMemoryView.swift | 536-620 | Save recorded memory |
| `enrich(memory:)` | StoryPageViewModel.swift | 787-845 | Enhance memory with details |
| `generatePrompts()` | PromptGenerator.swift | 49-139 | Create image prompts |
| `sanitizePromptWithLLM()` | StoryPageViewModel.swift | 498-545 | Sanitize for DALL-E 3 |
| `generateImages()` | OpenAIImageService.swift | 41-140 | Call DALL-E 3 API |
| `buildCharacterContext()` | StoryPageViewModel.swift | ~971 | Add character details |

---

## Conclusion

The MemoirAI memory-to-image pipeline is sophisticated but has multiple points where accuracy can be lost:

1. ❌ **Too many AI rewrites** - each stage drifts from original
2. ❌ **Identity gets diluted** - profile features lost through transformations  
3. ❌ **Over-sanitization** - removes too much specificity
4. ❌ **Face obscuring** - actively makes faces unclear
5. ❌ **Character context underused** - often empty

**Primary Recommendations:**
- Reduce transformation stages (combine steps)
- Add identity AFTER sanitization (closer to DALL-E)
- Remove face obscuring instruction
- Increase prompt length limits
- Always use character context

These changes should significantly improve image accuracy while maintaining DALL-E 3 compliance.

---

*Generated: 2025-10-30*  
*Version: 1.0*










