// Memoir Flipbook JavaScript Wrapper
// Provides API for Swift WKWebView integration

let pageFlip;
let isReady = false;
let isUpdatingDimensions = false; // Prevent recursive calls
let dimensionUpdateTimeout = null; // For debouncing

// Function to get current container dimensions
function getContainerDimensions() {
    const containerElement = document.getElementById('book-container');
    const bookElement = document.getElementById('book');
    
    // Get the actual container dimensions with fallbacks
    let containerWidth = containerElement?.offsetWidth || containerElement?.clientWidth || 280;
    let containerHeight = containerElement?.offsetHeight || containerElement?.clientHeight || 374;
    
    // Ensure minimum dimensions
    containerWidth = Math.max(containerWidth, 280);
    containerHeight = Math.max(containerHeight, 374);
    
    // Ensure maximum dimensions to prevent overflow
    containerWidth = Math.min(containerWidth, 800);
    containerHeight = Math.min(containerHeight, 800);
    
    console.log('Flipbook: Current container dimensions:', {
        width: containerWidth,
        height: containerHeight,
        containerElement: containerElement,
        bookElement: bookElement
    });
    
    return { width: containerWidth, height: containerHeight };
}

// Function to update PageFlip dimensions with debouncing
function updatePageFlipDimensions() {
    if (!pageFlip) {
        console.log('Flipbook: PageFlip not available for dimension update');
        return;
    }
    
    // Prevent recursive calls
    if (isUpdatingDimensions) {
        console.log('Flipbook: Dimension update already in progress, skipping');
        return;
    }
    
    // Set flag to prevent recursion
    isUpdatingDimensions = true;
    
    try {
        const dimensions = getContainerDimensions();
        console.log('Flipbook: Updating PageFlip dimensions to:', dimensions);
        
        // Only update if dimensions have actually changed
        if (pageFlip.getState().pageFlipSize.width !== dimensions.width || 
            pageFlip.getState().pageFlipSize.height !== dimensions.height) {
            
            // Update PageFlip with new dimensions
            pageFlip.updateFromHtml();
            
            // Notify Swift of the dimension update
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
                window.webkit.messageHandlers.native.postMessage({
                    type: 'dimensionsUpdated',
                    dimensions: dimensions
                });
            }
        }
    } catch (error) {
        console.error('Flipbook: Error updating PageFlip dimensions:', error);
    } finally {
        // Reset the flag after a delay to prevent immediate re-entry
        setTimeout(() => {
            isUpdatingDimensions = false;
        }, 200);
    }
}

// Store pages data globally for PDF generation
let globalPagesData = [];

// Function to fix page positioning for single pages
function fixPagePositioning() {
    console.log('🔧 fixPagePositioning() CALLED');
    
    // Get current page index
    const currentIndex = pageFlip ? pageFlip.getCurrentPageIndex() : 0;
    const totalPages = pageFlip ? pageFlip.getPageCount() : 0;
    
    console.log(`🔧 Current page ${currentIndex} of ${totalPages}`);
    
    // Log all visible page containers and their positions
    const containers = document.querySelectorAll('.stf__item');
    containers.forEach((container, idx) => {
        const rect = container.getBoundingClientRect();
        const styles = window.getComputedStyle(container);
        console.log(`🔧 Container ${idx}: top=${rect.top}px, left=${rect.left}px, display=${styles.display}, position=${styles.position}`);
    });
    
    // Check visible pages
    const visibleItems = document.querySelectorAll('.stf__item:not([style*="display: none"])');
    const singleMode = document.querySelector('.stf__single-mode');
    
    console.log(`Flipbook: Visible items: ${visibleItems.length}, Single mode: ${!!singleMode}`);
    
    // If we have a single visible page
    if (visibleItems.length === 1 || singleMode) {
        const singleItem = visibleItems[0];
        if (!singleItem) return;
        
        const isCoverPage = singleItem.querySelector('.flipbook-page.cover-page');
        const isLastPage = currentIndex === totalPages - 1;
        const isRightSide = singleItem.classList.contains('--right');
        const isLeftSide = singleItem.classList.contains('--left');
        
        console.log(`Flipbook: Single page - Cover: ${!!isCoverPage}, Last: ${isLastPage}, Right: ${isRightSide}, Left: ${isLeftSide}`);
        
        // Cover pages should always be centered
        if (isCoverPage) {
            console.log('Flipbook: Cover page should be centered');
            
            // Remove any existing position classes
            singleItem.classList.remove('force-left-position', 'force-right-position');
            singleItem.classList.add('force-center-position');
            
            const block = singleItem.closest('.stf__block');
            if (block) {
                block.style.justifyContent = 'center';
                singleItem.style.margin = '0 auto';
            }
        }
        // Non-cover single pages positioning
        else {
            // Determine if page should be on left or right
            let shouldBeOnLeft = false;
            
            // In a book, odd pages (1, 3, 5...) are typically on the right
            // Even pages (0, 2, 4...) are on the left
            // But for single page display:
            // - Last page if odd total should be on left
            if (totalPages % 2 === 1 && isLastPage) {
                shouldBeOnLeft = true;
                console.log('Flipbook: Last page with odd total should be on left');
            }
            // Regular single pages follow even/odd rule
            else {
                shouldBeOnLeft = currentIndex % 2 === 0;
                console.log(`Flipbook: Page ${currentIndex} should be on ${shouldBeOnLeft ? 'left' : 'right'}`);
            }
            
            // Apply positioning fix if needed
            if (shouldBeOnLeft && isRightSide) {
                console.log('Flipbook: Fixing page position - moving from right to left');
                
                singleItem.classList.remove('force-center-position', 'force-right-position');
                singleItem.classList.add('force-left-position');
                
                const block = singleItem.closest('.stf__block');
                if (block) {
                    block.style.justifyContent = 'flex-start';
                    singleItem.style.marginLeft = '0';
                    singleItem.style.marginRight = 'auto';
                }
            } else if (!shouldBeOnLeft && isLeftSide) {
                console.log('Flipbook: Fixing page position - moving from left to right');
                
                singleItem.classList.remove('force-center-position', 'force-left-position');
                singleItem.classList.add('force-right-position');
                
                const block = singleItem.closest('.stf__block');
                if (block) {
                    block.style.justifyContent = 'flex-end';
                    singleItem.style.marginLeft = 'auto';
                    singleItem.style.marginRight = '0';
                }
            } else {
                console.log('Flipbook: Page is correctly positioned');
            }
        }
    }
    // For double page spreads
    else if (visibleItems.length === 2) {
        console.log('Flipbook: Double page spread detected - no positioning fix needed');
    }
}

// Backward compatibility - keep the old function name but use new logic
function fixCoverPagePosition() {
    fixPagePositioning();
}

// Page tap handler for native iOS zoom
function handlePageTap(pageIndex) {
    console.log('📖 JavaScript handlePageTap: Sending page index', pageIndex, 'to Swift');
    console.log('📖 JavaScript: Total processed pages count:', window.processedPagesCount || 'unknown');
    
    // Notify Swift to show native zoom
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
        window.webkit.messageHandlers.native.postMessage({
            type: 'pageTapped',
            pageIndex: pageIndex
        });
    }
}

// Photo frame drag state
let dragState = {
    isDragging: false,
    frameId: null,
    frameIndex: null,
    startX: 0,
    startY: 0,
    offsetX: 0,
    offsetY: 0,
    element: null
};

