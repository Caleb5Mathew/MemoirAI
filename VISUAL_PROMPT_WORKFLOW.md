# Visual Prompt Workflow - Simple Explanation

## 🎨 How Visual Prompts Work with Book Generation

### The Complete Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    USER'S MEMORY (Raw Text)                     │
│  "I was 17 when I got my first job at a grocery store..."       │
└────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              STEP 1: EXTRACT VISUAL SCENE                       │
│                                                                  │
│  GPT-4o-mini analyzes memory and identifies the most visually    │
│  interesting moment. Creates a visual description.              │
│                                                                  │
│  Output: "A teenager stands in a grocery store aisle, an older  │
│          woman demonstrates shelf stocking techniques..."        │
└────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              STEP 2: BUILD CHARACTER LIST                       │
│                                                                  │
│  System builds character descriptions:                         │
│  • Character 1: Main person (from headshot photo analysis)      │
│  • Character 2: Other people (from memory's character details)  │
│                                                                  │
│  Example:                                                       │
│  Character 1: Main character - warm brown skin, dark eyes...    │
│  Character 2: Mrs. Johnson - older woman, gray hair...          │
└────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              STEP 3: ASSEMBLE FINAL PROMPT                     │
│                                                                  │
│  Combines 3 parts:                                              │
│                                                                  │
│  ┌─────────────────────────────────────────────┐               │
│  │ PART 1: CHARACTERS                         │               │
│  │ Character 1: Main character - [description]│               │
│  │ Character 2: Mrs. Johnson - [description]  │               │
│  └─────────────────────────────────────────────┘               │
│                              +                                  │
│  ┌─────────────────────────────────────────────┐               │
│  │ PART 2: SCENE DESCRIPTION                   │               │
│  │ "A teenager stands in a grocery store..."  │               │
│  └─────────────────────────────────────────────┘               │
│                              +                                  │
│  ┌─────────────────────────────────────────────┐               │
│  │ PART 3: STYLE                               │               │
│  │ "STYLE: Photorealistic image with detailed │               │
│  │  textures, natural lighting..."             │               │
│  └─────────────────────────────────────────────┘               │
└────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              STEP 4: ENHANCE PROMPT (Optional)                  │
│                                                                  │
│  GPT-4o rewrites prompt for better clarity while preserving:    │
│  • Character list (exact)                                       │
│  • Style section (exact)                                        │
│  • Scene description (enhanced for visual clarity)               │
└────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              STEP 5: GENERATE IMAGE                             │
│                                                                  │
│  Try GPT-5 first (if available):                                │
│  • Sends prompt directly, GPT-5 handles everything              │
│                                                                  │
│  Fallback to DALL-E 3:                                          │
│  • Sends enhanced prompt to DALL-E 3 API                        │
│  • Size: 1792x1024                                              │
│  • Returns generated image                                      │
└────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FINAL IMAGE                                   │
│              Added to Storybook Page                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 Detailed Breakdown

### Step 1: Extract Visual Scene (`extractVisualScene`)

**Location:** `StoryPageViewModel.swift` (lines 1399-1453)

**What it does:**
- Takes raw memory text
- Uses GPT-4o-mini to identify the most visually interesting moment
- Returns a single paragraph describing the scene

**Input:**
```
"I was 17 when I got my first job at a local grocery store. 
My manager was this really kind older lady named Mrs. Johnson. 
She taught me how to stock shelves and work the cash register."
```

**Output:**
```
"A teenager stands in the bustling aisles of a neighborhood grocery 
store, wearing a crisp employee uniform. Beside her, an older woman 
manager demonstrates with patient gestures how to arrange canned goods 
on metal shelves. The fluorescent lights overhead cast a steady glow 
on rows of colorful product labels."
```

---

### Step 2: Build Character List (`buildCharacterList`)

**Location:** `StoryPageViewModel.swift` (lines 956-1034)

**What it does:**
- Extracts character descriptions from:
  1. **Headshot photo** (main character) - analyzed via face recognition
  2. **Character details** stored with the memory (other people)
- Formats as "Character 1, Character 2, etc."

**Example Output:**
```
Character 1: Main character - warm brown skin, expressive dark eyes, 
             straight dark hair
Character 2: Mrs. Johnson - older woman, gray-streaked hair, 
             warm brown skin
```

---

### Step 3: Assemble Final Prompt (`assembleFinalPrompt`)

**Location:** `StoryPageViewModel.swift` (lines 1372-1396)

**What it does:**
- Combines three parts into one prompt:
  1. **Characters** (from Step 2)
  2. **Scene Description** (from Step 1)
  3. **Style** (from user's art style selection)

**Final Prompt Structure:**
```
Character 1: Main character - warm brown skin, expressive dark eyes, 
             straight dark hair
Character 2: Mrs. Johnson - older woman, gray-streaked hair

A teenager stands in the bustling aisles of a neighborhood grocery 
store, wearing a crisp employee uniform. Beside her, an older woman 
manager demonstrates with patient gestures how to arrange canned goods 
on metal shelves. The fluorescent lights overhead cast a steady glow 
on rows of colorful product labels.

STYLE: Photorealistic image with detailed textures, natural lighting, 
and lifelike appearance.
```

---

### Step 4: Enhance Prompt (`enhancePromptForDALLE3`)

**Location:** `StoryPageViewModel.swift` (lines 1327-1370)

**What it does:**
- Uses GPT-4o to improve prompt clarity
- **Preserves** character list and style exactly
- **Enhances** scene description for better visual clarity

**Why:** Makes the prompt more effective for image generation while keeping important parts intact.

---

### Step 5: Generate Image

**Location:** `StoryPageViewModel.swift` (lines 1582-1669)

**Two Methods:**

#### Method 1: GPT-5 (Preferred)
- Sends prompt directly to GPT-5
- GPT-5 handles everything internally (like ChatGPT web)
- Returns image directly

#### Method 2: DALL-E 3 (Fallback)
- Sends enhanced prompt to DALL-E 3 API
- Parameters:
  - Model: `dall-e-3`
  - Size: `1792x1024`
  - Quality: `standard`
- Downloads image from returned URL

---

## 🎯 Key Components

### Character Context Sources

1. **Main Character (Character 1):**
   - From headshot photo analysis (`faceDescription`)
   - Analyzed using OpenAI Vision API
   - Describes: skin tone, eye color, hair color/texture

2. **Other Characters:**
   - From `characterDetails` stored with memory
   - User-provided descriptions when creating memory
   - Includes: name, age, race, physical description, clothing

### Art Styles

The system supports different art styles that modify the final prompt:

- **Realistic:** "Photorealistic image with detailed textures, natural lighting..."
- **Kids Book:** "Children's book illustration with soft watercolor style..."
- **Cartoon:** "Cartoon illustration with bold outlines, flat colors..."
- **Custom:** User-defined style description

---

## 🔄 Complete Example Flow

### Input Memory:
```
"I was 17 when I got my first job at a local grocery store. 
My manager was this really kind older lady named Mrs. Johnson. 
She taught me how to stock shelves and work the cash register."
```

### Step 1 Output (Visual Scene):
```
"A teenager stands in the bustling aisles of a neighborhood grocery 
store, wearing a crisp employee uniform. Beside her, an older woman 
manager demonstrates with patient gestures how to arrange canned goods 
on metal shelves."
```

### Step 2 Output (Character List):
```
Character 1: Main character - warm brown skin, expressive dark eyes, 
             straight dark hair
Character 2: Mrs. Johnson - older woman, gray-streaked hair
```

### Step 3 Output (Assembled Prompt):
```
Character 1: Main character - warm brown skin, expressive dark eyes, 
             straight dark hair

Character 2: Mrs. Johnson - older woman, gray-streaked hair

A teenager stands in the bustling aisles of a neighborhood grocery 
store, wearing a crisp employee uniform. Beside her, an older woman 
manager demonstrates with patient gestures how to arrange canned goods 
on metal shelves. The fluorescent lights overhead cast a steady glow 
on rows of colorful product labels.

STYLE: Photorealistic image with detailed textures, natural lighting, 
and lifelike appearance.
```

### Step 4 Output (Enhanced - if needed):
```
[Same structure, but scene description may be refined for clarity]
```

### Step 5 Output:
```
[Generated image showing the scene]
```

---

## 🎨 Visual Summary

```
┌──────────────┐
│ Raw Memory   │
│   Text       │
└──────┬───────┘
       │
       ├─► Extract Visual Scene (GPT-4o-mini)
       │   └─► Scene description
       │
       ├─► Build Character List
       │   ├─► Character 1 (from headshot)
       │   └─► Character 2+ (from memory details)
       │
       └─► Assemble Final Prompt
           ├─► Characters section
           ├─► Scene description section
           └─► Style section
               │
               ├─► Enhance (GPT-4o) [optional]
               │
               └─► Generate Image
                   ├─► Try GPT-5 first
                   └─► Fallback to DALL-E 3
                       └─► Final Image
```

---

## 💡 Key Insights

1. **3-Part Structure:** Every prompt has Characters + Scene + Style
2. **Character Consistency:** Character 1 always comes from headshot analysis
3. **Scene Extraction:** LLM identifies the most visually interesting moment
4. **Style Flexibility:** User can choose different art styles
5. **Fallback System:** Tries GPT-5 first, falls back to DALL-E 3
6. **Prompt Enhancement:** Optional step to improve clarity without losing details

---

*Last Updated: 2025-01-27*







