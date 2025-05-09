//
//  Profile.swift
//  MemoirAI
//
//  Created by user941803 on 4/23/25.
//

import Foundation
import SwiftUI

struct Profile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var photoData: Data? // stored as JPEG data

    var image: Image {
        if let data = photoData, let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        } else {
            return Image("grandparent-illustration") // fallback
        }
    }
}