// Photo frame drag start handler
function handlePhotoFrameDragStart(event, frameId, frameIndex) {
    const touch = event.touches[0];
    const element = event.currentTarget;
    const rect = element.getBoundingClientRect();
    const containerRect = element.parentElement.getBoundingClientRect();
    
    // CRITICAL: Stop all event propagation to prevent page flip
    event.stopPropagation();
    event.stopImmediatePropagation();
    event.preventDefault();
    
    dragState.isDragging = true;
    dragState.frameId = frameId;
    dragState.frameIndex = frameIndex;
    dragState.startX = touch.clientX;
    dragState.startY = touch.clientY;
    dragState.offsetX = touch.clientX - rect.left;
    dragState.offsetY = touch.clientY - rect.top;
    dragState.element = element;
    
    // Disable page flipping during drag
    if (pageFlip && typeof pageFlip.disable === 'function') {
        pageFlip.disable();
    }
    
    // Add body class to prevent page interactions
    document.body.classList.add('dragging-photo-frame');
    
    // Add dragging class for visual feedback
    element.classList.add('photo-frame-dragging');
}

// Photo frame drag handler
function handlePhotoFrameDrag(event, frameId, frameIndex) {
    if (!dragState.isDragging || dragState.frameId !== frameId) {
        return;
    }
    
    // CRITICAL: Stop all event propagation to prevent page flip
    event.stopPropagation();
    event.stopImmediatePropagation();
    event.preventDefault();
    
    const touch = event.touches[0];
    const element = dragState.element;
    const containerRect = element.parentElement.getBoundingClientRect();
    
    // Calculate new position relative to container
    let newX = touch.clientX - containerRect.left - dragState.offsetX;
    let newY = touch.clientY - containerRect.top - dragState.offsetY;
    
    // Get original frame dimensions
    const originalX = parseFloat(element.getAttribute('data-original-x')) || 0;
    const originalY = parseFloat(element.getAttribute('data-original-y')) || 0;
    const frameWidth = parseFloat(element.style.width) || 150;
    const frameHeight = parseFloat(element.style.height) || 200;
    
    // Constrain to container bounds (with margin)
    const margin = 10;
    newX = Math.max(margin, Math.min(newX, containerRect.width - frameWidth - margin));
    newY = Math.max(margin, Math.min(newY, containerRect.height - frameHeight - margin));
    
    // Update position
    element.style.left = newX + 'px';
    element.style.top = newY + 'px';
}

// Photo frame drag end handler
function handlePhotoFrameDragEnd(event, frameId, frameIndex) {
    if (!dragState.isDragging || dragState.frameId !== frameId) {
        return;
    }
    
    // CRITICAL: Stop all event propagation to prevent page flip
    event.stopPropagation();
    event.stopImmediatePropagation();
    event.preventDefault();
    
    const element = dragState.element;
    const containerRect = element.parentElement.getBoundingClientRect();
    
    // Get final position
    const finalX = parseFloat(element.style.left) || 0;
    const finalY = parseFloat(element.style.top) || 0;
    const frameWidth = parseFloat(element.style.width) || 150;
    const frameHeight = parseFloat(element.style.height) || 200;
    
    // Check if we actually moved (not just a tap)
    const moved = Math.abs(dragState.startX - (event.changedTouches[0]?.clientX || dragState.startX)) > 5 ||
                  Math.abs(dragState.startY - (event.changedTouches[0]?.clientY || dragState.startY)) > 5;
    
    // Re-enable page flipping
    if (pageFlip && typeof pageFlip.enable === 'function') {
        pageFlip.enable();
    }
    
    // Remove body class to re-enable page interactions
    document.body.classList.remove('dragging-photo-frame');
    
    // Remove dragging class
    element.classList.remove('photo-frame-dragging');
    
    // Update original position attributes
    element.setAttribute('data-original-x', finalX.toString());
    element.setAttribute('data-original-y', finalY.toString());
    
    // Get current page index
    const currentPageIndex = pageFlip ? pageFlip.getCurrentPageIndex() : 0;
    
    // Only notify Swift if we actually moved
    if (moved && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
        window.webkit.messageHandlers.native.postMessage({
            type: 'photoFrameMoved',
            pageIndex: currentPageIndex,
            frameId: frameId,
            frameIndex: frameIndex,
            newPosition: {
                x: finalX,
                y: finalY,
                width: frameWidth,
                height: frameHeight
            }
        });
    }
    
    // Reset drag state after a short delay to prevent click from firing
    setTimeout(() => {
        dragState.isDragging = false;
        dragState.frameId = null;
        dragState.frameIndex = null;
        dragState.element = null;
    }, moved ? 0 : 300); // If moved, reset immediately; if tap, wait 300ms
}

// Photo frame click handler
function handlePhotoFrameClick(event, frameId, frameIndex) {
    // If we just finished dragging, don't trigger click
    if (dragState.isDragging || dragState.frameId === frameId) {
        // Clear drag state to allow future clicks
        setTimeout(() => {
            dragState.isDragging = false;
            dragState.frameId = null;
        }, 100);
        return;
    }
    
    console.log('Flipbook: Photo frame clicked, id:', frameId, 'index:', frameIndex);
    
    // Prevent event from bubbling to page tap
    if (event) {
        event.stopPropagation();
        event.preventDefault();
    }
    
    // Get current page index
    const currentPageIndex = pageFlip ? pageFlip.getCurrentPageIndex() : 0;
    
    // Notify Swift to open photo picker for this specific frame
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
        window.webkit.messageHandlers.native.postMessage({
            type: 'photoFrameTapped',
            pageIndex: currentPageIndex,
            frameId: frameId,
            frameIndex: frameIndex
        });
    }
}

