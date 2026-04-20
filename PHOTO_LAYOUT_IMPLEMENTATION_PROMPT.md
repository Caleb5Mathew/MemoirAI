# Photo Layout Implementation Prompt - UserMemoriesBookView

## Overview
Implement a complete photo layout system for the "Create Your Own Book" feature in `UserMemoriesBookView`. Users should be able to add photo layouts to memoir pages, position them freely, and upload photos from multiple sources. The system must work seamlessly in both the main flipbook view and the zoom view.

## Current State Analysis

### Entry Point
- **Location**: `MemoirAI/Story/UserMemoriesBookView.swift`
- **Trigger**: User clicks "Create your own book" button in `StorybookView.swift` (line 349)
- **Current Issue**: Pages display only text content with no image support. The screenshot shows "UNTITLED PROMPT" with text-only formatting.

### Existing Infrastructure (Partially Implemented)
1. **Photo Layout Types** (`PhotoLayoutTemplate.swift`):
   - `PhotoLayoutType` enum: `.portrait`, `.landscape`, `.square`, `.custom`
   - `PhotoLayout` struct with frame positioning, image data, rotation, border styles
   - `PhotoLayoutBottomSheet` for selecting layout templates

2. **Photo Selection** (`PhotoFrameEditorView.swift`):
   - Uses `PhotosPicker` for photo library selection
   - Supports image adjustment (zoom, pan)
   - Missing: Camera capture and Files app integration

3. **FlipPage Model** (`FlipPage.swift`):
   - Has `photoLayouts: [PhotoLayout]?` property
   - Supports `.photoLayout` page type
   - Currently not properly rendered in flipbook

4. **JavaScript Rendering** (`flipbook.js`):
   - Has `photoLayout` case in `createPageHTML()` (line 1302)
   - Renders photo frames with placeholders
   - Missing: Proper interaction handling and drag/drop support

5. **Zoom View** (`PageZoomView` in `StorybookView.swift`):
   - Currently only shows text editing for photo layout pages (line 1350-1371)
   - Missing: Photo layout editing, positioning, and photo upload

## Requirements

### 1. Photo Layout Addition System

#### 1.1 Layout Selection
- **Current**: `PhotoLayoutBottomSheet` shows layout options (portrait, landscape, square, custom)
- **Enhancement Needed**:
  - When user taps "Add photos" button in `UserMemoriesBookView` (line 462), show `PhotoLayoutBottomSheet`
  - User selects a layout template (portrait, landscape, square, custom)
  - Layout is added to the **current page** being viewed
  - Layout appears centered on the page with default size based on template type
  - Multiple layouts can be added to the same page

#### 1.2 Visual Feedback
- New layout appears as a placeholder frame with:
  - Dashed border indicating it's empty
  - Camera icon and "Tap to add photo" text
  - Appropriate aspect ratio based on layout type
  - Subtle shadow for depth

### 2. Photo Layout Positioning & Manipulation

#### 2.1 Drag to Move
- **Implementation Location**: Both `FlipbookViewWithWebView` (WebView-based) and `PageZoomView` (native SwiftUI)
- **Behavior**:
  - Long press or tap-and-hold on a photo layout frame to enter "edit mode"
  - In edit mode, layout becomes draggable
  - Visual indicator shows layout is selected (highlighted border, selection handles)
  - Layout can be moved anywhere on the page
  - Constrain movement within page boundaries
  - Save position when drag ends

#### 2.2 Resize
- **Selection Handles**: Show resize handles at corners when layout is selected
- **Behavior**:
  - Drag corner handles to resize
  - Maintain aspect ratio for portrait/landscape/square types
  - Allow free resize for custom type
  - Minimum size: 50x50 points
  - Maximum size: Page dimensions minus margins

#### 2.3 Rotation
- **Rotation Handle**: Show rotation handle above selected layout
- **Behavior**:
  - Drag rotation handle to rotate layout
  - Visual feedback during rotation
  - Save rotation angle (0-360 degrees)

#### 2.4 Delete
- **Delete Button**: Show delete button (X) on selected layout
- **Behavior**:
  - Tap to delete layout from page
  - Show confirmation dialog before deletion
  - Remove layout from `photoLayouts` array

### 3. Photo Upload System

#### 3.1 Photo Source Options
When user taps on a photo layout placeholder (or existing photo), show action sheet with three options:

1. **Camera Roll / Photo Library**
   - Use `PhotosPicker` (already implemented in `PhotoFrameEditorView`)
   - Allow single photo selection
   - Show photo picker interface

2. **Take Photo**
   - Use `UIImagePickerController` with `.camera` source type
   - Present camera interface
   - Allow user to capture photo
   - Optionally allow cropping/editing before adding to layout

3. **Files**
   - Use `UIDocumentPickerViewController` or `PHPickerViewController` with file access
   - Allow selection of image files from Files app
   - Support common image formats (JPEG, PNG, HEIC)

