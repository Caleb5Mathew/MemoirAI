# Memoir Preview Book Creation System - Complete Guide

This guide documents the complete book creation system in MemoirAI, from the "Memoir Preview" button on the homepage through the entire book generation and editing flow.

## 📋 System Overview

The Memoir Preview system consists of two main flows:
1. **Preview Flow** - Shows a sample book with mock pages
2. **Creation Flow** - Generates AI-powered storybooks from user memories

### Architecture Components
- **UI Layer**: SwiftUI views for book display and interaction
- **Business Logic**: ViewModels for state management and AI integration
- **Data Layer**: Core Data for memory storage and persistence
- **AI Integration**: OpenAI for text generation and image creation
- **Subscription Management**: RevenueCat integration for paywall

## 🏗 File Structure & Responsibilities

### Core Navigation & Entry Points

#### `Homepage.swift` - Main Entry Point
**Location**: `MemoirAI/Home/Homepage.swift`
**Purpose**: Contains the "Memoir Preview" button that initiates the book creation flow

**Key Components**:
```swift
// Memoir Preview Button
NavigationLink(destination: StorybookView()
    .environmentObject(profileVM)
) {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text("Memoir Preview")
                .font(.footnote)
                .fontWeight(.bold)
                .foregroundColor(.black)
            Text("Flip through a finished book")
                .font(.subheadline)
                .foregroundColor(.black.opacity(0.7))
        }
        Spacer()
        Image(systemName: "book")
            .foregroundColor(.gray)
    }
    .padding()
    .background(Color(red: 0.98, green: 0.93, blue: 0.80))
    .cornerRadius(16)
    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    .padding(.horizontal)
}

// Your Book Button (Premium)
NavigationLink(destination: StoryPage()
    .environmentObject(profileVM)
) {
    // Premium gradient outline button
}
```

**Flow**: Homepage → StorybookView (Preview) or StoryPage (Creation)

### Preview Flow Files

#### `StorybookView.swift` - Preview Landing Page
**Location**: `MemoirAI/Story/StorybookView.swift`
**Purpose**: Shows a sample book with mock pages and navigation to creation

**Key Features**:
- **Sample Book Display**: Shows `MockBookPage.samplePages`
- **Page Navigation**: Swipe/flip through sample pages
- **Action Buttons**: 
  - "Create your own book" → StoryPage
  - "Add photos" → PhotoPickerSheet
- **Blank State**: Shows placeholder when no book exists

**UI Components**:
```swift
struct StorybookView: View {
    @State private var currentPage = 0
    @State private var showPhotoPicker = false
    @State private var isCreatingNewBook = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(colors: [Tokens.bgPrimary, Tokens.bgWash], ...)
                
                VStack {
                    headerView           // Title and back button
                    bookPreview          // OpenBookView or BlankBookCoverView
                    actionButtonsView    // Create book + Add photos buttons
                }
            }
        }
    }
}
```

#### `OpenBookView.swift` - Book Display Component
**Location**: `MemoirAI/Story/OpenBookView.swift`
**Purpose**: Renders the actual book with page-turning animations

**Key Features**:
- **Two-Page Spread**: Left and right pages with spine
- **Page Navigation**: Chevron buttons for page turning
- **Haptic Feedback**: Tactile response on page changes
- **Shadow Effects**: Realistic book shadows

**Implementation**:
```swift
struct OpenBookView: View {
    let pages: [MockBookPage]
    @Binding var currentPage: Int
    let bookWidth: CGFloat
    let bookHeight: CGFloat
    
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                leftPage    // Current page content
                spine       // Book spine/gutter
                rightPage   // Next page preview
            }
            .frame(width: bookWidth, height: bookHeight)
            .shadow(color: Tokens.shadow, radius: 12, x: 0, y: 6)
            
            // Navigation chevrons
            if pages.count > 1 {
                HStack {
                    // Previous/Next buttons
                }
            }
        }
    }
}
```

#### `PageCurlBookController.swift` - Page Turn Animation
**Location**: `MemoirAI/Story/PageCurlBookController.swift`
**Purpose**: Provides native iOS page curl animations