// PDF Download functionality - captures actual rendered pages
window.downloadPDF = async function(isKidsBook = false) {
    console.log('Flipbook: Starting PDF download with page capture... Kids book:', isKidsBook);
    
    if (!pageFlip) {
        console.error('Flipbook: PageFlip not initialized');
        return;
    }
    
    // Check if html2canvas is available
    if (typeof html2canvas === 'undefined') {
        console.error('Flipbook: html2canvas library not loaded');
        // Fallback to basic implementation
        downloadPDFBasic(isKidsBook);
        return;
    }
    
    const totalPages = pageFlip.getPageCount ? pageFlip.getPageCount() : 0;
    if (totalPages === 0) {
        console.error('Flipbook: No pages to download');
        return;
    }
    
    // Store current page to restore later
    const currentPageIndex = pageFlip.getCurrentPageIndex ? pageFlip.getCurrentPageIndex() : 0;
    const pdfContent = [];
    const bookElement = document.getElementById('book');
    
    // Hide navigation arrows temporarily
    const navArrows = document.getElementById('navigation-arrows');
    if (navArrows) navArrows.style.display = 'none';
    
    try {
        console.log(`Flipbook: Capturing ${totalPages} pages...`);
        
        // Capture each page
        for (let i = 0; i < totalPages; i++) {
            console.log(`Flipbook: Capturing page ${i + 1} of ${totalPages}`);
            
            // Navigate to the page
            pageFlip.flip(i);
            
            // Wait for page flip animation to complete
            await new Promise(resolve => setTimeout(resolve, 800));
            
            // Find the specific page element to capture using data-page-index
            const pageSelector = `.flipbook-page[data-page-index="${i}"]`;
            let pageToCapture = bookElement.querySelector(pageSelector);
            
            // If specific page not found (e.g. cover might not have index logic same way), try fallback
            if (!pageToCapture) {
                console.warn(`Flipbook: Could not find page with index ${i}, attempting fallback logic`);
                
                // Check if we're on cover page (single page mode)
                if (i === 0) {
                    // Cover page - look for the visible page
                    pageToCapture = bookElement.querySelector('.stf__item.--right .flipbook-page.cover-page') ||
                                   bookElement.querySelector('.flipbook-page.cover-page');
                } else {
                    // Regular pages - find the visible page(s)
                    // Note: This fallback might capture a spread if we fail to find the specific page
                    const visiblePages = bookElement.querySelectorAll('.stf__item .flipbook-page');
                    if (visiblePages.length > 0) {
                        pageToCapture = visiblePages[0]; // Prefer single page capture in fallback
                    }
                }
            }
            
            // Fallback to book element if absolutely nothing found
            if (!pageToCapture) {
                console.warn(`Flipbook: Could not find specific page element for page ${i + 1}, using book container`);
                pageToCapture = bookElement;
            }
            
            console.log(`Flipbook: Capturing element:`, pageToCapture.className || 'element');
            
            // Determine dimensions based on standard book sizes
            // Comic, Realistic, Custom: 8.5 x 11 inches (portrait) = 8.5/11 aspect ratio
            // Kids Book: 11 x 8.5 inches (landscape) = 11/8.5 aspect ratio
            const rect = pageToCapture.getBoundingClientRect();
            const actualAspectRatio = rect.width / rect.height;
            console.log(`Flipbook: Page element dimensions: ${rect.width}x${rect.height} (Ratio: ${actualAspectRatio})`);
            
            // Standard aspect ratios
            const targetAspectRatio = isKidsBook ? (11.0 / 8.5) : (8.5 / 11.0);
            console.log(`Flipbook: Target aspect ratio: ${targetAspectRatio} (${isKidsBook ? 'landscape' : 'portrait'})`);
            
            let targetWidth, targetHeight;
            
            // Set base dimensions based on book type with correct aspect ratio
            // Use high resolution: 300 DPI equivalent
            if (isKidsBook) {
                // Kids books: 11 x 8.5 inches at 300 DPI = 3300 x 2550 pixels
                targetWidth = 3300; 
                targetHeight = 2550;
            } else {
                // Regular/Realistic/Comic: 8.5 x 11 inches at 300 DPI = 2550 x 3300 pixels
                targetWidth = 2550;
                targetHeight = 3300;
            }
            
            console.log(`Flipbook: Using ${isKidsBook ? 'kids book' : 'regular book'} dimensions: ${targetWidth}x${targetHeight}`);
            
            let canvasOptions = {
                backgroundColor: '#faf8f3', // Paper color
                scale: 3, // High quality scale
                logging: false,
                useCORS: true,
                allowTaint: true,
                letterRendering: true, 
                imageTimeout: 0,
                width: targetWidth,
                height: targetHeight
            };
            
            // Capture with configured settings
            const canvas = await html2canvas(pageToCapture, canvasOptions);
            
            // Clean up temporary spread container if created
            if (pageToCapture.parentElement === bookElement && !pageToCapture.classList.contains('stf__item')) {
                pageToCapture.remove();
            }
            
            // Convert to JPEG with high quality
            const imageData = canvas.toDataURL('image/jpeg', 0.95);
            pdfContent.push(imageData);
        }
        
        console.log('Flipbook: All pages captured successfully');
        
        // Create filename with timestamp
        const timestamp = new Date().toISOString().slice(0, 10);
        const filename = `memoir-book-${timestamp}.pdf`;
        
        // Send to Swift for PDF generation
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'downloadPDF',
                pages: pdfContent,
                filename: filename,
                pageCount: totalPages
            });
            console.log('Flipbook: Sent captured pages to Swift for PDF generation');
        } else {
            console.error('Flipbook: Unable to communicate with native app');
        }
        
    } catch (error) {
        console.error('Flipbook: Error capturing pages:', error);
    } finally {
        // Restore navigation arrows
        if (navArrows) navArrows.style.display = 'flex';
        
        // Return to original page
        pageFlip.flip(currentPageIndex);
        
        console.log('Flipbook: PDF download process completed');
    }
};

// Fallback basic PDF implementation (without html2canvas)
function downloadPDFBasic(isKidsBook = false) {
    console.log('Flipbook: Using basic PDF generation (fallback), Kids book:', isKidsBook);
    
    if (!globalPagesData || globalPagesData.length === 0) {
        console.error('Flipbook: No pages available for PDF export');
        return;
    }
    
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    // Keep fallback dimensions aligned with standard export sizes.
    const pageWidth = isKidsBook ? 792 : 612;
    const pageHeight = isKidsBook ? 612 : 792;
    canvas.width = pageWidth;
    canvas.height = pageHeight;
    
    const pdfContent = [];
    
    globalPagesData.forEach((page, index) => {
        ctx.fillStyle = '#faf8f3';
        ctx.fillRect(0, 0, pageWidth, pageHeight);
        ctx.fillStyle = '#3a3a3a';
        ctx.font = '12px Baskerville, Georgia, serif';
        
        const margin = 60;
        const contentWidth = pageWidth - (margin * 2);
        let y = margin;
        if (page.title) {
            ctx.font = 'bold 18px Baskerville, Georgia, serif';
            ctx.fillText(page.title, margin, y);
            y += 30;
        }
        
        if (page.text || page.caption) {
            ctx.font = '11px Baskerville, Georgia, serif';
            const text = page.text || page.caption || '';
            const lines = wrapText(ctx, text, contentWidth);
            lines.forEach(line => {
                ctx.fillText(line, margin, y);
                y += 16;
            });
        }
        
        pdfContent.push(canvas.toDataURL('image/jpeg', 0.95));
    });
    
    const timestamp = new Date().toISOString().slice(0, 10);
    const filename = `memoir-book-basic-${timestamp}.pdf`;
    
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
        window.webkit.messageHandlers.native.postMessage({
            type: 'downloadPDF',
            pages: pdfContent,
            filename: filename
        });
    }
}

// Helper function to wrap text
function wrapText(context, text, maxWidth) {
    const words = text.split(' ');
    const lines = [];
    let currentLine = words[0];
    
    for (let i = 1; i < words.length; i++) {
        const word = words[i];
        const width = context.measureText(currentLine + ' ' + word).width;
        if (width < maxWidth) {
            currentLine += ' ' + word;
        } else {
            lines.push(currentLine);
            currentLine = word;
        }
    }
    lines.push(currentLine);
    return lines;
}

