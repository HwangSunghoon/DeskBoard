import Foundation
import SwiftData
import Combine
import OSLog

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
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()
    @Published private(set) var container: ModelContainer?
    @Published private(set) var isTemporary = false
    @Published private(set) var needsSaveAttention = false
    @Published private(set) var recoveryMessage: String?
    private let makeDiskContainer: () throws -> ModelContainer
    private let saveDiskContext: (ModelContext) throws -> Void
    private let directory: URL
    private var timer: Timer?
    private var firstUnprotectedFailure: Date?
    private var lastRecoveryData: Data?
    private var needsCheckpoint = true
    private var pendingSnapshot: RecoverySnapshot?
    private var archivedPendingSnapshot = false
    private var lastFailureLog: Date?
    private var lastArchiveCleanup: Date?
    private let logger = Logger(subsystem: "com.local.DeskBoard", category: "persistence")
    private var pendingURL: URL { directory.appendingPathComponent("pending.json") }
    private var backupURL: URL { directory.appendingPathComponent("last-saved.json") }

    init(directory: URL? = nil, makeDiskContainer: @escaping () throws -> ModelContainer = {
        try ModelContainer(for: TodoItem.self, ImportantItem.self, MemoDocument.self)
    }, saveDiskContext: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("DeskBoard/Recovery", isDirectory: true)
        self.makeDiskContainer = makeDiskContainer
        self.saveDiskContext = saveDiskContext
        // A pending snapshot contains edits not committed to the database. Never
        // silently replace it with older database contents, or erase the database.
        let pending = readSnapshot(at: pendingURL)
        do {
            let disk = try makeDiskContainer()
            container = disk
            if let pending {
                pendingSnapshot = pending
                recoveryMessage = "An unsaved recovery copy is available. Your saved database is shown. Export the recovery copy before choosing Restore recovery copy."
            }
        } catch {
            logger.error("Persistent store could not open. Error code: \((error as NSError).code)")
            do { try useTemporaryStore(restoring: pending ?? readSnapshot(at: backupURL)) }
            catch {
                // Even if a temporary store cannot be made, time/weather/settings
                // still work in the storage-independent fallback view.
                isTemporary = true
                recoveryMessage = "Your original data is untouched. The data store could not be opened. Try again or export the recovery copy."
            }
        }
        container?.mainContext.autosaveEnabled = false
    }

    private func useTemporaryStore(restoring snapshot: RecoverySnapshot?) throws {
        let memory = try ModelContainer(for: TodoItem.self, ImportantItem.self, MemoDocument.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        memory.mainContext.autosaveEnabled = false
        snapshot?.insert(into: memory.mainContext)
        container = memory
        isTemporary = true
        recoveryMessage = snapshot == nil
            ? "Your original data could not be opened and has not been deleted. New edits use a separate recovery copy."
            : "Showing a recovery copy. Your original database is untouched. Retry saving to restore this copy, or export it first."
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in _ = self?.checkpoint() }
        }
        timer?.tolerance = 0.5
    }

    /// Saving failures never roll back the editor or replace its context.
    /// Return false only when neither the database nor a recovery copy is durable.
    @discardableResult func checkpoint(now: Date = .now) -> Bool {
        guard let context = container?.mainContext else { return true }
        guard context.hasChanges || needsCheckpoint else { return true }
        do {
            let snapshot = try RecoverySnapshot(context: context)
            let data = try JSONEncoder().encode(snapshot)
            lastRecoveryData = data
            if !isTemporary {
                do {
                    try saveDiskContext(context)
                    needsCheckpoint = false
                    firstUnprotectedFailure = nil
                    needsSaveAttention = false
                    // A backup failure is not a user-facing failure if the primary save succeeded.
                    do {
                        try write(data, to: backupURL)
                        if pendingSnapshot == nil, FileManager.default.fileExists(atPath: pendingURL.path) {
                            try preserveUnreadablePendingCopy()
                            try FileManager.default.removeItem(at: pendingURL)
                        }
                        if pendingSnapshot == nil { pruneRecoveryArchives(now: now) }
                    } catch { logger.notice("Recovery backup update failed. Error code: \((error as NSError).code)") }
                    return true
                } catch {
                    logSaveFailure(error, now: now)
                }
            }
            if let pendingSnapshot, !archivedPendingSnapshot {
                try write(try JSONEncoder().encode(pendingSnapshot), to: directory.appendingPathComponent("earlier-recovery-\(UUID().uuidString).json"))
                archivedPendingSnapshot = true
            }
            try preserveUnreadablePendingCopy()
            try write(data, to: pendingURL)
            // Keep retrying the real database, even if its context no longer marks changes.
            needsCheckpoint = !isTemporary
            if isTemporary { try context.save() }
            firstUnprotectedFailure = nil
            needsSaveAttention = false
            return true
        } catch {
            needsCheckpoint = true
            if firstUnprotectedFailure == nil { firstUnprotectedFailure = now }
            needsSaveAttention = needsSaveAttention || now.timeIntervalSince(firstUnprotectedFailure ?? now) >= 300
            logSaveFailure(error, now: now)
            return false
        }
    }

    /// Called explicitly from the recovery UI. Archive the old database's contents
    /// before replacing them with the displayed recovery snapshot.
    func retry() {
        if !isTemporary, let pendingSnapshot {
            do {
                // Save any currently displayed database edits before switching copies.
                guard checkpoint() else { return }
                try useTemporaryStore(restoring: pendingSnapshot)
                self.pendingSnapshot = nil
                NotificationCenter.default.post(name: Self.didRecover, object: self)
            } catch { return }
        }
        guard isTemporary else { _ = checkpoint(); return }
        do {
            let disk = try makeDiskContainer()
            disk.mainContext.autosaveEnabled = false
            let recovered: RecoverySnapshot?
            if let source = container?.mainContext { recovered = try RecoverySnapshot(context: source) }
            else { recovered = readSnapshot(at: pendingURL) }
            if let recovered {
                let original = try RecoverySnapshot(context: disk.mainContext)
                try write(try JSONEncoder().encode(original), to: directory.appendingPathComponent("before-restore-\(UUID().uuidString).json"))
                for item in try disk.mainContext.fetch(FetchDescriptor<TodoItem>()) { disk.mainContext.delete(item) }
                for item in try disk.mainContext.fetch(FetchDescriptor<ImportantItem>()) { disk.mainContext.delete(item) }
                for item in try disk.mainContext.fetch(FetchDescriptor<MemoDocument>()) { disk.mainContext.delete(item) }
                recovered.insert(into: disk.mainContext)
                try saveDiskContext(disk.mainContext)
            }
            container = disk
            isTemporary = false
            pendingSnapshot = nil
            recoveryMessage = nil
            needsCheckpoint = true
            _ = checkpoint()
            NotificationCenter.default.post(name: Self.didRecover, object: self)
        } catch {
            recoveryMessage = "The original store is still unavailable. Keep working in this recovery copy, or export it."
            logger.error("Store recovery failed; keeping temporary context. Error code: \((error as NSError).code)")
        }
    }

    func exportData() throws -> Data {
        if let pendingSnapshot { return try JSONEncoder().encode(pendingSnapshot) }
        if let context = container?.mainContext { return try JSONEncoder().encode(RecoverySnapshot(context: context)) }
        if let lastRecoveryData { return lastRecoveryData }
        if let snapshot = readSnapshot(at: pendingURL) ?? readSnapshot(at: backupURL) { return try JSONEncoder().encode(snapshot) }
        throw CocoaError(.fileReadUnknown)
    }

    var hasPendingRecovery: Bool { pendingSnapshot != nil }

    func requestSaveHelp() { needsSaveAttention = true }

    private func logSaveFailure(_ error: Error, now: Date) {
        guard lastFailureLog.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastFailureLog = now
        logger.notice("Save attempt failed; preserving edits. Error code: \((error as NSError).code)")
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func readSnapshot(at url: URL) -> RecoverySnapshot? {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(RecoverySnapshot.self, from: data), value.version == 1 else { return nil }
        return value
    }

    /// A corrupt or newer-format pending file may still be useful for manual
    /// recovery. Preserve its exact bytes before any replacement or removal.
    private func preserveUnreadablePendingCopy() throws {
        guard FileManager.default.fileExists(atPath: pendingURL.path),
              readSnapshot(at: pendingURL) == nil else { return }
        let data = try Data(contentsOf: pendingURL)
        try write(data, to: directory.appendingPathComponent("unreadable-recovery-\(UUID().uuidString).json"))
    }

    /// Only retired, readable snapshots expire. Never prune during a storage
    /// failure or while a pending recovery copy still needs the user's decision.
    private func pruneRecoveryArchives(now: Date) {
        guard !FileManager.default.fileExists(atPath: pendingURL.path),
              lastArchiveCleanup.map({ now.timeIntervalSince($0) >= 86_400 }) ?? true else { return }
        lastArchiveCleanup = now
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            guard file.pathExtension == "json",
                  let prefix = ["before-restore-", "earlier-recovery-"].first(where: { name.hasPrefix($0) }),
                  UUID(uuidString: String(name.dropFirst(prefix.count))) != nil,
                  let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) > 30 * 86_400,
                  readSnapshot(at: file) != nil else { continue }
            do { try FileManager.default.removeItem(at: file) }
            catch { logger.notice("Recovery archive cleanup deferred. Error code: \((error as NSError).code)") }
        }
    }

    static let didRecover = Notification.Name("DeskBoard.persistenceRecovered")
    deinit { timer?.invalidate() }
}

