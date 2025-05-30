//
//  View+Snapshot.swift
//  MemoirAI
//
//  Created by user941803 on 5/21/25.
//

// View+Snapshot.swift
import SwiftUI
import UIKit

extension View {
  /// Renders this SwiftUI view into a UIImage.
  func snapshot(width: CGFloat, height: CGFloat) -> UIImage {
    // 1. Host the view
    let controller = UIHostingController(rootView: self)
    guard let view = controller.view else {
        // Return a blank image if view creation fails
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { _ in }
    }

    // 2. Set size
    view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
    view.backgroundColor = .clear

    // 3. Draw into a graphics context
    let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
    return renderer.image { _ in
      view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
    }
  }
}