// Initialize the flipbook when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    console.log('Flipbook: DOM loaded');
    
    const bookElement = document.getElementById('book');
    const containerElement = document.getElementById('book-container');
    
    console.log('Flipbook: Container element:', containerElement);
    console.log('Flipbook: Container dimensions:', {
        offsetWidth: containerElement?.offsetWidth,
        offsetHeight: containerElement?.offsetHeight,
        clientWidth: containerElement?.clientWidth,
        clientHeight: containerElement?.clientHeight,
        scrollWidth: containerElement?.scrollWidth,
        scrollHeight: containerElement?.scrollHeight
    });
    
    console.log('Flipbook: Book element:', bookElement);
    console.log('Flipbook: Book dimensions:', {
        offsetWidth: bookElement?.offsetWidth,
        offsetHeight: bookElement?.offsetHeight,
        clientWidth: bookElement?.clientWidth,
        clientHeight: bookElement?.clientHeight
    });
    
    if (!bookElement) {
        console.error('Flipbook: Book element not found!');
        // Still notify Swift that we're ready (even with error)
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'ready',
                error: 'Book element not found'
            });
        }
        return;
    }

    // Check if St.PageFlip is available
    console.log('Flipbook: Checking St.PageFlip availability...');
    console.log('Flipbook: typeof St:', typeof St);
    console.log('Flipbook: St object:', St);
    console.log('Flipbook: St.PageFlip:', St?.PageFlip);
    
    if (typeof St === 'undefined' || !St.PageFlip) {
        console.error('Flipbook: St.PageFlip not available!');
        console.error('Flipbook: St is undefined:', typeof St === 'undefined');
        console.error('Flipbook: St.PageFlip is undefined:', !St?.PageFlip);
        
        // Notify Swift of the error
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'ready',
                error: 'St.PageFlip not available'
            });
        }
        return;
    }
    
    console.log('Flipbook: St.PageFlip is available!');

    try {
        // Get actual container dimensions
        const dimensions = getContainerDimensions();
        
        console.log('Flipbook: Using container dimensions:', dimensions);
        
        // Small delay to ensure container is properly sized
        setTimeout(() => {
            // Initialize StPageFlip
            console.log('Flipbook: Initializing PageFlip with dimensions:', dimensions);
            console.log('Flipbook: Book element for PageFlip:', bookElement);
            
            try {
                // Try minimal configuration first - REVERTED to working config
                pageFlip = new St.PageFlip(bookElement, {
                    width: dimensions.width,
                    height: dimensions.height,
                    size: "stretch",
                    showCover: true,  // Show single cover page instead of spread
                    startPage: 0,     // Start at cover page
                    drawShadow: true,
                    flippingTime: 1000,
                    usePortrait: false,
                    startZIndex: 0,
                    autoSize: true,
                    maxShadowOpacity: 0.3
                });
                console.log('Flipbook: PageFlip initialized with minimal config (reverted)');
                console.log('Flipbook: PageFlip initialized successfully with minimal config:', pageFlip);
                
                // REMOVED: Simple div test that was interfering with book rendering
                console.log('Flipbook: Skipping simple div test to avoid interference');
                
                // DEBUG: Check PageFlip state immediately after initialization
                console.log('Flipbook: PageFlip state after init:', {
                    hasLoadFromHTML: typeof pageFlip.loadFromHTML === 'function',
                    hasFlipNext: typeof pageFlip.flipNext === 'function',
                    hasFlipPrev: typeof pageFlip.flipPrev === 'function',
                    hasGetCurrentPageIndex: typeof pageFlip.getCurrentPageIndex === 'function',
                    hasGetPageCount: typeof pageFlip.getPageCount === 'function'
                });
                
            } catch (error) {
                console.error('Flipbook: Error initializing PageFlip:', error);
                console.error('Flipbook: Error stack:', error.stack);
                throw error;
            }
            
            console.log('Flipbook: StPageFlip initialized successfully');
            console.log('Flipbook: StPageFlip instance:', pageFlip);
            
            console.log('Flipbook: StPageFlip initialized with config:', {
                width: dimensions.width,
                height: dimensions.height,
                size: "stretch",
                showCover: true,  // Show single cover page
                autoSize: true
            });
            
            // DEBUG: Verify cover page configuration
            console.log('Flipbook: Cover page should be first page with showCover: true');
            
            // Fix cover page positioning after PageFlip initializes
            setTimeout(() => {
                fixCoverPagePosition();
            }, 100);
            
            // Listen for flip events and notify Swift
            // CRITICAL: This is the ONLY flip handler - all flip logic goes here
            pageFlip.on('flip', function(e) {
                const debugMsg = `🔄 FLIP EVENT: Flipped to index: ${e.data}`;
                console.log(debugMsg);
                
                // Track if this is a cover transition
                const isFlippingFromCover = e.data === 1;
                const isFlippingToCover = e.data === 0;
                const coverDebug = `🔄 Cover transition? From: ${isFlippingFromCover}, To: ${isFlippingToCover}`;
                console.log(coverDebug);
                
                // CRITICAL: Reset flipping flags AFTER animation completes (1100ms)
                // The flip animation takes 1000ms, so we wait slightly longer to ensure it's done
                // This prevents rapid clicks from queuing up multiple flips
                setTimeout(() => {
                    globalIsFlipping = false;
                    console.log('Flipbook: Reset globalIsFlipping flag after animation completed');
                }, 1100);
                
                // Send debug to Swift
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
                    window.webkit.messageHandlers.native.postMessage({
                        type: 'debug',
                        message: debugMsg + ' | ' + coverDebug
                    });
                    
                    window.webkit.messageHandlers.native.postMessage({
                        type: 'flip',
                        index: e.data
                    });
                }
                
                // Fix page positioning after flip, but skip cover transitions to prevent glitches
                if (!isFlippingFromCover && !isFlippingToCover) {
                    const willFixMsg = '🔄 Will apply positioning fix in 100ms (non-cover page)';
                    console.log(willFixMsg);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
                        window.webkit.messageHandlers.native.postMessage({
                            type: 'debug',
                            message: willFixMsg
                        });
                    }
                    setTimeout(() => {
                        const executingMsg = '🔧 Executing fixPagePositioning() now';
                        console.log(executingMsg);
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
                            window.webkit.messageHandlers.native.postMessage({
                                type: 'debug',
                                message: executingMsg
                            });
                        }
                        fixPagePositioning();
                    }, 100);
                } else {
                    const skipMsg = '🔄 SKIPPING positioning fix (cover transition)';
                    console.log(skipMsg);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
                        window.webkit.messageHandlers.native.postMessage({
                            type: 'debug',
                            message: skipMsg
                        });
                    }
                }
                
                // Update navigation button states after flip completes
                setTimeout(() => {
                    updateNavigationState();
                }, 1100);
            });

            // Listen for state changes
            pageFlip.on('changeState', function(e) {
                console.log('🔄 STATE CHANGE:', e.data);
                
                // Log visible pages during state change
                const visiblePages = document.querySelectorAll('.stf__item:not([style*="display: none"])');
                console.log('🔄 Visible pages during state change:', visiblePages.length);
                visiblePages.forEach((item, idx) => {
                    const page = item.querySelector('.flipbook-page');
                    const isCover = page && page.classList.contains('cover-page');
                    const rect = item.getBoundingClientRect();
                    console.log(`🔄   Page ${idx}: cover=${isCover}, top=${rect.top}px, height=${rect.height}px`);
                });
                
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
                    window.webkit.messageHandlers.native.postMessage({
                        type: 'stateChange',
                        state: e.data
                    });
                }
            });
            
            // Listen for resize events - but don't trigger dimension updates to avoid recursion
            pageFlip.on('resize', function(e) {
                console.log('PageFlip: Resized to:', e.data);
                // Don't call any dimension update functions to prevent recursion
            });
            
            // Set up navigation arrows
            console.log('Flipbook: About to setup navigation arrows...');
            setupNavigationArrows();
            console.log('Flipbook: Navigation arrows setup completed');
            
            // Set up page click handlers for zoom
            setupPageClickHandlers();
            
            // Notify Swift that we're ready
            console.log('Flipbook: Sending ready message to Swift');
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
                window.webkit.messageHandlers.native.postMessage({
                    type: 'ready'
                });
            }
        }, 100); // 100ms delay
        
    } catch (error) {
        console.error('Flipbook: Error initializing StPageFlip:', error);
        // Notify Swift of the error
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'ready',
                error: error.message
            });
        }
    }
});