#### 3.2 Photo Processing
- **Image Conversion**:
  - Convert selected image to base64 string for storage
  - Store in `PhotoLayout.imageData` property
  - Format: `"data:image/jpeg;base64,{base64String}"`
  - Compression quality: 0.6-0.8 for balance between quality and size

- **Image Display**:
  - Display image within layout frame
  - Use `.aspectRatio(contentMode: .fill)` with `.clipped()` for proper cropping
  - Support pinch-to-zoom and pan gestures for image positioning within frame (already in `PhotoFrameEditorView`)

### 4. Integration with Flipbook Rendering

#### 4.1 WebView Rendering (`flipbook.js`)
- **Current**: Basic photo layout rendering exists (line 1302-1340)
- **Enhancements Needed**:
  - Properly serialize `PhotoLayout` frames to JavaScript
  - Handle frame positioning (x, y, width, height, rotation)
  - Render photo frames as interactive elements
  - Support tap events to trigger photo upload
  - Support drag gestures for repositioning (via JavaScript touch events)
  - Update frame positions when dragged in WebView
  - Sync changes back to Swift `FlipPage` model

#### 4.2 Native Fallback Rendering
- **Current**: `OpenBookView` uses `convertFlipPagesToMockPages()` which doesn't handle photo layouts
- **Enhancement Needed**:
  - Create native SwiftUI rendering for photo layouts in fallback mode
  - Use `PhotoFrameView` component for each layout
  - Support drag, resize, rotation gestures
  - Maintain same functionality as WebView version

### 5. Zoom View Integration

#### 5.1 Photo Layout Display in Zoom View
- **Current**: `PageZoomView` shows placeholder text for photo layout pages (line 1350-1371)
- **Enhancement Needed**:
  - Render actual photo layouts when page type is `.photoLayout`
  - Display all `photoLayouts` from the page
  - Show photo frames with proper positioning, rotation, and images
  - Use `PhotoFrameView` or similar component for rendering

#### 5.2 Editing in Zoom View
- **Tap to Select**: Tap on photo layout to select it
- **Edit Mode**: When selected, show:
  - Selection handles (resize corners)
  - Rotation handle
  - Delete button
  - Move handle/indicator
- **Drag to Reposition**: Drag selected layout to new position
- **Resize**: Use corner handles to resize
- **Rotate**: Use rotation handle
- **Delete**: Tap delete button, confirm, remove from page
- **Add Photo**: Tap on empty layout or existing photo to open photo source picker
- **Save Changes**: Changes persist back to `flipbookPages` array

#### 5.3 Photo Upload in Zoom View
- **Same Options**: Camera roll, take photo, files (as described in section 3.1)
- **Integration**: Use `PhotoFrameEditorView` or create inline photo picker
- **Update**: After photo selection, update layout's `imageData` and refresh display

### 6. Page Formatting & Layout

#### 6.1 Text + Photo Layouts
- **Current Issue**: Pages show only text, no image placeholders
- **Enhancement Needed**:
  - Allow pages to have both text content AND photo layouts
  - Text should flow around photo layouts (or be positioned above/below)
  - When adding photo layout to text page, convert page type to `.mixed` or `.photoLayout`
  - Maintain text content when adding layouts

#### 6.2 Layout Constraints
- **Page Boundaries**: Photo layouts must stay within page margins
- **Overlap Handling**: Allow layouts to overlap (with z-ordering)
- **Text Wrapping**: If text exists, position layouts to not obscure important text
- **Minimum Spacing**: Optional: Maintain minimum spacing between layouts

### 7. Persistence & State Management

#### 7.1 Data Model Updates
- **FlipPage Model**: Already has `photoLayouts: [PhotoLayout]?` - ensure proper encoding/decoding
- **PhotoLayout Model**: Already has all needed properties:
  - `frame: CGRect` (position and size)
  - `imageData: String?` (base64 encoded)
  - `rotation: Double`
  - `borderStyle: BorderStyle`
- **Save Changes**: All modifications to layouts must persist in `flipbookPages` array

#### 7.2 State Synchronization
- **WebView ↔ Swift**: Changes made in WebView must sync to Swift model
- **Zoom View ↔ Main View**: Changes in zoom view must reflect in main flipbook view
- **Real-time Updates**: Use `@Binding` and state updates to trigger re-renders

### 8. User Experience Enhancements

#### 8.1 Visual Feedback
- **Selection State**: Clear visual indication when layout is selected
- **Drag Preview**: Show layout being dragged with slight opacity/scale change
- **Drop Zones**: Visual feedback for valid drop locations
- **Loading States**: Show loading indicator while processing/uploading photos

#### 8.2 Haptic Feedback
- **Selection**: Light haptic when selecting layout
- **Drag Start**: Medium haptic when starting drag
- **Drop**: Light haptic when dropping layout
- **Delete**: Strong haptic with confirmation

#### 8.3 Animations
- **Layout Addition**: Fade-in animation when adding new layout
- **Layout Movement**: Smooth animation when repositioning
- **Layout Deletion**: Fade-out animation before removal
- **Photo Upload**: Progress indicator or loading animation

