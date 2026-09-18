import Foundation
import SwiftData

/// No default SwiftData URL or production recovery path is used by the lab's
/// shared Sidebar store. Even legacy views that reference .shared are isolated.
@MainActor enum LabStorageIsolation {
    static func makeSidebarStore() -> PersistenceController {
        precondition(Bundle.main.bundleIdentifier == "com.local.DeskBoard.ErrorLab")
        precondition(NSHomeDirectory().contains("/Containers/com.local.DeskBoard.ErrorLab/Data"))
        let root = URL.applicationSupportDirectory.appendingPathComponent("DeskBoardErrorLab/Sidebar", isDirectory: true)
        return PersistenceController(directory: root.appendingPathComponent("Recovery"), makeDiskContainer: {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(url: root.appendingPathComponent("sidebar-test.store"))
            return try ModelContainer(for: TodoItem.self, ImportantItem.self, MemoDocument.self, configurations: configuration)
        })
    }
}