// API functions exposed to Swift
window.renderPages = function(pagesJSON) {
    console.log('Flipbook: renderPages called with:', pagesJSON);
    
    // DEBUG: Check if book element exists and has content
    const bookElement = document.getElementById('book');
    console.log('Flipbook: Book element before rendering:', bookElement);
    console.log('Flipbook: Book element innerHTML before rendering:', bookElement?.innerHTML);
    console.log('Flipbook: Book element dimensions before rendering:', {
        offsetWidth: bookElement?.offsetWidth,
        offsetHeight: bookElement?.offsetHeight,
        clientWidth: bookElement?.clientWidth,
        clientHeight: bookElement?.clientHeight
    });
    
    if (!pageFlip) {
        console.error('Flipbook: PageFlip not initialized');
        // Notify Swift of the error
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'error',
                message: 'PageFlip not initialized'
            });
        }
        return;
    }
    
    try {
        const pages = JSON.parse(pagesJSON);
        console.log('Flipbook: Parsed pages:', pages);
        
        // Store pages globally for PDF export
        globalPagesData = pages;
        
        // Process pages and handle text overflow
        const processedPages = [];
        let pageNumber = 1;
        
        console.log('📖 JavaScript renderPages: Starting with', pages.length, 'original pages');
        
        pages.forEach((page, originalIndex) => {
            if (page.type === 'text' || page.type === 'leftBars') {
                // Check if text needs to be split across multiple pages
                const fullText = page.text || page.caption || '';
                const words = fullText.split(/\s+/).length;
                
                console.log(`📖 JS Page ${originalIndex} (${page.title || 'No title'}, type: ${page.type}): ${words} words`);
                
                if (words > 150) {
                    // Split text into multiple pages
                    const textPages = splitTextIntoPages(fullText, 150);
                    textPages.forEach((pageText, index) => {
                        const isContinuation = index > 0;
                        const pageData = {
                            ...page,
                            text: pageText,
                            caption: pageText
                        };
                        processedPages.push({
                            data: pageData,
                            pageNumber: page.type === 'cover' ? null : pageNumber++,
                            isContinuation
                        });
                        console.log(`   → JS: Split part ${index + 1}`);
                    });
                    console.log(`   → JS: Total split into ${textPages.length} pages`);
                } else {
                    processedPages.push({
                        data: page,
                        pageNumber: page.type === 'cover' ? null : pageNumber++,
                        isContinuation: false
                    });
                    console.log('   → JS: No split needed (<= 150 words)');
                }
            } else {
                processedPages.push({
                    data: page,
                    pageNumber: page.type === 'cover' ? null : pageNumber++,
                    isContinuation: false
                });
                console.log(`📖 JS Page ${originalIndex} (${page.type}): Not text/leftBars, no split`);
            }
        });
        
        console.log('📖 JavaScript renderPages: Created', processedPages.length, 'expanded pages from', pages.length, 'original pages');
        
        // Store processed pages count for debugging
        window.processedPagesCount = processedPages.length;
        
        // Convert HTML strings to DOM elements
        const domPages = processedPages.map((pageInfo, htmlPageIndex) => {
            const htmlString = createPageHTML(pageInfo.data, pageInfo.pageNumber, pageInfo.isContinuation);
            console.log('Flipbook: Generated HTML for page:', pageInfo.data.type, htmlString);
            
            // Create a temporary container to parse HTML
            const tempDiv = document.createElement('div');
            tempDiv.innerHTML = htmlString.trim();
            
            // Get the first child element (the actual page div)
            const pageElement = tempDiv.firstElementChild;
            if (!pageElement) {
                console.error('Flipbook: Failed to create DOM element for page:', page.type);
                return null;
            }
            
            // CRITICAL: Add data-page-index to identify which expanded page this is
            pageElement.setAttribute('data-page-index', htmlPageIndex);
            console.log(`Flipbook: Set data-page-index=${htmlPageIndex} on page element`);
            
            console.log('Flipbook: Created DOM element:', pageElement);
            console.log('Flipbook: Page element tag name:', pageElement.tagName);
            console.log('Flipbook: Page element class name:', pageElement.className);
            console.log('Flipbook: Page element dimensions:', {
                offsetWidth: pageElement.offsetWidth,
                offsetHeight: pageElement.offsetHeight,
                clientWidth: pageElement.clientWidth,
                clientHeight: pageElement.clientHeight
            });
            
            // DEBUG: Check if element has content
            console.log('Flipbook: Page element innerHTML:', pageElement.innerHTML);
            
            return pageElement;
        }).filter(element => element !== null); // Filter out any nulls
        
        console.log('Flipbook: DOM pages ready:', domPages.length);
        
        // Safely check PageFlip state
        try {
            console.log('Flipbook: PageFlip current state before loading:', pageFlip.getState ? pageFlip.getState() : 'getState not available');
            console.log('Flipbook: PageFlip methods available:', Object.getOwnPropertyNames(pageFlip));
            console.log('Flipbook: PageFlip prototype methods:', Object.getOwnPropertyNames(Object.getPrototypeOf(pageFlip)));
        } catch (e) {
            console.log('Flipbook: Could not get PageFlip state:', e.message);
        }
        
        // Load the DOM elements into PageFlip
        console.log('Flipbook: About to load DOM pages into PageFlip:', domPages.length);
        console.log('Flipbook: DOM pages:', domPages);
        
        // DEBUG: Check book element before PageFlip
        const bookElementBefore = document.getElementById('book');
        console.log('Flipbook: Book element BEFORE PageFlip:', bookElementBefore);
        console.log('Flipbook: Book innerHTML BEFORE PageFlip:', bookElementBefore?.innerHTML);
        console.log('Flipbook: Book children BEFORE PageFlip:', bookElementBefore?.children?.length);
        
        // Save current page before reloading (only if pages are already loaded)
        let currentPageIndex = 0;
        try {
            // Check if pageFlip has pages loaded before trying to get current index
            if (pageFlip && pageFlip.getPageCount && pageFlip.getPageCount() > 0) {
                currentPageIndex = pageFlip.getCurrentPageIndex ? pageFlip.getCurrentPageIndex() : 0;
                console.log('Flipbook: Saving current page index before reload:', currentPageIndex);
            } else {
                console.log('Flipbook: No pages loaded yet, skipping page save');
            }
        } catch (error) {
            console.log('Flipbook: Could not get current page (first load):', error.message);
            currentPageIndex = 0;
        }
        
        try {
            console.log('Flipbook: Calling pageFlip.loadFromHTML...');
            pageFlip.loadFromHTML(domPages);
            console.log('Flipbook: loadFromHTML completed successfully');
            
            // Restore the page after loading, but only if we're not already on that page
            // CRITICAL: Set flag before restoring to prevent flip event from triggering another render
            if (currentPageIndex > 0) {
                setTimeout(() => {
                    const currentPage = pageFlip.getCurrentPageIndex ? pageFlip.getCurrentPageIndex() : 0;
                    if (currentPage !== currentPageIndex) {
                        console.log('Flipbook: Restoring page to index:', currentPageIndex, '(from', currentPage, ')');
                        // Set flag to prevent flip event from causing issues
                        globalIsFlipping = true;
                        pageFlip.flip(currentPageIndex);
                        // Reset flag after animation completes
                        setTimeout(() => {
                            globalIsFlipping = false;
                        }, 1100);
                    } else {
                        console.log('Flipbook: Already on page', currentPageIndex, ', skipping restore');
                    }
                }, 100); // Small delay to ensure pages are loaded
            }
            
            // DEBUG: Check book element immediately after PageFlip
            const bookElementAfter = document.getElementById('book');
            console.log('Flipbook: Book element AFTER PageFlip:', bookElementAfter);
            console.log('Flipbook: Book innerHTML AFTER PageFlip:', bookElementAfter?.innerHTML);
            console.log('Flipbook: Book children AFTER PageFlip:', bookElementAfter?.children?.length);
            
            // DEBUG: Check for PageFlip-specific elements
            const pageFlipElements = document.querySelectorAll('.stf__block, .stf__page, .stf__page__content, .stf__wrapper');
            console.log('Flipbook: PageFlip elements found immediately after loadFromHTML:', pageFlipElements.length);
            pageFlipElements.forEach((el, index) => {
                console.log(`Flipbook: PageFlip element ${index}:`, {
                    tagName: el.tagName,
                    className: el.className,
                    id: el.id,
                    innerHTML: el.innerHTML.substring(0, 100) + '...'
                });
            });
            
        } catch (error) {
            console.error('Flipbook: Error in loadFromHTML:', error);
            console.error('Flipbook: Error stack:', error.stack);
        }
        
        console.log('Flipbook: Pages loaded into PageFlip');
        
        // DEBUG: Check book element after loading pages
        const bookElementAfter = document.getElementById('book');
        console.log('Flipbook: Book element after loading pages:', bookElementAfter);
        console.log('Flipbook: Book element innerHTML after loading:', bookElementAfter?.innerHTML);
        console.log('Flipbook: Book element dimensions after loading:', {
            offsetWidth: bookElementAfter?.offsetWidth,
            offsetHeight: bookElementAfter?.offsetHeight,
            clientWidth: bookElementAfter?.clientWidth,
            clientHeight: bookElementAfter?.clientHeight
        });
        
        // DEBUG: Check if PageFlip actually created any elements
        const allPageFlipElements = document.querySelectorAll('[class*="stf"]');
        console.log('Flipbook: All PageFlip elements found:', allPageFlipElements.length);
        allPageFlipElements.forEach((el, index) => {
            console.log(`Flipbook: PageFlip element ${index}:`, {
                tagName: el.tagName,
                className: el.className,
                id: el.id,
                innerHTML: el.innerHTML.substring(0, 50) + '...'
            });
        });
        
                // Update dimensions after loading pages - but only once
        setTimeout(() => {
            updatePageFlipDimensions();
            
            // DEBUG: Check CSS and visibility
            console.log('Flipbook: Checking CSS and visibility...');
            const bookElement = document.getElementById('book');
            const computedStyle = window.getComputedStyle(bookElement);
            console.log('Flipbook: Book element computed style:', {
                display: computedStyle.display,
                visibility: computedStyle.visibility,
                opacity: computedStyle.opacity,
                width: computedStyle.width,
                height: computedStyle.height,
                position: computedStyle.position,
                zIndex: computedStyle.zIndex
            });
            
            // DEBUG: Check if PageFlip elements are visible
            const pageFlipElements = bookElement.querySelectorAll('.stf__block, .stf__page, .stf__page__content');
            console.log('Flipbook: PageFlip elements found:', pageFlipElements.length);
            
            if (pageFlipElements.length === 0) {
                console.error('Flipbook: NO PageFlip elements found! This is the problem!');
                console.log('Flipbook: Book element innerHTML:', bookElement.innerHTML);
                console.log('Flipbook: Book element children:', bookElement.children.length);
                console.log('Flipbook: Book element children:', Array.from(bookElement.children).map(child => ({
                    tagName: child.tagName,
                    className: child.className,
                    id: child.id
                })));
            } else {
                pageFlipElements.forEach((el, index) => {
                    const style = window.getComputedStyle(el);
                    console.log(`Flipbook: PageFlip element ${index} style:`, {
                        display: style.display,
                        visibility: style.visibility,
                        opacity: style.opacity,
                        width: style.width,
                        height: style.height
                    });
                });
            }
            
                    // DEBUG: Check navigation arrows
        const navArrows = document.getElementById('navigation-arrows');
        const prevButton = document.getElementById('prev-button');
        const nextButton = document.getElementById('next-button');
        console.log('Flipbook: Navigation elements found:', {
            navArrows: !!navArrows,
            prevButton: !!prevButton,
            nextButton: !!nextButton
        });
        
        // DEBUG: Check positioning
        if (navArrows) {
            const navStyle = window.getComputedStyle(navArrows);
            console.log('Flipbook: Navigation arrows positioning:', {
                top: navStyle.top,
                left: navStyle.left,
                transform: navStyle.transform,
                position: navStyle.position
            });
        }
        
        if (bookElement) {
            const bookStyle = window.getComputedStyle(bookElement);
            console.log('Flipbook: Book positioning:', {
                marginTop: bookStyle.marginTop,
                display: bookStyle.display,
                alignItems: bookStyle.alignItems,
                justifyContent: bookStyle.justifyContent
            });
        }
            
            // DEBUG: Check PageFlip state for navigation
            if (pageFlip) {
                const currentPage = pageFlip.getCurrentPageIndex ? pageFlip.getCurrentPageIndex() : 0;
                const totalPages = pageFlip.getPageCount ? pageFlip.getPageCount() : 0;
                console.log('Flipbook: PageFlip state for navigation:', {
                    currentPage: currentPage,
                    totalPages: totalPages
                });
            }
        }, 200);
        
        // Safely check PageFlip state after loading
        try {
            console.log('Flipbook: PageFlip state after loading:', pageFlip.getState ? pageFlip.getState() : 'getState not available');
            console.log('Flipbook: PageFlip current page:', pageFlip.getCurrentPageIndex ? pageFlip.getCurrentPageIndex() : 'getCurrentPageIndex not available');
            console.log('Flipbook: PageFlip total pages:', pageFlip.getPageCount ? pageFlip.getPageCount() : 'getPageCount not available');
        } catch (e) {
            console.log('Flipbook: Could not get PageFlip state after loading:', e.message);
        }
        
        // Notify Swift that pages are loaded (use processedPages.length for expanded count)
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'pagesLoaded',
                count: processedPages.length  // Use expanded page count, not original
            });
        }
        
        // Fix cover page position after pages are loaded
        setTimeout(() => {
            fixCoverPagePosition();
        }, 200);
        
        // DEBUG: Log page navigation details
        console.log('Flipbook: Total pages in array:', pages.length);
        console.log('Flipbook: PageFlip page count:', pageFlip.getPageCount ? pageFlip.getPageCount() : 'N/A');
        console.log('Flipbook: Page indices available:', Array.from({length: pageFlip.getPageCount ? pageFlip.getPageCount() : 0}, (_, i) => i));
    } catch (error) {
        console.error('Flipbook: Error rendering pages:', error);
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'error',
                message: error.message
            });
        }
    }
};

