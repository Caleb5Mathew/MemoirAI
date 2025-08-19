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
    
    // New profile fields
    var birthdate: Date?
    var ethnicity: String?
    var gender: String?
    var createdAt: Date
    var updatedAt: Date
    
    // Maintain backward compatibility with existing profiles
    init(id: UUID = UUID(), 
         name: String, 
         photoData: Data? = nil,
         birthdate: Date? = nil,
         ethnicity: String? = nil,
         gender: String? = nil,
         createdAt: Date? = nil,
         updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.photoData = photoData
        self.birthdate = birthdate
        self.ethnicity = ethnicity
        self.gender = gender
        self.createdAt = createdAt ?? Date()
        self.updatedAt = updatedAt ?? Date()
    }
    
    // Custom decoding for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        photoData = try container.decodeIfPresent(Data.self, forKey: .photoData)
        
        // New fields with defaults for backward compatibility
        birthdate = try container.decodeIfPresent(Date.self, forKey: .birthdate)
        ethnicity = try container.decodeIfPresent(String.self, forKey: .ethnicity)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    var image: Image {
        if let data = photoData, let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        } else {
            return Image("grandparent-illustration") // fallback
        }
    }
    
    var uiImage: UIImage? {
        if let data = photoData {
            return UIImage(data: data)
        }
        return nil
    }
    
    // Computed property for age calculation
    var age: Int? {
        guard let birthdate = birthdate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: birthdate, to: Date())
        return components.year
    }
    
    // Check if profile has all basic info
    var isComplete: Bool {
        return !name.isEmpty && photoData != nil && birthdate != nil
    }
}
