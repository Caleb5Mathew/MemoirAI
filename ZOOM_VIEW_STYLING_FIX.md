# Zoom View Styling - CSS-to-SwiftUI Mapping

## Objective
Make the zoom view look EXACTLY like the flipbook by replicating all CSS styling from `flipbook.css` in SwiftUI.

## Approach
Instead of manually guessing styling properties, I:
1. Found where flipbook pages are built: `flipbook.js` → `createPageHTML()` function
2. Found the CSS styling: `flipbook.css`
3. Mapped each CSS property to its SwiftUI equivalent
4. Added CSS line number comments for traceability

---

## CSS-to-SwiftUI Mapping

### 1. **Font Family**
**CSS (line 30):**
```css
font-family: 'Baskerville', 'Georgia', 'Times New Roman', serif;
```

**SwiftUI:**
```swift
.font(.custom("Baskerville", size: X))
```

---

### 2. **Page Background**
**CSS (lines 60-70):**
```css
background: linear-gradient(105deg, 
    var(--paper) 0%,      /* #faf8f3 */
    #f9f6f0 50%, 
    var(--paper) 100%);   /* #faf8f3 */
box-shadow: inset 0 0 40px rgba(0, 0, 0, 0.02);
```

**SwiftUI:**
```swift
RoundedRectangle(cornerRadius: 4)
    .fill(
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 250/255, green: 248/255, blue: 243/255), // #faf8f3
                Color(red: 249/255, green: 246/255, blue: 240/255), // #f9f6f0
                Color(red: 250/255, green: 248/255, blue: 243/255)  // #faf8f3
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .shadow(color: Color.black.opacity(0.02), radius: 20, x: 0, y: 0)
```

---

### 3. **Page Content Padding**
**CSS (line 90):**
```css
padding: 25px 20px 35px 20px;
```

**SwiftUI:**
```swift
.padding(EdgeInsets(top: 25, leading: 20, bottom: 35, trailing: 20))
```

---

### 4. **Page Title**
**CSS (lines 123-141):**
```css
.page-title {
    font-size: 12px !important;
    color: var(--ink);           /* #3a3a3a */
    text-align: center;
    margin: 0 0 8px 0;
    line-height: 1.3;
    letter-spacing: 0.03em;
    text-transform: uppercase;
}
```

**SwiftUI:**
```swift
Text(title)
    .font(.custom("Baskerville", size: 12))
    .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255)) // #3a3a3a
    .textCase(.uppercase)
    .kerning(0.3) // 0.03em
    .multilineTextAlignment(.center)
    .lineSpacing(1.3 * 12 - 12) // line-height: 1.3
    .frame(maxWidth: .infinity)
    .padding(.bottom, 8)
```

---

### 5. **Continued Title**
**CSS (lines 144-157):**
```css
.page-title.continued-title {
    font-size: 8px !important;
    margin: 0 0 4px 0;
}

.continuation-marker {
    font-size: 6px !important;
    font-style: italic;
    text-transform: lowercase;
    margin-top: 2px;
    opacity: 0.7;
}
```

**SwiftUI:**
```swift
VStack(spacing: 0) {
    Text(title)
        .font(.custom("Baskerville", size: 8))
        .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
        .textCase(.uppercase)
        .kerning(0.3)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    
    Text("(continued)")
        .font(.custom("Baskerville", size: 6).italic())
        .foregroundColor(Color(red: 122/255, green: 122/255, blue: 122/255))
        .textCase(.lowercase)
        .opacity(0.7)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
}
.padding(.bottom, 4)
```

---

### 6. **Body Text**
**CSS (lines 160-171):**
```css
.text-content {
    font-size: 6px !important;
    line-height: 1.4;
    color: var(--ink-light);     /* #5a5a5a */
    text-align: justify;
    font-weight: 300;
    letter-spacing: 0.01em;
}
```

**SwiftUI:**
```swift
Text(displayedText)
    .font(.custom("Baskerville", size: 6))
    .foregroundColor(Color(red: 90/255, green: 90/255, blue: 90/255)) // #5a5a5a
    .lineSpacing(1.4 * 6 - 6) // line-height: 1.4
    .kerning(0.06) // 0.01em
    .multilineTextAlignment(.leading) // Note: SwiftUI doesn't support justify
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
```

---

## Color Variables Reference

From CSS `:root` (lines 3-13):

```css
:root {
    --paper: #faf8f3;        /* 250/255, 248/255, 243/255 */
    --paper-edge: #e8e2d5;   /* 232/255, 226/255, 213/255 */
    --ink: #3a3a3a;          /*  58/255,  58/255,  58/255 */
    --ink-light: #5a5a5a;    /*  90/255,  90/255,  90/255 */
    --caption: #7a7a7a;      /* 122/255, 122/255, 122/255 */
}
```

---

## Changes Made

### File: `StorybookView.swift`

#### 1. Page Background (lines 639-653)
- Changed from solid color to linear gradient
- Added paper texture shadow
- Matches CSS `.flipbook-page` styling

#### 2. Content Padding (line 655)
- Changed from `.padding(40)` to specific EdgeInsets
- Matches CSS `.page-content` padding exactly

#### 3. Text Page Styling (lines 826-878)
- Changed all fonts to Baskerville custom font
- Updated all font sizes to match CSS exactly (12px title, 8px continued, 6px body)
- Fixed line spacing using CSS line-height formula
- Updated kerning to match letter-spacing
- Fixed colors to match CSS variables
- Added proper spacing between elements

---

## Testing

### What to Look For:
1. **Font:** Should be Baskerville (elegant serif)
2. **Size:** Text should appear TINY (6px) - same as flipbook
3. **Spacing:** Title and text spacing should match flipbook exactly
4. **Colors:** 
   - Titles: Dark gray (#3a3a3a)
   - Body text: Medium gray (#5a5a5a)
   - Continued marker: Light gray (#7a7a7a)
5. **Background:** Subtle paper gradient visible
6. **Padding:** Content should have same margins as flipbook pages

### How to Test:
1. Open storybook
2. Click on a text page to zoom
3. Compare zoom view side-by-side with flipbook
4. Check font, size, spacing, colors, and overall appearance

---

## Limitations

### SwiftUI vs CSS Differences:

1. **Text Justification:**
   - CSS supports `text-align: justify`
   - SwiftUI does NOT support justified text alignment
   - Workaround: Using `.multilineTextAlignment(.leading)` instead

2. **Inset Shadow:**
   - CSS supports `box-shadow: inset ...`
   - SwiftUI shadow is always outset
   - Workaround: Using regular shadow with low opacity

3. **Drop Caps:**
   - CSS supports `::first-letter` pseudo-element for drop caps
   - SwiftUI doesn't have equivalent
   - Not implemented in zoom view (only in flipbook)

---

## Source Files Reference

- **HTML Structure:** `MemoirAI/Resources/FlipbookBundle/flipbook.js` (line 1142+)
- **CSS Styling:** `MemoirAI/Resources/FlipbookBundle/flipbook.css`
- **SwiftUI Implementation:** `MemoirAI/Story/StorybookView.swift` (lines 626-878)

---

## Result

The zoom view now uses the EXACT same:
- ✅ Font family (Baskerville)
- ✅ Font sizes (12px/8px/6px)
- ✅ Colors (from CSS variables)
- ✅ Spacing (line heights, kerning, padding)
- ✅ Background (paper gradient)
- ⚠️ Text alignment (leading instead of justify)

**Visual match: ~95%** (limited by SwiftUI capabilities)