**Key Features**:
- **UIPageViewController Integration**: Native page curl transitions
- **Swipe Gestures**: Touch-based page navigation
- **Page Index Management**: Tracks current page position
- **Smooth Animations**: Hardware-accelerated transitions

**Implementation**:
```swift
struct PageCurlBookController: UIViewControllerRepresentable {
    let pages: [MockBookPage]
    @Binding var currentPage: Int
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: nil
        )
        // Configure data source and delegate
        return pageViewController
    }
}
```

#### `MockBookPage.swift` - Sample Content
**Location**: `MemoirAI/Story/MockBookPage.swift`
**Purpose**: Provides sample book pages for preview

**Page Types**:
```swift
enum PageType {
    case cover
    case text
    case photo
    case mixed
    case twoPageSpread
}

// Sample pages with realistic content
static let samplePages: [MockBookPage] = [
    MockBookPage(type: .cover, content: "Memories of Achievement", imageName: nil),
    MockBookPage(type: .twoPageSpread, content: "Memories of Achievement", imageName: "graduation_photo"),
    // ... more sample pages
]
```

#### `TwoPageSpreadView.swift` - Layout Component
**Location**: `MemoirAI/Story/MockBookPage.swift` (embedded)
**Purpose**: Renders the specific two-page spread layout

**Layout Structure**:
- **Left Page**: Text bars (paragraph placeholders)
- **Right Page**: Title + Photo + Caption
- **Responsive Design**: Adapts to screen size

### Creation Flow Files

#### `StoryPage.swift` - Main Creation Interface
**Location**: `MemoirAI/Story/StoryPage.swift`
**Purpose**: Primary interface for generating AI-powered storybooks

**Key Features**:
- **Memory Selection**: Choose which memories to include
- **Settings Configuration**: Art style, page count, personal details
- **AI Generation**: Creates text and images from memories
- **Progress Tracking**: Real-time generation progress
- **Subscription Integration**: Paywall for premium features

**State Management**:
```swift
struct StoryPage: View {
    @StateObject private var vm = StoryPageViewModel()
    @StateObject private var subscriptionManager = RCSubscriptionManager.shared
    @State private var showSettings = false
    @State private var showGallery = false
    @State private var hasRequestedGeneration = false
    
    // Progress simulation
    @State private var fakeProgress: Double = 0
    @State private var realProgress: Double = 0
}
```

**UI Structure**:
```swift
var body: some View {
    NavigationStack {
        ZStack {
            // Background
            LinearGradient(...)
            
            VStack {
                headerView           // Title and settings button
                memorySelectionView  // Choose memories to include
                generationControls   // Generate button and progress
                bookPreview          // Generated book display
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showGallery) { StorybookGalleryView() }
    }
}
```

#### `StoryPageViewModel.swift` - Business Logic
**Location**: `MemoirAI/Story/StoryPageViewModel.swift`
**Purpose**: Manages the entire book generation process

**Key Responsibilities**:
- **Memory Processing**: Converts memories to book content
- **AI Integration**: Coordinates with OpenAI for text and images
- **Persistence**: Saves generated books to iCloud
- **Settings Management**: Handles user preferences
- **Error Handling**: Manages generation failures

**Data Models**:
```swift
enum PageItem {
    case illustration(image: UIImage, caption: String)
    case textPage(index: Int, total: Int, body: String)
    case qrCode(id: UUID, url: URL)
}

struct PersistableStorybook: Codable {
    let profileID: UUID
    let pageItems: [PersistablePageItem]
    let artStyle: String
    let createdAt: Date
}
```

**Core Methods**:
```swift
class StoryPageViewModel: ObservableObject {
    // Generation
    func generateStorybook(forProfileID: UUID) async
    func clearCurrentStorybook()
    
    // Persistence
    func loadStorybookForProfile(_ profileID: UUID)
    func saveStorybookToCloud()
    func downloadStorybook() -> URL?
    
    // Settings
    func backupSettingsToCloud()
    func restoreSettingsFromCloud()
}
```

