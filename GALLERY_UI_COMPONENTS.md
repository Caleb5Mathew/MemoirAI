# Storybook Gallery - UI Component Guide

## Visual Component Breakdown

### 🎨 Filter Chips (Top Row)
```
┌─────────────────────────────────────────────────────────┐
│  [📚 All Books] [🖼️ Realistic] [😊 Comic] [📖 Kids Book] │
└─────────────────────────────────────────────────────────┘
```

**Features:**
- Selected state: Brown background (`Tokens.accent`)
- Unselected: White background with subtle shadow
- Icons match the art style type
- Smooth transitions on tap
- Horizontal scrollable if needed

---

### 🔄 Sort Controls (Bottom Row)
```
┌──────────────────────────────────────────────────────┐
│  ⬍  [Newest] [Oldest]                      5 books   │
└──────────────────────────────────────────────────────┘
```

**Features:**
- Sort direction icon
- Outlined selected state
- Live book count badge on right
- Minimal, clean design

---

### 📚 Book Card Design
```
┌─────────────────────────┐
│                         │
│   [Cover Image]         │  ← 200px height
│   (200x200)             │
│                    🏷️   │  ← Art style badge
│─────────────────────────│
│ December 13, 2025       │  ← Date (serif font)
│ 📄 12 • 2 hours ago     │  ← Page count & time
└─────────────────────────┘
```

**Styling:**
- White background
- Rounded corners (12px)
- Shadow with depth
- Subtle border
- Art style badge floating on cover

---

### 📑 Complete Layout Structure
```
╔═══════════════════════════════════════════════╗
║           My Collection                        ║  ← Nav title (large)
╠═══════════════════════════════════════════════╣
║ ┌───────────────────────────────────────────┐ ║
║ │ Filter Chips (All/Realistic/Comic/Kids)   │ ║
║ │ Sort Controls (Newest/Oldest) | Count     │ ║
║ └───────────────────────────────────────────┘ ║
╠═══════════════════════════════════════════════╣
║  ┌──────────┐  ┌──────────┐                  ║
║  │  Book 1  │  │  Book 2  │                  ║  ← 2-column grid
║  │  Card    │  │  Card    │                  ║
║  └──────────┘  └──────────┘                  ║
║                                               ║
║  ┌──────────┐  ┌──────────┐                  ║
║  │  Book 3  │  │  Book 4  │                  ║
║  │  Card    │  │  Card    │                  ║
║  └──────────┘  └──────────┘                  ║
║                                               ║
╚═══════════════════════════════════════════════╝
```

---

### 🎭 Empty State (When No Books Match Filter)
```
┌──────────────────────────────────┐
│                                  │
│          📚                       │  ← Large icon (64pt)
│                                  │
│      No storybooks yet           │  ← Serif title (24pt)
│                                  │
│  Generate a book and it will     │  ← Helpful subtitle
│  appear here.                    │
│                                  │
└──────────────────────────────────┘
```

**Features:**
- Changes based on active filter
- Helpful, contextual messaging
- Elegant serif typography
- Subtle accent colors

---

## Color Palette Used

### Background Colors
- **bgWash**: `#EDE6DA` - Warm parchment background
- **paper**: `#FFFFFF` - Clean white for cards

### Text Colors
- **ink**: `#2F2A25` - Primary text color
- **ink.opacity(0.6)**: Secondary/metadata text
- **ink.opacity(0.5)**: Tertiary text

### Accent Colors
- **accent**: `#7C5C3A` - Primary accent (brown)
- **accentSoft**: `#C9B6A0` - Soft accent for borders
- **shadow**: `black.opacity(0.12)` - Soft shadows

---

## Typography Hierarchy

### Card Title (Date)
- **Size**: 15pt
- **Weight**: Semibold
- **Design**: Serif
- **Color**: Tokens.ink

### Metadata (Page count, time)
- **Size**: 12pt
- **Weight**: Regular
- **Design**: Default
- **Color**: Tokens.ink.opacity(0.5)

### Filter Chips
- **Size**: 14pt
- **Weight**: Medium
- **Design**: Default

### Sort Buttons
- **Size**: 13pt
- **Weight**: Medium
- **Design**: Default

### Empty State Title
- **Size**: 24pt
- **Weight**: Semibold
- **Design**: Serif

---

## Interactive States

### Filter Chip States
```
Unselected: [White BG] [Grey Text] [Light Shadow]
Selected:   [Brown BG] [White Text] [Accent Shadow]
```

### Sort Button States
```
Unselected: [No Border] [Grey Text]
Selected:   [Brown Border] [Brown Text] [Light Brown BG]
```

### Book Card States
```
Normal:  [Standard Shadow] [No Scale]
Tapped:  [Slight Depth] [Opens Reader Sheet]
```

---

## Animations

### Filter/Sort Changes
- **Type**: Spring animation
- **Response**: 0.3 seconds
- **Damping**: 0.8 (natural feel)

### Book Card Transitions
- **Appear**: Scale + Opacity fade in
- **Disappear**: Scale + Opacity fade out
- **Duration**: Automatic with spring physics

### Book Count Badge
- **Update**: Smooth number change
- **Type**: Implicit animation with value change

---

## SF Symbols Used

| Element | Symbol | Context |
|---------|--------|---------|
| All Books Filter | `books.vertical` | Filter chip & empty state |
| Realistic Filter | `photo.artframe` | Filter chip & card badge |
| Comic Filter | `face.smiling.fill` | Filter chip & card badge |
| Kids Book Filter | `book.closed.fill` | Filter chip & card badge |
| Sort Direction | `arrow.up.arrow.down` | Sort control indicator |
| Page Count | `doc.text.fill` | Card metadata |
| Close Reader | `xmark.circle.fill` | Reader dismiss button |
| Placeholder | `photo` | Empty cover placeholder |

---

## Layout Specifications

### Grid Configuration
- **Columns**: 2
- **Spacing**: 16px between cards
- **Padding**: 16px around grid

### Card Dimensions
- **Width**: Flexible (fills column)
- **Cover Height**: 200px
- **Info Section**: Auto-height
- **Corner Radius**: 12px

### Control Panel
- **Horizontal Padding**: 16px
- **Top Padding**: 12px
- **Bottom Padding**: 8px
- **Corner Radius**: 16px

---

## Accessibility Features

✅ **VoiceOver Labels**: All interactive elements have clear labels
✅ **Color Contrast**: Text meets WCAG AA standards
✅ **Touch Targets**: All buttons meet 44pt minimum
✅ **Dynamic Type**: Supports system font scaling
✅ **Semantic Colors**: Uses semantic color tokens

---

## Responsive Behavior

### Portrait Mode
- 2-column grid
- Full-width control panel
- Optimal card proportions

### Landscape Mode
- 2-column grid maintained
- May show more cards vertically
- Control panel adjusts to width

### Small Screens (iPhone SE)
- Cards scale appropriately
- Filter chips scroll horizontally
- Readable font sizes maintained

### Large Screens (iPad)
- Same 2-column layout (could be enhanced to 3-4 columns in future)
- Larger touch targets
- More spacing

---

## User Flow

1. **Enter Gallery** → See all books, "Newest" sort
2. **Tap Filter** → Books fade out/in with new filter
3. **Tap Sort** → Books rearrange smoothly
4. **Tap Book** → Sheet opens with full-screen reader
5. **Swipe in Reader** → Navigate through book pages
6. **Close Reader** → Return to gallery at same scroll position

---

This design creates a premium, app-like experience that matches the elegant, warm aesthetic of the memoir application.


