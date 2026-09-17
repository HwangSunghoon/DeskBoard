import Foundation
import SwiftData

private func check(_ condition: Bool, _ message: String = "Regression check failed") {
    precondition(condition, message)
}

@main struct PersistenceResilienceRegressionChecks {
    @MainActor static func memory() throws -> ModelContainer {
        try ModelContainer(for: TodoItem.self, ImportantItem.self, MemoDocument.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DeskBoardPersistenceChecks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let primary = try memory()
        var failSaving = true
        let recoveryDirectory = root.appendingPathComponent("recovery")
        let controller = PersistenceController(directory: recoveryDirectory, makeDiskContainer: { primary }, saveDiskContext: { context in
            if failSaving { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        })
        let todo = TodoItem(title: "Keep this task", sortOrder: 0)
        primary.mainContext.insert(todo)
        primary.mainContext.insert(ImportantItem(title: "Event", date: .now, sortOrder: 0))
        primary.mainContext.insert(MemoDocument(text: "Keep this memo"))
        check(controller.checkpoint(), "Recovery copy must protect edits even if primary save fails")
        check(!controller.needsSaveAttention)
        check(try primary.mainContext.fetchCount(FetchDescriptor<TodoItem>()) == 1)
        let savedCopy = try JSONDecoder().decode(RecoverySnapshot.self, from: controller.exportData())
        check(savedCopy.todos[0].title == todo.title && savedCopy.memos[0].text == "Keep this memo")
        let branch = root.appendingPathComponent("failed-restore")
        try FileManager.default.createDirectory(at: branch, withIntermediateDirectories: true)
        try JSONEncoder().encode(savedCopy).write(to: branch.appendingPathComponent("pending.json"))
        let original = try memory()
        var blockRestore = false
        let failedRestore = PersistenceController(directory: branch, makeDiskContainer: {
            if blockRestore { throw CocoaError(.fileReadCorruptFile) }
            return original
        })
        blockRestore = true
        failedRestore.retry()
        check(failedRestore.isTemporary)
        let continuedMemo = try failedRestore.container!.mainContext.fetch(FetchDescriptor<MemoDocument>())[0]
        continuedMemo.text = "Edit after a failed restore"
        let exportedAfterFailure = try JSONDecoder().decode(RecoverySnapshot.self, from: failedRestore.exportData())
        check(exportedAfterFailure.memos[0].text == continuedMemo.text, "Export must never return the pre-edit pending snapshot")
        // Simulate a restart with a broken disk store. No original database deletion.
        let fallback = PersistenceController(directory: recoveryDirectory, makeDiskContainer: { throw CocoaError(.fileReadCorruptFile) })
        check(fallback.isTemporary && fallback.container != nil)
        let restored = try fallback.container!.mainContext.fetch(FetchDescriptor<MemoDocument>())
        check(restored[0].text == "Keep this memo")
        check(fallback.checkpoint() && !fallback.needsSaveAttention)
        // A healthy store is never silently overwritten by an older pending copy.
        let healthy = try memory()
        healthy.mainContext.insert(MemoDocument(text: "Existing database"))
        try healthy.mainContext.save()
        let withPending = PersistenceController(directory: recoveryDirectory, makeDiskContainer: { healthy })
        check(!withPending.isTemporary && withPending.hasPendingRecovery)
        check(try healthy.mainContext.fetch(FetchDescriptor<MemoDocument>())[0].text == "Existing database")
        withPending.retry() // explicit restore action
        check(!withPending.isTemporary && !withPending.hasPendingRecovery)
        check(try healthy.mainContext.fetch(FetchDescriptor<MemoDocument>())[0].text == "Keep this memo")
        let files = try FileManager.default.contentsOfDirectory(atPath: recoveryDirectory.path)
        check(files.contains { $0.hasPrefix("before-restore-") })
        failSaving = false
        check(controller.checkpoint())
        check(!controller.needsSaveAttention)

        // A file where a directory is expected reliably simulates backup failure,
        // without filling the disk or altering any user data.
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("test".utf8).write(to: blocked)
        let unavailable = PersistenceController(directory: blocked, makeDiskContainer: { throw CocoaError(.fileReadCorruptFile) })
        unavailable.container!.mainContext.insert(MemoDocument(text: "Still editable"))
        let t = Date()
        check(!unavailable.checkpoint(now: t) && !unavailable.needsSaveAttention)
        check(!unavailable.checkpoint(now: t.addingTimeInterval(299)) && !unavailable.needsSaveAttention)
        check(!unavailable.checkpoint(now: t.addingTimeInterval(301)) && unavailable.needsSaveAttention)
        check(try unavailable.container!.mainContext.fetch(FetchDescriptor<MemoDocument>())[0].text == "Still editable")
        // Exercise the same schema against a real, isolated on-disk SQLite store.
        let config = ModelConfiguration(url: root.appendingPathComponent("test.store"))
        let diskFactory = { try ModelContainer(for: TodoItem.self, ImportantItem.self, MemoDocument.self, configurations: config) }
        let realDisk = PersistenceController(directory: root.appendingPathComponent("real-recovery"), makeDiskContainer: diskFactory)
        realDisk.container!.mainContext.insert(MemoDocument(text: "Survives reopening"))
        check(realDisk.checkpoint())
        let reopenedDisk = try diskFactory()
        check(try reopenedDisk.mainContext.fetch(FetchDescriptor<MemoDocument>())[0].text == "Survives reopening")
        print("PASS: failed primary save preserves edits, durable recovery copy, broken-store fallback, pending copy never silently overwrites primary, explicit restore archives original, export, five-minute warning threshold")
    }
}