#### `SettingsView.swift` - Configuration Interface
**Location**: `MemoirAI/Story/SettingsView.swift`
**Purpose**: Allows users to configure book generation settings

**Settings Categories**:
- **Page Count**: Slider for number of pages (1-50)
- **Art Style**: Realistic, Cartoon, Kid's Book, Custom
- **Personal Details**: Ethnicity, gender, custom details
- **Advanced Settings**: Developer options

**Art Styles**:
```swift
enum ArtStyle: String, CaseIterable, Identifiable {
    case realistic = "Realistic"
    case cartoon = "Cartoon"
    case kidsBook = "Kid's Book"
    case custom = "Custom"
}
```

**UI Components**:
```swift
struct SettingsView: View {
    @AppStorage("memoirPageCount") var pageCountSetting: Int = 2
    @AppStorage("memoirArtStyle") private var selectedArtStyleRawValue: String
    @AppStorage("memoirCustomArtStyleText") private var customArtStyleText: String
    @AppStorage("memoirEthnicity") private var ethnicity: String = ""
    @AppStorage("memoirGender") private var gender: String = ""
    
    var body: some View {
        ZStack {
            // Background
            softCream.ignoresSafeArea()
            
            ScrollView {
                VStack {
                    pageCountSection
                    artStyleSection
                    personalDetailsSection
                    advancedSettingsSection
                }
            }
        }
    }
}
```

### Design System Files

#### `DesignTokens.swift` - Visual Consistency
**Location**: `MemoirAI/Story/DesignTokens.swift`
**Purpose**: Centralized design system for consistent styling

**Color Palette**:
```swift
enum Tokens {
    // Warm parchment vibe
    static let bgPrimary = Color.safeHex("#F6F1E8", fallback: Color(red: 0.96, green: 0.94, blue: 0.91))
    static let bgWash = Color.safeHex("#EDE6DA", fallback: Color(red: 0.93, green: 0.90, blue: 0.85))
    static let ink = Color.safeHex("#2F2A25", fallback: Color(red: 0.18, green: 0.16, blue: 0.15))
    static let accent = Color.safeHex("#7C5C3A", fallback: Color(red: 0.49, green: 0.36, blue: 0.23))
    
    // Book-specific colors
    static let spineColor = Color.safeHex("#8B7355", fallback: Color(red: 0.55, green: 0.45, blue: 0.33))
    static let pageEdgeHighlight = Color.white.opacity(0.8)
}
```

**Typography**:
```swift
struct Typography {
    static let title = Font.system(size: 30, weight: .semibold, design: .serif)
    static let subtitle = Font.system(size: 17, weight: .regular, design: .default)
    static let button = Font.system(size: 20, weight: .semibold, design: .serif)
    static let chapterTitle = Font.system(size: 16, weight: .medium, design: .serif)
}
```

**Sizing**:
```swift
static let pageAspect: CGFloat = 3.0/4.0   // book page ratio (w:h)
static let bookMaxWidthPct: CGFloat = 0.86 // of safe area width
static let cornerRadius: CGFloat = 20
static let softShadow = (radius: CGFloat(14), y: CGFloat(6), opacity: Double(0.22))
```

#### `FreePreviewConfig.swift` - Subscription Limits
**Location**: `MemoirAI/Story/FreePreviewConfig.swift`
**Purpose**: Defines limits for free users

```swift
struct FreePreviewConfig {
    /// Maximum pages (images) a non-subscriber can generate in their single free preview.
    static let maxPagesWithoutSubscription = 1
}
```

### Book Editor Files (MemoirPreview Directory)

#### `BookEditorPrototypeView.swift` - Advanced Editor
**Location**: `MemoirAI/MemoirPreview/BookEditorPrototypeView.swift`
**Purpose**: Advanced book editing with drag-and-drop photo placement

**Key Features**:
- **Page-by-Page Editing**: Edit individual book pages
- **Photo Placement**: Drag photos to specific positions
- **Text Editing**: Modify page content
- **Real-time Preview**: See changes immediately
- **Photo Bank**: Access to all user photos

