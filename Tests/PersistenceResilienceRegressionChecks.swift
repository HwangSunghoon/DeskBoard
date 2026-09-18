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
        try checkArchiveRetention(root: root, data: JSONEncoder().encode(savedCopy))
        try checkPreRestoreEdits(root: root, data: JSONEncoder().encode(savedCopy))
        print("PASS: failed primary save preserves edits, durable recovery copy, broken-store fallback, pending copy never silently overwrites primary, explicit restore archives original, export, five-minute warning threshold")
    }

    @MainActor static func checkPreRestoreEdits(root: URL, data: Data) throws {
        for failPrimary in [false, true] {
            let directory = root.appendingPathComponent("restore-edits-\(failPrimary)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("pending.json"))
            let config = ModelConfiguration(url: root.appendingPathComponent("restore-edits-\(failPrimary).store"))
            let factory = { try ModelContainer(for: TodoItem.self, ImportantItem.self, MemoDocument.self, configurations: config) }
            let seed = try factory()
            seed.mainContext.insert(MemoDocument(text: "Original saved memo"))
            try seed.mainContext.save()
            var failNextSave = failPrimary
            let controller = PersistenceController(directory: directory, makeDiskContainer: factory, saveDiskContext: {
                if failNextSave { failNextSave = false; throw CocoaError(.fileWriteOutOfSpace) }
                try $0.save()
            })
            let latest = "Latest edit immediately before restore"
            try controller.container!.mainContext.fetch(FetchDescriptor<MemoDocument>())[0].text = latest
            controller.retry()
            check(!controller.isTemporary && !controller.hasPendingRecovery)
            let disk = try factory()
            check(try disk.mainContext.fetch(FetchDescriptor<MemoDocument>())[0].text == "Keep this memo")
            let archives = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("before-restore-") }
            check(archives.contains { file in
                guard let snapshot = try? JSONDecoder().decode(RecoverySnapshot.self, from: Data(contentsOf: file)) else { return false }
                return snapshot.memos.contains { $0.text == latest }
            }, "Latest pre-restore edits must survive even when checkpoint only saves pending.json")
        }

        let blocked = root.appendingPathComponent("restore-archive-blocked")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try data.write(to: blocked.appendingPathComponent("pending.json"))
        let primary = try memory()
        let memo = MemoDocument(text: "Keep the current editor")
        primary.mainContext.insert(memo)
        try primary.mainContext.save()
        let controller = PersistenceController(directory: blocked, makeDiskContainer: { primary })
        // Simulate storage becoming unavailable after the pending copy was loaded.
        try FileManager.default.moveItem(at: blocked, to: root.appendingPathComponent("restore-archive-original"))
        try Data("blocked".utf8).write(to: blocked)
        controller.retry()
        check(controller.container === primary && controller.hasPendingRecovery && !controller.isTemporary)
        check(try primary.mainContext.fetch(FetchDescriptor<MemoDocument>())[0].text == memo.text)
        print("PASS: latest pre-restore edits archived across primary save failure; failed archive leaves current editor untouched")
    }

    @MainActor static func checkArchiveRetention(root: URL, data: Data) throws {
        let fm = FileManager.default
        let now = Date()
        let old = now.addingTimeInterval(-31 * 86_400)
        let directory = root.appendingPathComponent("retention")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        func seed(_ name: String, date: Date = old, bytes: Data? = nil) throws -> URL {
            let url = directory.appendingPathComponent(name)
            try (bytes ?? data).write(to: url)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            return url
        }
        let retired = try seed("before-restore-\(UUID().uuidString).json")
        let earlier = try seed("earlier-recovery-\(UUID().uuidString).json")
        let recent = try seed("before-restore-\(UUID().uuidString).json", date: now)
        let unknown = try seed("before-restore-manual-export.json")
        let unreadable = try seed("before-restore-\(UUID().uuidString).json", bytes: Data("broken".utf8))
        let symlink = directory.appendingPathComponent("before-restore-\(UUID().uuidString).json")
        try fm.createSymbolicLink(at: symlink, withDestinationURL: unknown)
        let disk = try memory()
        var failSave = true
        let controller = PersistenceController(directory: directory, makeDiskContainer: { disk }, saveDiskContext: {
            if failSave { throw CocoaError(.fileWriteOutOfSpace) }
            try $0.save()
        })
        disk.mainContext.insert(MemoDocument(text: "Protected"))
        check(controller.checkpoint(now: now))
        check(fm.fileExists(atPath: retired.path), "Failed primary save must not prune archives")
        // A restart with an unresolved pending snapshot must not prune either.
        let pending = PersistenceController(directory: directory, makeDiskContainer: { try memory() })
        check(pending.hasPendingRecovery && pending.checkpoint(now: now))
        check(fm.fileExists(atPath: retired.path))
        check(fm.fileExists(atPath: directory.appendingPathComponent("pending.json").path))
        failSave = false
        check(controller.checkpoint(now: now))
        check(!fm.fileExists(atPath: retired.path) && !fm.fileExists(atPath: earlier.path))
        for file in [recent, unknown, unreadable, symlink] {
            check(fm.fileExists(atPath: file.path), "Only valid retired app snapshots may expire")
        }
        check(fm.fileExists(atPath: directory.appendingPathComponent("last-saved.json").path))
        // Failed backup update must also leave archives intact.
        let blockedBackup = root.appendingPathComponent("retention-backup-failure")
        try fm.createDirectory(at: blockedBackup.appendingPathComponent("last-saved.json"), withIntermediateDirectories: true)
        let protected = blockedBackup.appendingPathComponent("before-restore-\(UUID().uuidString).json")
        try data.write(to: protected)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: protected.path)
        let backupFailure = PersistenceController(directory: blockedBackup, makeDiskContainer: { try memory() })
        check(backupFailure.checkpoint(now: now))
        check(fm.fileExists(atPath: protected.path))
        for failedPrimary in [false, true] {
            let corruptDirectory = root.appendingPathComponent("unreadable-pending-\(failedPrimary)")
            try fm.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
            let raw = Data("Unreadable but irreplaceable recovery data".utf8)
            try raw.write(to: corruptDirectory.appendingPathComponent("pending.json"))
            let corruptPending = PersistenceController(directory: corruptDirectory, makeDiskContainer: { try memory() }, saveDiskContext: {
                if failedPrimary { throw CocoaError(.fileWriteOutOfSpace) }
                try $0.save()
            })
            check(corruptPending.checkpoint(now: now))
            let preserved = try fm.contentsOfDirectory(at: corruptDirectory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("unreadable-recovery-") }
            check(preserved.count == 1)
            check(try Data(contentsOf: preserved[0]) == raw)
        }
        print("PASS: retention protects pending/latest/recent/unreadable/unknown/symlink files and skips failed saves/backups")
    }
}
