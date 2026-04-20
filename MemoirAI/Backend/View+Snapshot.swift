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
  /// Renders this SwiftUI view into a UIImage at print resolution (points).
  /// Used for book page snapshots (text + illustration) before Firebase upload.
  func snapshot(width: CGFloat, height: CGFloat) -> UIImage {
    // 1. Host the view
    let controller = UIHostingController(rootView: self)
    guard let view = controller.view else {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { _ in }
    }

    // 2. Set size and force layout
    let size = CGSize(width: max(width, 1), height: max(height, 1))
    view.bounds = CGRect(origin: .zero, size: size)
    view.backgroundColor = .clear
    view.layoutIfNeeded()

    // 3. Draw into graphics context (afterScreenUpdates ensures layout is applied)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
      view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
    }
  }
}