// Expose updatePageFlipDimensions to Swift
window.updatePageFlipDimensions = function() {
    // Only call if not already updating and pageFlip exists
    if (!isUpdatingDimensions && pageFlip) {
        updatePageFlipDimensions();
    }
};

// Expose the updating flag to Swift
Object.defineProperty(window, 'isUpdatingDimensions', {
    get: function() {
        return isUpdatingDimensions;
    }
});

// Global function to update navigation button states
// This can be called from anywhere (main flip handler, navigation arrows, etc.)
function updateNavigationState() {
    if (!pageFlip) return;
    
    const prevButton = document.getElementById('prev-button');
    const nextButton = document.getElementById('next-button');
    
    if (!prevButton || !nextButton) {
        // Buttons not found yet, skip update
        return;
    }
    
    const currentPage = pageFlip.getCurrentPageIndex ? pageFlip.getCurrentPageIndex() : 0;
    const totalPages = pageFlip.getPageCount ? pageFlip.getPageCount() : 0;
    
    console.log('Flipbook: Current page:', currentPage, 'Total pages:', totalPages);
    
    prevButton.disabled = currentPage <= 0;
    nextButton.disabled = currentPage >= totalPages - 1;
    
    // Update button visibility
    prevButton.style.display = totalPages <= 1 ? 'none' : 'flex';
    nextButton.style.display = totalPages <= 1 ? 'none' : 'flex';
}

