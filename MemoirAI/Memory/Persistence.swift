//
//  Persistence.swift
//  MemoirAI
//
//  Created by user941803 on 4/6/25.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    static var preview: PersistenceController = {
        let controller = PersistenceController()

        // Create sample data here if needed
        let viewContext = controller.container.viewContext
        let sampleEntry = MemoryEntry(context: viewContext)
        sampleEntry.id = UUID()
        sampleEntry.prompt = "Sample Prompt"
        sampleEntry.text = "This is a sample memory."
        sampleEntry.createdAt = Date()

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }

        return controller
    }()
    let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "MemoirDataModel") // Name matches xcdatamodeld
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Core Data store failed: \(error)")
            }
        }
    }
}