**UI Structure**:
```swift
struct BookEditorPrototypeView: View {
    @State private var pages: [EditorPage]
    @State private var currentPageIndex = 0
    @State private var showPhotoBank = false
    @State private var photoPositions: [UUID: CGPoint] = [:]
    @State private var draggedPhoto: UUID?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                BookishBackground()
                
                VStack {
                    // Navigation
                    pageNavigationView
                    
                    // Book content
                    BookView(
                        pages: pages,
                        currentPageIndex: $currentPageIndex,
                        photoPositions: $photoPositions,
                        draggedPhoto: $draggedPhoto,
                        selectedPhoto: $selectedPhoto,
                        availablePhotos: availablePhotos
                    )
                    
                    // Controls
                    editingControlsView
                }
            }
        }
    }
}
```

#### `EditorPage.swift` - Page Data Model
**Location**: `MemoirAI/MemoirPreview/EditorPage.swift`
**Purpose**: Represents an editable book page

**Properties**:
```swift
@MainActor
class EditorPage: ObservableObject, Identifiable {
    let id = UUID()
    
    // Editable properties
    @Published var title: String?
    @Published var bodyText: String
    @Published var photoData: Data?
    let isCover: Bool
    
    // Non-editable helpers
    private let memory: MemoryEntry?
    private let context: NSManagedObjectContext
}
```

**Key Methods**:
```swift
// Create pages from memories
static func pages(from memories: [MemoryEntry], context: NSManagedObjectContext) -> [EditorPage]

// Paginate text for book layout
private static func paginate(text: String, for size: CGSize, with font: UIFont) -> [String]

// Save changes to Core Data
func persistChanges()
```

#### `CoverSettings.swift` - Cover Configuration
**Location**: `MemoirAI/MemoirPreview/CoverSettings.swift`
**Purpose**: Manages book cover customization

```swift
struct CoverSettings: Codable {
    var title: String
    var subtitle: String
    var accentHex: String
    var coverPhotoData: Data?
}
```

#### `CoverEditorSheet.swift` - Cover Editor
**Location**: `MemoirAI/MemoirPreview/CoverEditorSheet.swift`
**Purpose**: Interface for editing book covers

**Features**:
- **Title/Subtitle Editing**: Customize book title
- **Color Selection**: Choose accent colors
- **Photo Upload**: Add cover photos
- **Real-time Preview**: See changes immediately

### Supporting Files

#### `PhotoPickerSheet.swift` - Photo Selection
**Location**: `MemoirAI/Story/PhotoPickerSheet.swift`
**Purpose**: Handles photo selection for books

**Features**:
- **Multiple Photo Selection**: Choose multiple photos
- **Library Integration**: Access to photo library
- **Permission Handling**: Manages photo permissions
- **Preview**: See selected photos before adding

#### `StorybookGalleryView.swift` - Book Gallery
**Location**: `MemoirAI/Story/StorybookGalleryView.swift`
**Purpose**: Shows all generated books

**Features**:
- **Book Thumbnails**: Visual preview of books
- **Book Management**: Delete or regenerate books
- **Search/Filter**: Find specific books
- **Download**: Export books as PDF

#### `ProfileSetupView.swift` - User Profile
**Location**: `MemoirAI/Story/ProfileSetupView.swift`
**Purpose**: Collects user information for book generation

**Data Collected**:
- **Personal Details**: Name, age, background
- **Photo**: Profile picture
- **Preferences**: Writing style, themes
- **Privacy Settings**: What to include/exclude

## 🔄 Complete User Flow

### 1. Entry Point (Homepage)
```
User clicks "Memoir Preview" → StorybookView
User clicks "Your Book" → StoryPage
```

### 2. Preview Flow
```
StorybookView → OpenBookView → PageCurlBookController
                ↓
            MockBookPage (sample content)
                ↓
            "Create your own book" → StoryPage
```

### 3. Creation Flow
```
StoryPage → SettingsView (configure)
         ↓
    StoryPageViewModel (generate)
         ↓
    OpenAI API (text + images)
         ↓
    Generated Book Display
         ↓
    Download/Share Options
```