// Navigation arrows functionality
function setupNavigationArrows() {
    console.log('Flipbook: Setting up navigation arrows...');
    
    const prevButton = document.getElementById('prev-button');
    const nextButton = document.getElementById('next-button');
    
    if (!prevButton || !nextButton) {
        console.error('Flipbook: Navigation buttons not found!');
        return;
    }
    
    // Add click handlers with boundary checks
    // CRITICAL: Check globalIsFlipping flag BEFORE allowing any flip
    prevButton.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        
        // CRITICAL: Check global flag to prevent rapid clicks
        if (globalIsFlipping) {
            console.log('Flipbook: Already flipping, ignoring prev click');
            return;
        }
        
        console.log('Flipbook: Previous button clicked');
        if (pageFlip && pageFlip.flipPrev && pageFlip.getCurrentPageIndex) {
            const currentPage = pageFlip.getCurrentPageIndex();
            // Only flip if not on first page
            if (currentPage > 0) {
                // CRITICAL: Set flag BEFORE calling flipPrev to prevent rapid clicks
                globalIsFlipping = true;
                pageFlip.flipPrev();
                // Flag will be reset by the main flip event handler
            } else {
                console.log('Flipbook: Already on first page, ignoring prev');
            }
        }
    });
    
    nextButton.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        
        // CRITICAL: Check global flag to prevent rapid clicks
        if (globalIsFlipping) {
            console.log('Flipbook: Already flipping, ignoring next click');
            return;
        }
        
        console.log('Flipbook: Next button clicked');
        if (pageFlip && pageFlip.flipNext && pageFlip.getCurrentPageIndex && pageFlip.getPageCount) {
            const currentPage = pageFlip.getCurrentPageIndex();
            const totalPages = pageFlip.getPageCount();
            // Only flip if not on last page
            if (currentPage < totalPages - 1) {
                // CRITICAL: Set flag BEFORE calling flipNext to prevent rapid clicks
                globalIsFlipping = true;
                pageFlip.flipNext();
                // Flag will be reset by the main flip event handler
            } else {
                console.log('Flipbook: Already on last page, ignoring next');
            }
        }
    });
    
    // NOTE: We removed the duplicate flip handler here - the main handler above handles everything
    
    // Prevent boundary swipe attempts from triggering unwanted behavior
    // Listen for state changes that might indicate a failed flip attempt
    pageFlip.on('changeState', function(e) {
        const currentPage = pageFlip.getCurrentPageIndex ? pageFlip.getCurrentPageIndex() : 0;
        const totalPages = pageFlip.getPageCount ? pageFlip.getPageCount() : 0;
        console.log('Flipbook: State changed:', e.data, 'Current page:', currentPage, '/', totalPages);
    });
    
    // Initial state update
    setTimeout(updateNavigationState, 500);
    
    console.log('Flipbook: Navigation arrows setup complete');
}

// Track flipping state globally
let globalIsFlipping = false;

window.next = function() {
    // CRITICAL: Check flag BEFORE allowing flip
    if (globalIsFlipping) {
        console.log('Flipbook: Already flipping, ignoring next');
        return;
    }
    
    if (pageFlip && pageFlip.flipNext && pageFlip.getCurrentPageIndex && pageFlip.getPageCount) {
        const currentPage = pageFlip.getCurrentPageIndex();
        const totalPages = pageFlip.getPageCount();
        // Only flip if not on last page
        if (currentPage < totalPages - 1) {
            // CRITICAL: Set flag BEFORE calling flipNext
            globalIsFlipping = true;
            pageFlip.flipNext();
            // Flag will be reset by the main flip event handler - no need for setTimeout here
        } else {
            console.log('Flipbook: Already on last page, ignoring next');
        }
    }
};

window.prev = function() {
    // CRITICAL: Check flag BEFORE allowing flip
    if (globalIsFlipping) {
        console.log('Flipbook: Already flipping, ignoring prev');
        return;
    }
    
    if (pageFlip && pageFlip.flipPrev && pageFlip.getCurrentPageIndex) {
        const currentPage = pageFlip.getCurrentPageIndex();
        // Only flip if not on first page
        if (currentPage > 0) {
            // CRITICAL: Set flag BEFORE calling flipPrev
            globalIsFlipping = true;
            pageFlip.flipPrev();
            // Flag will be reset by the main flip event handler - no need for setTimeout here
        } else {
            console.log('Flipbook: Already on first page, ignoring prev');
        }
    }
};

window.goToPage = function(pageIndex) {
    if (pageFlip) {
        pageFlip.flip(pageIndex);
    }
};

// Text content splitting function for pagination
function splitTextIntoPages(text, wordsPerPage = 150) {
    const words = text.split(/\s+/);
    const pages = [];
    
    for (let i = 0; i < words.length; i += wordsPerPage) {
        const pageWords = words.slice(i, Math.min(i + wordsPerPage, words.length));
        pages.push(pageWords.join(' '));
    }
    
    return pages;
}

