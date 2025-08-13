// Memoir Flipbook JavaScript Wrapper
// Provides API for Swift WKWebView integration

let pageFlip;
let isReady = false;

// Initialize the flipbook when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    initializeFlipbook();
});

function initializeFlipbook() {
    const bookElement = document.getElementById('book');
    
    if (!bookElement) {
        console.error('Book element not found');
        return;
    }

    // Initialize StPageFlip
    pageFlip = new St.PageFlip(bookElement, {
        width: 550,
        height: 733,
        size: "stretch",
        minWidth: 315,
        maxWidth: 1000,
        minHeight: 400,
        maxHeight: 1533,
        maxShadowOpacity: 0.5,
        showCover: true,
        mobileScrollSupport: false
    });

    // Listen for flip events and notify Swift
    pageFlip.on('flip', function(e) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'flip',
                index: e.data
            });
        }
    });

    // Listen for state changes
    pageFlip.on('changeState', function(e) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'stateChange',
                state: e.data
            });
        }
    });

    // Notify Swift that we're ready
    setTimeout(() => {
        isReady = true;
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'ready'
            });
        }
    }, 100);
}

// API functions exposed to Swift
window.renderPages = function(pagesJSON) {
    if (!pageFlip) {
        console.error('PageFlip not initialized');
        return;
    }

    try {
        const pages = JSON.parse(pagesJSON);
        const htmlPages = pages.map(page => createPageHTML(page));
        
        pageFlip.loadFromHTML(htmlPages);
        
        // Notify Swift that pages are loaded
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'pagesLoaded',
                count: pages.length
            });
        }
    } catch (error) {
        console.error('Error rendering pages:', error);
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
            window.webkit.messageHandlers.native.postMessage({
                type: 'error',
                message: error.message
            });
        }
    }
};

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

// Handle window resize
window.addEventListener('resize', function() {
    if (pageFlip) {
        pageFlip.updateFromHtml();
    }
}); 