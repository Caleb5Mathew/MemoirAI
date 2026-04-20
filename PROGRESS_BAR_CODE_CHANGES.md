# Progress Bar - Quick Code Reference

## Files Modified
1. `StoryPageViewModel.swift` - Added progress tracking properties and status updates
2. `StoryPage.swift` - Enhanced UI display and progress syncing

## Key Changes Summary

### 1. New ViewModel Properties (StoryPageViewModel.swift)

```swift
// Added after line 39 (after @Published var pageItems)
@Published var currentMemoryIndex: Int = 0
@Published var totalMemories: Int = 0
@Published var currentStatus: String = ""
```

### 2. Status Updates in Generation Loop (StoryPageViewModel.swift)

#### Initialization (in generateStorybook function)
```swift
currentMemoryIndex = 0
totalMemories = 0
currentStatus = "Preparing..."
```

#### During memory selection
```swift
currentStatus = "Loading memories..."
// ... fetch entries ...
currentStatus = "Selecting best memories..."
// ... rank memories ...
totalMemories = chosen.count
currentStatus = "Organizing memories chronologically..."
```

#### In the main generation loop (for each memory)
```swift
// At start of loop
currentMemoryIndex = idx + 1
currentStatus = "Processing memory \(idx + 1) of \(totalMemories)"

// Before scene extraction
currentStatus = "Analyzing memory \(idx + 1) of \(totalMemories)..."

// Before title/character extraction
currentStatus = "Extracting details for memory \(idx + 1) of \(totalMemories)..."

// Before image generation
currentStatus = "Generating image \(idx + 1) of \(totalMemories)..."

// After image generation, before saving
currentStatus = "Saving memory \(idx + 1) of \(totalMemories)..."
```

### 3. Enhanced Loading View (StoryPage.swift)

```swift
@ViewBuilder
private func makeLoadingView() -> some View {
    VStack(spacing: 12) {
        // ... existing progress bar ...
        
        // NEW: Show current status
        if !vm.currentStatus.isEmpty {
            Text(vm.currentStatus)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(localColors.terracotta)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        
        // ... rest of view ...
    }
}
```

### 4. Progress Syncing (StoryPage.swift)

```swift
// In addLifecycleModifiers, updated the onChange for vm.progress
.onChange(of: vm.progress) { _, newProgress in
    // Sync realProgress with vm.progress for accurate progress bar
    realProgress = newProgress
}
```

### 5. Dynamic ETA Calculation (StoryPage.swift)

```swift
private var etaString: String {
    guard vm.isLoading, let start = generationStart else { return "" }
    let elapsed = Int(Date().timeIntervalSince(start))
    
    // If we have real progress > 10%, calculate ETA based on actual speed
    if realProgress > 0.1 {
        let estimatedTotal = Int(Double(elapsed) / realProgress)
        let remaining = max(0, estimatedTotal - elapsed)
        let mins = remaining / 60
        let secs = remaining % 60
        return "About \(mins)m \(secs)s remaining"
    } else {
        // Use initial estimate
        let remaining = max(0, totalEstimatedSeconds - elapsed)
        let mins = remaining / 60
        let secs = remaining % 60
        return "Estimated time: \(mins)m \(secs)s remaining"
    }
}
```

### 6. Updated Time Estimate (StoryPage.swift)

```swift
// In startActualGenerationProcess
// Changed from: pagesExpected * 12
// Changed to:
totalEstimatedSeconds = pagesExpected * 23
```

### 7. Reduced Fake Progress (StoryPage.swift)

```swift
// Changed from:
// let fakeIncrementPerTick = 0.004
// let targetFakeProgress = 0.4

// Changed to:
let fakeIncrementPerTick = 0.0025
let targetFakeProgress = 0.15
```

## Visual Comparison

### Before
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
40%
Estimated time: 2m 15s remaining
Please keep the app open...
```

### After
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
65%
Generating image 3 of 5...
About 1m 32s remaining
Please keep the app open...
```

## How It Works

1. **Initialization**: When generation starts, sets `totalMemories` and initial status
2. **Loop Start**: For each memory, updates `currentMemoryIndex` and `currentStatus`
3. **Step Updates**: Updates status at each major step (analyzing, extracting, generating, saving)
4. **Progress Sync**: ViewModel updates `progress`, View syncs to `realProgress` via onChange
5. **Display**: Loading view shows accurate percentage, current status, and dynamic ETA
6. **Completion**: Progress reaches 100% exactly when all memories are processed

## Status Message Examples

Real examples of status messages users will see:

```
Preparing...
Loading memories...
Selecting best memories...
Organizing memories chronologically...
Processing memory 1 of 5
Analyzing memory 1 of 5...
Extracting details for memory 1 of 5...
Generating image 1 of 5...
Saving memory 1 of 5...
Processing memory 2 of 5
Analyzing memory 2 of 5...
[... and so on ...]
```

## Testing Quick Checklist

✅ Status messages appear in correct sequence
✅ Progress bar moves smoothly (no sticking at 40%)
✅ Memory counter updates correctly (1 of 5, 2 of 5, etc.)
✅ ETA becomes more accurate after first memory
✅ Progress reaches exactly 100% when done
✅ All status text is visible and readable
✅ No performance issues with frequent updates

## Debug Tips

If progress tracking isn't working:

1. **Check VM Progress Updates**: Add print statement in ViewModel:
   ```swift
   print("🔍 Progress updated: \(progress), Memory \(currentMemoryIndex)/\(totalMemories)")
   ```

2. **Check View Progress Sync**: Add print in onChange:
   ```swift
   .onChange(of: vm.progress) { _, newProgress in
       print("🔍 View synced progress: \(newProgress)")
       realProgress = newProgress
   }
   ```

3. **Check Status Updates**: Verify status changes:
   ```swift
   print("📝 Status: \(currentStatus)")
   ```

4. **Check Display Logic**: Verify displayProgress calculation:
   ```swift
   print("📊 Display: fake=\(fakeProgress), real=\(realProgress), display=\(displayProgress)")
   ```

