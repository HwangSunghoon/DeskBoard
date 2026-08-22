import Foundation
import SwiftData

@Model
final class TodoItem {
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: Date

    init(title: String, sortOrder: Int) {
        self.title = title
        self.isCompleted = false
        self.sortOrder = sortOrder
        self.createdAt = .now
    }
}

@Model
final class ImportantItem {
    var title: String
    var date: Date?
    var sortOrder: Int

    init(title: String, date: Date?, sortOrder: Int) {
        self.title = title
        self.date = date
        self.sortOrder = sortOrder
    }
}

@Model
final class MemoDocument {
    var text: String
    var updatedAt: Date

    init(text: String = "") {
        self.text = text
        self.updatedAt = .now
    }
}

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()
    let container: ModelContainer

    private init() {
        do {
            container = try ModelContainer(for: TodoItem.self, ImportantItem.self, MemoDocument.self)
        } catch {
            fatalError("Unable to create DeskBoard data store: \(error.localizedDescription)")
        }
    }
}