### 9. Error Handling & Edge Cases

#### 9.1 Photo Upload Errors
- Handle camera permission denial gracefully
- Handle photo library access denial
- Handle file selection cancellation
- Show appropriate error messages

#### 9.2 Layout Constraints
- Prevent layouts from being dragged off-page
- Handle resize beyond page boundaries
- Handle rotation that causes layout to go off-page
- Snap to boundaries if needed

#### 9.3 Performance
- Optimize image compression for large photos
- Lazy load images in flipbook view
- Cache rendered layouts
- Limit number of layouts per page (suggest max 5-10)

## Implementation Files to Modify/Create

### Files to Modify:
1. **`MemoirAI/Story/UserMemoriesBookView.swift`**
   - Enhance `handleTemplateSelected()` to properly add layouts
   - Improve `handlePhotoFrameTap()` to show full photo source options
   - Add drag/drop gesture handling for layouts
   - Sync layout changes between views

2. **`MemoirAI/Story/StorybookView.swift`** (PageZoomView)
   - Replace placeholder text editor for photo layout pages (line 1350-1371)
   - Add photo layout rendering and editing
   - Integrate photo upload system
   - Add drag/resize/rotate/delete functionality

3. **`MemoirAI/Story/PhotoFrameEditorView.swift`**
   - Add camera capture option
   - Add Files app integration
   - Enhance photo source selection UI

4. **`MemoirAI/Resources/FlipbookBundle/flipbook.js`**
   - Enhance photo layout rendering
   - Add drag/drop JavaScript handlers
   - Sync position changes back to Swift
   - Improve photo frame interaction

5. **`MemoirAI/Story/FlipbookView.swift`**
   - Improve photo layout serialization
   - Handle layout position updates from JavaScript
   - Sync changes to Swift model

6. **`MemoirAI/Story/PhotoFrameView.swift`**
   - Enhance drag/resize/rotate gestures
   - Improve visual feedback
   - Add delete functionality

### Files to Create (if needed):
1. **`MemoirAI/Story/PhotoSourcePicker.swift`** (optional)
   - Unified photo source selection view
   - Handles camera, photo library, and files
   - Returns selected image to callback

2. **`MemoirAI/Story/PhotoLayoutEditorView.swift`** (optional)
   - Dedicated view for editing photo layouts in zoom view
   - Combines positioning, photo upload, and styling

## Testing Checklist

- [ ] Add photo layout to empty page
- [ ] Add photo layout to page with text
- [ ] Add multiple layouts to same page
- [ ] Upload photo from camera roll
- [ ] Upload photo by taking picture
- [ ] Upload photo from Files app
- [ ] Drag layout to reposition
- [ ] Resize layout using corner handles
- [ ] Rotate layout using rotation handle
- [ ] Delete layout from page
- [ ] Edit layout in zoom view
- [ ] Changes persist after closing zoom view
- [ ] Layouts display correctly in flipbook view
- [ ] Layouts display correctly in zoom view
- [ ] Layouts render correctly in WebView
- [ ] Layouts render correctly in native fallback
- [ ] Photo upload works in main view
- [ ] Photo upload works in zoom view
- [ ] Layout positioning works in main view
- [ ] Layout positioning works in zoom view
- [ ] Multiple layouts on same page work correctly
- [ ] Text and layouts coexist on same page
- [ ] Page formatting looks correct with layouts
- [ ] Performance is acceptable with multiple layouts/photos

## Success Criteria

1. ✅ User can tap "Add photos" and select a layout template
2. ✅ Layout appears on current page as placeholder
3. ✅ User can tap placeholder to upload photo (camera roll, camera, files)
4. ✅ User can drag layout to reposition it
5. ✅ User can resize layout using corner handles
6. ✅ User can rotate layout using rotation handle
7. ✅ User can delete layout from page
8. ✅ All functionality works in main flipbook view
9. ✅ All functionality works in zoom view
10. ✅ Changes persist and sync between views
11. ✅ Photos display correctly in both views
12. ✅ Page formatting accommodates layouts properly
13. ✅ No formatting issues like shown in screenshot (text-only display)

## Technical Notes

- Use SwiftUI's `@Binding` for two-way data flow
- Use `PhotosPicker` for photo library access (iOS 14+)
- Use `UIImagePickerController` for camera access
- Use `UIDocumentPickerViewController` for Files app access
- Store images as base64 strings in `PhotoLayout.imageData`
- Use `CGRect` for frame positioning (x, y, width, height)
- Use degrees (0-360) for rotation
- Coordinate system: Top-left origin (0,0) for page
- Ensure proper coordinate conversion between WebView and SwiftUI

## Next Steps After Implementation

1. Test all functionality thoroughly
2. Optimize image compression and loading
3. Add undo/redo functionality (optional)
4. Add layout templates/presets (optional)
5. Add border style customization (already exists, ensure it works)
6. Add photo filters/effects (optional)
7. Improve animations and transitions
8. Add accessibility support
9. Performance profiling and optimization