/// Separate from the SwiftData schema: adding recovery must not migrate user models.
struct RecoverySnapshot: Codable {
    struct Todo: Codable { let title: String; let completed: Bool; let order: Int; let created: Date }
    struct Important: Codable { let title: String; let date: Date?; let order: Int }
    struct Memo: Codable { let text: String; let updated: Date }
    var version = 1
    let todos: [Todo]
    let important: [Important]
    let memos: [Memo]

    @MainActor init(context: ModelContext) throws {
        todos = try context.fetch(FetchDescriptor<TodoItem>()).map { Todo(title: $0.title, completed: $0.isCompleted, order: $0.sortOrder, created: $0.createdAt) }
        important = try context.fetch(FetchDescriptor<ImportantItem>()).map { Important(title: $0.title, date: $0.date, order: $0.sortOrder) }
        memos = try context.fetch(FetchDescriptor<MemoDocument>()).map { Memo(text: $0.text, updated: $0.updatedAt) }
    }

    @MainActor func insert(into context: ModelContext) {
        for value in todos {
            let item = TodoItem(title: value.title, sortOrder: value.order)
            item.isCompleted = value.completed
            item.createdAt = value.created
            context.insert(item)
        }
        for value in important { context.insert(ImportantItem(title: value.title, date: value.date, sortOrder: value.order)) }
        for value in memos {
            let item = MemoDocument(text: value.text)
            item.updatedAt = value.updated
            context.insert(item)
        }
    }
}
