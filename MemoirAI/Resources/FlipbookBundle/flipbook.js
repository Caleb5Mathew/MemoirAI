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
                // Try minimal configuration first
                pageFlip = new St.PageFlip(bookElement, {
                    width: dimensions.width,
                    height: dimensions.height,
                    size: "stretch",
                    minWidth: dimensions.width * 0.8,  // Ensure book fills most of container
                    maxWidth: dimensions.width,
                    minHeight: dimensions.height * 0.8, // Ensure book fills most of container
                    maxHeight: dimensions.height,
                    autoSize: false, // Disable autoSize to maintain our sizing
                    showCover: false, // Disable single-page cover behavior
                    flippingTime: 1000,
                    usePortrait: false,
                    hard: "cover",
                    pageMode: "double"
                });
                console.log('Flipbook: PageFlip initialized successfully with minimal config:', pageFlip);
                
                // DEBUG: Test if PageFlip can render a simple div
                console.log('Flipbook: Testing PageFlip with simple div...');
                const testDiv = document.createElement('div');
                testDiv.innerHTML = '<div style="width: 100px; height: 100px; background: blue; color: white;">TEST PAGE</div>';
                testDiv.style.width = '100px';
                testDiv.style.height = '100px';
                
                try {
                    pageFlip.loadFromHTML([testDiv]);
                    console.log('Flipbook: Simple div test successful');
                } catch (testError) {
                    console.error('Flipbook: Simple div test failed:', testError);
                }
                
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
            
            // Set up navigation arrows
            setupNavigationArrows();
            
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
        
        try {
            console.log('Flipbook: Calling pageFlip.loadFromHTML...');
            pageFlip.loadFromHTML(domPages);
            console.log('Flipbook: loadFromHTML completed successfully');
            
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

// Navigation arrows functionality
function setupNavigationArrows() {
    console.log('Flipbook: Setting up navigation arrows...');
    
    const prevButton = document.getElementById('prev-button');
    const nextButton = document.getElementById('next-button');
    
    if (!prevButton || !nextButton) {
        console.error('Flipbook: Navigation buttons not found!');
        return;
    }
    
    // Update button states based on current page
    function updateNavigationState() {
        if (!pageFlip) return;
        
        const currentPage = pageFlip.getCurrentPageIndex ? pageFlip.getCurrentPageIndex() : 0;
        const totalPages = pageFlip.getPageCount ? pageFlip.getPageCount() : 0;
        
        console.log('Flipbook: Current page:', currentPage, 'Total pages:', totalPages);
        
        prevButton.disabled = currentPage <= 0;
        nextButton.disabled = currentPage >= totalPages - 1;
        
        // Update button visibility
        prevButton.style.display = totalPages <= 1 ? 'none' : 'flex';
        nextButton.style.display = totalPages <= 1 ? 'none' : 'flex';
    }
    
    // Add click handlers
    prevButton.addEventListener('click', function() {
        console.log('Flipbook: Previous button clicked');
        if (pageFlip && pageFlip.flipPrev) {
            pageFlip.flipPrev();
        }
    });
    
    nextButton.addEventListener('click', function() {
        console.log('Flipbook: Next button clicked');
        if (pageFlip && pageFlip.flipNext) {
            pageFlip.flipNext();
        }
    });
    
    // Listen for page changes to update button states
    pageFlip.on('flip', function(e) {
        console.log('Flipbook: Page flipped, updating navigation state');
        setTimeout(updateNavigationState, 100); // Small delay to ensure state is updated
    });
    
    // Initial state update
    setTimeout(updateNavigationState, 500);
    
    console.log('Flipbook: Navigation arrows setup complete');
}

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