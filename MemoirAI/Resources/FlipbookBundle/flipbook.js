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
    if (typeof St === 'undefined' || !St.PageFlip) {
        console.error('Flipbook: St.PageFlip not available!');
        // Notify Swift of the error
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'ready',
                error: 'St.PageFlip not available'
            });
        }
        return;
    }

    try {
        // Get actual container dimensions
        const dimensions = getContainerDimensions();
        
        console.log('Flipbook: Using container dimensions:', dimensions);
        
        // Small delay to ensure container is properly sized
        setTimeout(() => {
            // Initialize StPageFlip
            pageFlip = new St.PageFlip(bookElement, {
                width: dimensions.width,
                height: dimensions.height,
                size: "stretch",
                minWidth: 280,
                maxWidth: 800,
                minHeight: 374,
                maxHeight: 800,
                maxShadowOpacity: 0.5,
                showCover: false, // Disable single-page cover behavior
                mobileScrollSupport: false,
                autoSize: false, // Disable autoSize to prevent layout issues
                flippingTime: 1000,
                usePortrait: false,
                hard: "cover",
                pageMode: "double"
            });
            
            console.log('Flipbook: StPageFlip initialized successfully');
            console.log('Flipbook: StPageFlip instance:', pageFlip);
            
            console.log('Flipbook: StPageFlip initialized with config:', {
                width: dimensions.width,
                height: dimensions.height,
                size: "stretch",
                minWidth: 280,
                maxWidth: 800,
                minHeight: 374,
                maxHeight: 800,
                showCover: false,
                autoSize: true
            });
            
            // Listen for flip events and notify Swift
            pageFlip.on('flip', function(e) {
                console.log('PageFlip: Page flipped to index:', e.data);
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
                    window.webkit.messageHandlers.native.postMessage({
                        type: 'flip',
                        index: e.data
                    });
                }
            });

            // Listen for state changes
            pageFlip.on('changeState', function(e) {
                console.log('PageFlip: State changed to:', e.data);
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
        
        // Convert HTML strings to DOM elements
        const domPages = pages.map(page => {
            const htmlString = createPageHTML(page);
            console.log('Flipbook: Generated HTML for page:', page.type, htmlString);
            
            // Create a temporary container to parse HTML
            const tempDiv = document.createElement('div');
            tempDiv.innerHTML = htmlString.trim();
            
            // Get the first child element (the actual page div)
            const pageElement = tempDiv.firstElementChild;
            if (!pageElement) {
                console.error('Flipbook: Failed to create DOM element for page:', page.type);
                return null;
            }
            
            console.log('Flipbook: Created DOM element:', pageElement);
            console.log('Flipbook: Page element dimensions:', {
                offsetWidth: pageElement.offsetWidth,
                offsetHeight: pageElement.offsetHeight,
                clientWidth: pageElement.clientWidth,
                clientHeight: pageElement.clientHeight
            });
            
            return pageElement;
        }).filter(element => element !== null); // Filter out any nulls
        
        console.log('Flipbook: DOM pages ready:', domPages.length);
        
        // Safely check PageFlip state
        try {
            console.log('Flipbook: PageFlip current state before loading:', pageFlip.getState ? pageFlip.getState() : 'getState not available');
        } catch (e) {
            console.log('Flipbook: Could not get PageFlip state:', e.message);
        }
        
        // Load the DOM elements into PageFlip
        pageFlip.loadFromHTML(domPages);
        
        console.log('Flipbook: Pages loaded into PageFlip');
        
        // Update dimensions after loading pages - but only once
        setTimeout(() => {
            updatePageFlipDimensions();
        }, 200);
        
        // Safely check PageFlip state after loading
        try {
            console.log('Flipbook: PageFlip state after loading:', pageFlip.getState ? pageFlip.getState() : 'getState not available');
            console.log('Flipbook: PageFlip current page:', pageFlip.getCurrentPageIndex ? pageFlip.getCurrentPageIndex() : 'getCurrentPageIndex not available');
            console.log('Flipbook: PageFlip total pages:', pageFlip.getPageCount ? pageFlip.getPageCount() : 'getPageCount not available');
        } catch (e) {
            console.log('Flipbook: Could not get PageFlip state after loading:', e.message);
        }
        
        // Notify Swift that pages are loaded
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'pagesLoaded',
                count: pages.length
            });
        }
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

window.next = function() {
    if (pageFlip) {
        pageFlip.flipNext();
    }
};

window.prev = function() {
    if (pageFlip) {
        pageFlip.flipPrev();
    }
};

window.goToPage = function(pageIndex) {
    if (pageFlip) {
        pageFlip.flip(pageIndex);
    }
};

// Helper function to create HTML for each page
function createPageHTML(page) {
    const { type, title, caption, imageBase64, imageName } = page;
    
    switch (type) {
        case 'cover':
            return `
                <div class="flipbook-page cover-page">
                    <div class="page-content">
                        <div class="cover-title">${title || 'Memories of Achievement'}</div>
                        <div class="cover-accent"></div>
                    </div>
                </div>
            `;
            
        case 'leftBars':
            return `
                <div class="flipbook-page left-page">
                    <div class="page-content">
                        <div class="paragraph-bars">
                            ${generateParagraphBars()}
                        </div>
                    </div>
                </div>
            `;
            
        case 'rightPhoto':
            return `
                <div class="flipbook-page right-page">
                    <div class="page-content">
                        <div class="page-title">${title || 'Memories of Achievement'}</div>
                        <div class="photo-container">
                            ${createImageElement(imageBase64, imageName)}
                        </div>
                        <div class="page-caption">${caption || 'A short two-line caption underneath the photograph.'}</div>
                    </div>
                </div>
            `;
            
        case 'mixed':
            return `
                <div class="flipbook-page">
                    <div class="page-content">
                        <div class="mixed-content">
                            <div class="mixed-bars">
                                ${generateParagraphBars(5)}
                            </div>
                            <div class="photo-container small-photo">
                                ${createImageElement(imageBase64, imageName)}
                            </div>
                        </div>
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

// Generate paragraph bars with varied lengths
function generateParagraphBars(count = 12) {
    const patterns = [0.92, 0.78, 0.86, 0.70, 0.95, 0.82, 0.65, 0.90, 0.74, 0.88, 0.68, 0.96];
    let html = '';
    
    for (let i = 0; i < count; i++) {
        const width = patterns[i % patterns.length] * 100;
        html += `<div class="paragraph-bar" style="width: ${width}%;"></div>`;
    }
    
    return html;
}

// Create image element from base64 or name
function createImageElement(imageBase64, imageName) {
    if (imageBase64) {
        return `<img src="data:image/jpeg;base64,${imageBase64}" alt="Page image">`;
    } else if (imageName) {
        // For demo purposes, we'll use a placeholder
        // In a real implementation, you'd need to handle image loading
        return `<div class="photo-placeholder">📷</div>`;
    } else {
        return `<div class="photo-placeholder">📷</div>`;
    }
}

// Handle window resize - but don't call updatePageFlipDimensions to avoid recursion
window.addEventListener('resize', function() {
    // Just log the resize event, don't trigger dimension updates
    console.log('Flipbook: Window resize detected');
}); 