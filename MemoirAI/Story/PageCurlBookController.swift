import SwiftUI
import UIKit

// MARK: - Page Curl Book Controller
struct PageCurlBookController: UIViewControllerRepresentable {
    let pages: [MockBookPage]
    @Binding var currentPage: Int
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: nil
        )
        
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        
        // Set initial page
        if let firstPage = context.coordinator.viewController(for: 0) {
            pageViewController.setViewControllers([firstPage], direction: .forward, animated: false)
        }
        
        return pageViewController
    }
    
    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.pages = pages
        context.coordinator.currentPage = currentPage
        
        // Update current page if needed
        if let currentVC = pageViewController.viewControllers?.first,
           let index = context.coordinator.index(for: currentVC),
           index != currentPage {
            if let newVC = context.coordinator.viewController(for: currentPage) {
                let direction: UIPageViewController.NavigationDirection = currentPage > index ? .forward : .reverse
                pageViewController.setViewControllers([newVC], direction: direction, animated: true)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlBookController
        var pages: [MockBookPage]
        var currentPage: Int
        
        init(_ parent: PageCurlBookController) {
            self.parent = parent
            self.pages = parent.pages
            self.currentPage = parent.currentPage
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let bookPageVC = viewController as? BookPageViewController,
                  let currentIndex = bookPageVC.pageIndex,
                  currentIndex > 0 else {
                return nil
            }
            
            return self.viewController(for: currentIndex - 1)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let bookPageVC = viewController as? BookPageViewController,
                  let currentIndex = bookPageVC.pageIndex,
                  currentIndex < pages.count - 1 else {
                return nil
            }
            
            return self.viewController(for: currentIndex + 1)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed,
               let currentVC = pageViewController.viewControllers?.first as? BookPageViewController,
               let index = currentVC.pageIndex {
                parent.currentPage = index
                self.currentPage = index
            }
        }
        
        func viewController(for index: Int) -> UIViewController? {
            guard index >= 0 && index < pages.count else { return nil }
            
            let page = pages[index]
            
            // For two-page spreads, we need to render the full spread
            let bookPageView: AnyView
            if page.type == .twoPageSpread {
                bookPageView = AnyView(TwoPageSpreadView(page: page))
            } else {
                bookPageView = AnyView(MockBookPageView(page: page, isLeftPage: index % 2 == 0))
            }
            
            let hostingController = BookPageViewController(rootView: bookPageView, pageIndex: index)
            
            return hostingController
        }
        
        func index(for viewController: UIViewController) -> Int? {
            return (viewController as? BookPageViewController)?.pageIndex
        }
    }
}

// MARK: - Book Page View Controller
class BookPageViewController: UIHostingController<AnyView> {
    let pageIndex: Int?
    
    init(rootView: AnyView, pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
} 