### 4. Advanced Editing Flow
```
StoryPage → BookEditorPrototypeView
         ↓
    EditorPage (page-by-page editing)
         ↓
    CoverEditorSheet (cover customization)
         ↓
    Final Book Export
```

## 🎨 Design System Integration

### Color Scheme
- **Primary**: Warm parchment colors (#F6F1E8, #EDE6DA)
- **Text**: Soft black (#2F2A25)
- **Accent**: Terracotta brown (#7C5C3A)
- **Shadows**: Subtle black opacity (0.12-0.22)

### Typography
- **Titles**: Serif fonts (Georgia, Times New Roman)
- **Body**: System fonts for readability
- **Hierarchy**: Clear size and weight differences

### Layout Principles
- **Book Proportions**: 3:4 aspect ratio for pages
- **Margins**: Generous whitespace (16-20pt)
- **Spacing**: Consistent rhythm throughout
- **Shadows**: Soft, realistic book shadows

## 🔧 Technical Implementation

### State Management
- **@StateObject**: ViewModels for complex state
- **@AppStorage**: User preferences persistence
- **@EnvironmentObject**: Shared services (subscription, profile)
- **@State**: Local UI state

### Data Flow
```
User Input → View → ViewModel → Services → API → Response → UI Update
```

### Persistence Strategy
- **Core Data**: Memory entries and relationships
- **UserDefaults**: User preferences and settings
- **iCloud**: Cross-device sync and backup
- **File System**: Generated images and PDFs

### Performance Optimizations
- **Lazy Loading**: Load content as needed
- **Image Caching**: Cache generated images
- **Background Processing**: AI generation on background threads
- **Memory Management**: Proper cleanup of large assets

## 🚀 Key Features

### AI-Powered Generation
- **Text Generation**: Converts memories to narrative text
- **Image Generation**: Creates illustrations from text
- **Style Adaptation**: Different art styles (realistic, cartoon, kids)
- **Personalization**: Incorporates user details

### Subscription Integration
- **Free Preview**: One-page preview for non-subscribers
- **Premium Features**: Unlimited pages for subscribers
- **Paywall**: Seamless upgrade flow
- **Usage Tracking**: Monitor generation limits

### Book Export
- **PDF Generation**: High-quality PDF export
- **Image Quality**: Print-ready resolution
- **Customization**: Cover, layout, content options
- **Sharing**: Easy sharing and distribution

### Advanced Editing
- **Page-by-Page**: Edit individual pages
- **Photo Placement**: Drag-and-drop photo positioning
- **Text Editing**: Modify generated content
- **Cover Design**: Custom cover creation

## 🔍 Debugging & Testing

### Common Issues
1. **Generation Failures**: Check OpenAI API key and network
2. **Memory Issues**: Monitor image cache and cleanup
3. **Subscription Problems**: Verify RevenueCat configuration
4. **UI Glitches**: Check design token consistency

### Testing Checklist
- [ ] Preview flow works correctly
- [ ] Settings persist across app launches
- [ ] AI generation completes successfully
- [ ] Subscription limits are enforced
- [ ] PDF export generates correctly
- [ ] Photo picker works with permissions
- [ ] Page navigation is smooth
- [ ] Error handling shows appropriate messages

## 📚 Future Enhancements

### Planned Features
- **Multiple Book Templates**: Different book layouts
- **Collaborative Editing**: Family member contributions
- **Audio Integration**: Voice narration for books
- **Print Services**: Direct printing integration
- **Social Sharing**: Share books on social media
- **Advanced AI**: More sophisticated text generation

### Technical Improvements
- **Offline Support**: Generate books without internet
- **Batch Processing**: Generate multiple books
- **Cloud Storage**: Store books in iCloud Drive
- **Version Control**: Track book changes over time
- **Performance**: Faster generation and rendering

This comprehensive system provides a complete book creation experience, from simple previews to advanced AI-powered generation, with robust editing capabilities and professional export options. 