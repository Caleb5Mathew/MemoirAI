import SwiftUI
import UIKit

// MARK: - Page Curl Book Controller
struct PageCurlBookController: UIViewControllerRepresentable {
    let pages: [MockBookPage]
    @Binding var currentPage: Int

    // Respect Reduce Motion at creation time
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: reduceMotion ? .scroll : .pageCurl,
            navigationOrientation: .horizontal,
            options: nil
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear
        pvc.isDoubleSided = false

        context.coordinator.pages = pages
        context.coordinator.currentPage = currentPage
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.pageViewController = pvc

        if let first = context.coordinator.viewController(for: currentPage) {
            pvc.setViewControllers([first], direction: .forward, animated: false)
        }

        // Log for acceptance checks
        #if DEBUG
        print("PageCurlBookController: transitionStyle = \(reduceMotion ? "scroll (Reduce Motion → crossfade)" : "pageCurl")")
        #endif

        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.pages = pages

        // If binding changed externally, update UI
        if let currentVC = pvc.viewControllers?.first,
           let shownIndex = context.coordinator.index(for: currentVC),
           shownIndex != currentPage,
           let newVC = context.coordinator.viewController(for: currentPage) {

            let direction: UIPageViewController.NavigationDirection = currentPage > shownIndex ? .forward : .reverse
            context.coordinator.setViewControllersWithAppropriateAnimation([newVC], direction: direction)
            context.coordinator.currentPage = currentPage
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlBookController
        var pages: [MockBookPage]
        var currentPage: Int
        var reduceMotion: Bool = false
        weak var pageViewController: UIPageViewController?

        init(_ parent: PageCurlBookController) {
            self.parent = parent
            self.pages = parent.pages
            self.currentPage = parent.currentPage
        }

        // MARK: Data Source
        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let bookVC = viewController as? BookPageViewController,
                  let idx = bookVC.pageIndex,
                  idx > 0 else { return nil }
            return self.viewController(for: idx - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let bookVC = viewController as? BookPageViewController,
                  let idx = bookVC.pageIndex,
                  idx < pages.count - 1 else { return nil }
            return self.viewController(for: idx + 1)
        }

        // MARK: Delegate
        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed,
                  let currentVC = pageViewController.viewControllers?.first as? BookPageViewController,
                  let idx = currentVC.pageIndex else { return }
            parent.currentPage = idx
            currentPage = idx

            // Light haptic on page settle
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        // MARK: View Controller Factory
        func viewController(for index: Int) -> UIViewController? {
            guard index >= 0 && index < pages.count else { return nil }
            let page = pages[index]
            let isLeft = (index % 2 == 0)

            // Render .twoPageSpread as left/right slices; otherwise normal page type
            let view: AnyView
            if page.type == .twoPageSpread {
                view = AnyView(TwoPageSpreadSlice(page: page, isLeftPage: isLeft))
            } else {
                view = AnyView(MockBookPageView(page: page, isLeftPage: isLeft))
            }

            return BookPageViewController(rootView: view, pageIndex: index)
        }

        func index(for viewController: UIViewController) -> Int? {
            (viewController as? BookPageViewController)?.pageIndex
        }

        // MARK: Animation helper (crossfade on Reduce Motion, curl otherwise)
        func setViewControllersWithAppropriateAnimation(_ vcs: [UIViewController],
                                                        direction: UIPageViewController.NavigationDirection) {
            guard let pvc = pageViewController else { return }
            if reduceMotion {
                // Crossfade transition to respect Reduce Motion
                UIView.transition(with: pvc.view, duration: 0.20, options: .transitionCrossDissolve, animations: {
                    pvc.setViewControllers(vcs, direction: direction, animated: false)
                })
            } else {
                pvc.setViewControllers(vcs, direction: direction, animated: true)
            }
        }
    }
}

// MARK: - Book Page Host
class BookPageViewController: UIHostingController<AnyView> {
    let pageIndex: Int?

    init(rootView: AnyView, pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
        view.backgroundColor = .clear
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