// Helper function to create HTML for each page
function createPageHTML(page, pageNumber = null, isContinuation = false) {
    const { type, title, caption, imageBase64, imageName, text } = page;
    
    switch (type) {
        case 'cover':
            const subtitle = caption ? `<div class="cover-subtitle">${caption}</div>` : '';
            return `
                <div class="flipbook-page cover-page" data-page-position="left" data-page-type="cover">
                    <div class="page-content">
                        <div class="cover-title">${title || 'Memories'}</div>
                        ${subtitle}
                        <div class="cover-accent"></div>
                    </div>
                </div>
            `;
            
        case 'leftBars':
        case 'text':
            const pageNumberHtml = pageNumber ? `<div class="page-number left">${pageNumber}</div>` : '';
            const textContent = text || caption || '';
            
            // Format text with proper paragraphs - clean typography
            const paragraphs = textContent.split('\n\n').filter(p => p.trim());
            const formattedText = paragraphs.map((para, index) => 
                `<p>${para.trim()}</p>`
            ).join('');
            
            // Add story-start class only if it's not a continuation and has a title (new story)
            const storyStartClass = !isContinuation && title ? 'story-start' : '';
            
            // Show title on all pages, with different styling for continued pages
            let titleHtml = '';
            if (title) {
                if (isContinuation) {
                    titleHtml = `<div class="page-title continued-title">${title}<span class="continuation-marker">(continued)</span></div>`;
                } else {
                    titleHtml = `<div class="page-title">${title}</div>`;
                }
            }
            
            return `
                <div class="flipbook-page text-page ${storyStartClass}">
                    <div class="page-content">
                        ${titleHtml}
                        <div class="text-content">
                            ${formattedText}
                        </div>
                        ${pageNumberHtml}
                    </div>
                </div>
            `;
            
        case 'rightPhoto':
            const rightPageNumber = pageNumber ? `<div class="page-number right">${pageNumber}</div>` : '';
            return `
                <div class="flipbook-page">
                    <div class="page-content">
                        ${title ? `<div class="page-title">${title}</div>` : ''}
                        <div class="figure-block">
                            <div class="photo-container">
                                ${createImageElement(imageBase64, imageName)}
                            </div>
                            ${caption ? `<div class="figure-caption">${caption}</div>` : ''}
                        </div>
                        ${rightPageNumber}
                    </div>
                </div>
            `;
            
        case 'mixed':
            const mixedPageNumber = pageNumber ? `<div class="page-number left">${pageNumber}</div>` : '';
            const mixedText = text || caption || '';
            const mixedParagraphs = mixedText.split('\n\n').filter(p => p.trim());
            const mixedFormattedText = mixedParagraphs.map(para => 
                `<p>${para.trim()}</p>`
            ).join('');
            
            return `
                <div class="flipbook-page text-page">
                    <div class="page-content">
                        ${title ? `<div class="page-title">${title}</div>` : ''}
                        <div class="text-content">
                            ${mixedFormattedText}
                        </div>
                        ${imageName || imageBase64 ? `
                            <div class="figure-block">
                                <div class="photo-container">
                                    ${createImageElement(imageBase64, imageName)}
                                </div>
                            </div>
                        ` : ''}
                        ${mixedPageNumber}
                    </div>
                </div>
            `;
            
        case 'photoLayout':
            // Render photo layout page with photo frames
            const photoLayouts = page.photoLayouts || [];
            const photoFramesHtml = photoLayouts.map((layout, index) => {
                const hasPhoto = layout.imageData || layout.imageBase64;
                const frameStyle = `
                    left: ${layout.frame[0][0]}px;
                    top: ${layout.frame[0][1]}px;
                    width: ${layout.frame[1][0]}px;
                    height: ${layout.frame[1][1]}px;
                    transform: rotate(${layout.rotation || 0}deg);
                `;
                
                const imageHtml = hasPhoto 
                    ? `<img src="${layout.imageData || layout.imageBase64}" alt="Photo" class="photo-frame-image" />`
                    : `<div class="photo-frame-placeholder">
                         <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                           <rect x="3" y="3" width="18" height="18" rx="2" ry="2"/>
                           <circle cx="8.5" cy="8.5" r="1.5"/>
                           <polyline points="21 15 16 10 5 21"/>
                         </svg>
                         <span>Tap to add photo</span>
                       </div>`;
                
                return `
                    <div class="photo-frame photo-frame-${layout.type.toLowerCase()}" 
                         style="${frameStyle}; pointer-events: none;"
                         data-frame-id="${layout.id}"
                         data-frame-index="${index}"
                         data-has-photo="${hasPhoto ? 'true' : 'false'}"
                         data-original-x="${layout.frame[0][0]}"
                         data-original-y="${layout.frame[0][1]}">
                        ${imageHtml}
                    </div>
                `;
            }).join('');
            
            const layoutPageNumberHtml = pageNumber ? `<div class="page-number right">${pageNumber}</div>` : '';
            return `
                <div class="flipbook-page photo-layout-page">
                    <div class="page-content">
                        <div class="photo-frames-container">
                            ${photoFramesHtml}
                        </div>
                        ${caption ? `<div class="photo-caption">${caption}</div>` : ''}
                        ${layoutPageNumberHtml}
                    </div>
                </div>
            `;
            
        default:
            return `
                <div class="flipbook-page">
                    <div class="page-content">
                        <div class="page-title">${title || 'Page'}</div>
                        <div class="page-caption">${caption || ''}</div>
                    </div>
                </div>
            `;
    }
}

// Section break for chapter divisions
function createSectionBreak() {
    return '<hr class="section-break" />';
}

// Create image element from base64 or name
function createImageElement(imageBase64, imageName) {
    if (imageBase64) {
        return `<img src="data:image/jpeg;base64,${imageBase64}" alt="Page image">`;
    } else if (imageName) {
        // For named images, we'll show a placeholder with the image name
        // The actual image loading needs to be handled by the native iOS side
        return `<div class="photo-placeholder" data-image="${imageName}">
            <div style="text-align: center; padding: 20px; background: rgba(0,0,0,0.05); border-radius: 4px;">
                <div style="font-size: 8px; color: #666; margin-bottom: 5px;">Image: ${imageName}</div>
                <div style="font-size: 24px;">🖼️</div>
            </div>
        </div>`;
    } else {
        return `<div class="photo-placeholder">📷</div>`;
    }
}

// Track if we're currently flipping to prevent unwanted zoom triggers
let isFlipping = false;
let flipTimeout = null;

// Set up click handlers for page zoom
function setupPageClickHandlers() {
    console.log('Flipbook: Setting up page click handlers for native zoom...');
    
    // Track flipping state to prevent zoom during page transitions
    if (pageFlip) {
        pageFlip.on('changeState', function(e) {
            if (e.data === 'flipping' || e.data === 'user_fold') {
                isFlipping = true;
                // Clear any existing timeout
                if (flipTimeout) clearTimeout(flipTimeout);
                // Set a timeout to reset flipping state
                flipTimeout = setTimeout(() => {
                    isFlipping = false;
                }, 500);
            } else if (e.data === 'read') {
                isFlipping = false;
                if (flipTimeout) clearTimeout(flipTimeout);
            }
        });
    }
    
    // Add handlers to book container for better coverage
    const bookContainer = document.getElementById('book-container');
    const bookElement = document.getElementById('book');
    
    if (!bookContainer) {
        console.error('Flipbook: book-container not found!');
        return;
    }
    
    console.log('Flipbook: Adding click handler to book-container');
    
    // Use both click and touchend for better mobile support
    const handleTap = function(e) {
        console.log('Flipbook: Tap detected on:', e.target.tagName, e.target.className);
        
        // Don't zoom if we're currently flipping pages
        if (isFlipping) {
            console.log('Flipbook: Tap ignored - page flip in progress');
            return;
        }
        
        // Check if this is a navigation arrow
        if (e.target.closest('.nav-arrow') || e.target.closest('#prev-button') || e.target.closest('#next-button')) {
            console.log('Flipbook: Tap on navigation button, ignoring');
            return;
        }
        
            // Check if clicked on a page
            const pageElement = e.target.closest('.flipbook-page');
            console.log('Flipbook: Page element found:', !!pageElement);
            
            if (pageElement) {
                console.log('Flipbook: Page clicked, triggering zoom');
                
                // Prevent default and stop propagation
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                
                // CRITICAL: Get the page index from the data attribute of the CLICKED page
                const htmlPageIndex = parseInt(pageElement.getAttribute('data-page-index') || '0', 10);
                
                console.log('📖 JavaScript: Clicked page element has data-page-index:', htmlPageIndex);
                console.log('📖 JavaScript: Page element classes:', pageElement.className);
                
                // Send the HTML page index directly - Swift will use this for its expanded pages
                handlePageTap(htmlPageIndex);
                
                return false;
            } else {
                console.log('Flipbook: No page element found in click path');
            }
    };
    
    // Add handlers for both mouse and touch events
    bookContainer.addEventListener('click', handleTap, true);
    bookContainer.addEventListener('touchend', handleTap, true);
    
    console.log('Flipbook: Page click handlers setup complete');
}

// Handle window resize - but don't call updatePageFlipDimensions to avoid recursion
window.addEventListener('resize', function() {
    // Just log the resize event, don't trigger dimension updates
    console.log('Flipbook: Window resize detected');
});

// Remove old zoom modal code since we're using native iOS presentation 