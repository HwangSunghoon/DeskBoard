import AppKit
import SwiftData
import SwiftUI

private func check(_ condition: Bool) { precondition(condition) }

private struct OfflineWeather: WeatherProviding {
    func fetch(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        throw URLError(.notConnectedToInternet)
    }
}

/// Uses real production views and failure handlers, never the user's database,
/// desktop capture, calendar permission, network, or PersistenceController.shared.
@main struct ErrorUIRenderingChecks {
    @MainActor static func memory() throws -> ModelContainer {
        try ModelContainer(for: TodoItem.self, ImportantItem.self, MemoDocument.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor static func main() async throws {
        precondition(Bundle.main.bundleIdentifier == "com.deskboard.tests.error-ui")
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DeskBoardErrorUI-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "DeskBoardErrorUI.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        var rows: [(String, AnyView)] = []
        var report: [String] = []
        func record(_ text: String) { report.append("PASS: \(text)"); print(report.last!) }

        // Primary saves fail, but recovery copies work: remain silent and editable.
        let primary = try memory()
        let protected = PersistenceController(directory: root.appendingPathComponent("protected"),
            makeDiskContainer: { primary }, saveDiskContext: { _ in throw CocoaError(.fileWriteOutOfSpace) })
        primary.mainContext.insert(MemoDocument(text: "My memo stays on screen"))
        precondition(protected.checkpoint() && !protected.needsSaveAttention)
        check(try JSONDecoder().decode(RecoverySnapshot.self, from: protected.exportData()).memos.first?.text == "My memo stays on screen")
        rows.append(("Primary save failed; recovery saved", AnyView(StorageStatusView(storage: protected))))
        record("Primary failure: recovery JSON saved, memo preserved, no save warning")

        // Only this test-owned path is blocked: no actual disk exhaustion or chmod.
        let blocked = root.appendingPathComponent("blocked-directory")
        try Data("Not a directory".utf8).write(to: blocked)
        let failingDisk = try memory()
        var failPrimary = true
        let failed = PersistenceController(directory: blocked, makeDiskContainer: { failingDisk }, saveDiskContext: {
            if failPrimary { throw CocoaError(.fileWriteOutOfSpace) }
            try $0.save()
        })
        failingDisk.mainContext.insert(MemoDocument(text: "Still editable after failure"))
        let t = Date()
        precondition(!failed.checkpoint(now: t) && !failed.needsSaveAttention)
        precondition(!failed.checkpoint(now: t.addingTimeInterval(299)) && !failed.needsSaveAttention)
        try await snapshot(StorageStatusView(storage: failed).frame(width: 340, height: 30),
                           name: "01-save-failure-before-threshold", output: output, defaults: defaults)
        precondition(!failed.checkpoint(now: t.addingTimeInterval(301)) && failed.needsSaveAttention)
        rows.append(("Both saves unavailable for over 5 minutes", AnyView(StorageStatusView(storage: failed))))
        try await snapshot(StorageStatusView(storage: failed).recoveryDetails,
                           name: "02-save-issue-details", output: output, defaults: defaults)
        record("Both failures: silent at 299 seconds, Save issue at 301 seconds; editor preserved")

        // Startup recovery and explicit restore failure use actual recovery records.
        let recoveryPath = root.appendingPathComponent("protected")
        let recovered = PersistenceController(directory: recoveryPath,
            makeDiskContainer: { throw CocoaError(.fileReadCorruptFile) })
        precondition(recovered.isTemporary && recovered.container != nil)
        check(try recovered.container!.mainContext.fetch(FetchDescriptor<MemoDocument>()).first?.text == "My memo stays on screen")
        rows.append(("Database unavailable; recovery copy loaded", AnyView(StorageStatusView(storage: recovered))))
        try await snapshot(StorageStatusView(storage: recovered).recoveryDetails,
                           name: "03-recovery-details", output: output, defaults: defaults)
        record("Database open failure: editable recovery copy loaded, Recovery copy control shown")

        let original = try memory()
        original.mainContext.insert(MemoDocument(text: "Keep my newer edit"))
        let pending = PersistenceController(directory: recoveryPath, makeDiskContainer: { original })
        precondition(pending.hasPendingRecovery && !pending.isTemporary)
        try await snapshot(StorageStatusView(storage: pending).recoveryDetails,
                           name: "04-pending-copy-details", output: output, defaults: defaults)
        try FileManager.default.moveItem(at: recoveryPath, to: root.appendingPathComponent("saved-fixture"))
        try Data("Blocked restore archive".utf8).write(to: recoveryPath)
        pending.retry()
        precondition(pending.container === original && !pending.isTemporary)
        precondition(pending.recoveryMessage?.contains("Recovery was not restored") == true)
        check(try original.mainContext.fetch(FetchDescriptor<MemoDocument>()).first?.text == "Keep my newer edit")
        try await snapshot(StorageStatusView(storage: pending).recoveryDetails,
                           name: "05-restore-failed-details", output: output, defaults: defaults)
        record("Restore archive failure: restore refused, current memo untouched, explanation shown")

        // No live request: the provider always throws. Production cache decoding is used.
        let locations = WeatherLocationStore(defaults: defaults)
        struct Cache: Encodable { let locationID: String; let snapshot: WeatherSnapshot }
        let dashboard = DashboardModel() // Never start its services or request calendar access.
        for (name, age) in [("06-weather-recent-cache", 60.0), ("07-weather-old-cache", 7201.0)] {
            let value = WeatherSnapshot(temperature: 20, high: 26, low: 17,
                precipitationProbability: 10, weatherCode: 0, updatedAt: Date().addingTimeInterval(-age))
            defaults.set(try JSONEncoder().encode(Cache(locationID: locations.selected.id, snapshot: value)), forKey: "weather.cache.v2")
            let weather = WeatherService(provider: OfflineWeather(), locations: locations, defaults: defaults)
            await weather.refresh()
            precondition(weather.snapshot?.temperature == 20 && !weather.isUnavailable)
            precondition(weather.isDelayed() == (age > 7200))
            try await snapshot(DateWeatherView(model: dashboard, weather: weather).frame(width: 340),
                               name: name, output: output, defaults: defaults)
        }
        defaults.removeObject(forKey: "weather.cache.v2")
        let emptyWeather = WeatherService(provider: OfflineWeather(), locations: locations, defaults: defaults)
        await emptyWeather.refresh()
        precondition(emptyWeather.snapshot == nil && emptyWeather.isUnavailable)
        try await snapshot(DateWeatherView(model: dashboard, weather: emptyWeather).frame(width: 340),
                           name: "08-weather-no-cache", output: output, defaults: defaults)
        record("Offline weather: cached value retained; delayed dot after 2 hours; no cache shows unavailable")

        let statuses = VStack(alignment: .leading, spacing: 16) {
            ForEach(rows.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    Text(rows[index].0).font(.system(size: 12, weight: .semibold))
                    rows[index].1.frame(height: 20)
                }
                Divider()
            }
        }.frame(width: 340)
        try await snapshot(statuses, name: "09-status-controls", output: output, defaults: defaults)
        // A successful retry must also clear the warning without restarting the app.
        failPrimary = false
        precondition(failed.checkpoint() && !failed.needsSaveAttention)
        check(try failingDisk.mainContext.fetch(FetchDescriptor<MemoDocument>()).first?.text == "Still editable after failure")
        try await snapshot(StorageStatusView(storage: failed).frame(width: 340, height: 30),
                           name: "10-save-recovered", output: output, defaults: defaults)
        record("Successful retry: save warning removed, same memo retained")
        report.append("Scope: own off-screen NSHostingView renderings, not desktop screenshots or automated popover clicks. No live permission/relaunch/quit-dialog testing.")
        try report.joined(separator: "\n").write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor static func snapshot<V: View>(_ content: V, name: String, output: URL, defaults: UserDefaults) async throws {
        // AppKit-hosted rendering includes native buttons (unlike ImageRenderer).
        // Only our own view is drawn; no Screen Recording or Accessibility access.
        let view = NSHostingView(rootView: content.padding(20)
            .background(Color(red: 0.76, green: 0.79, blue: 0.84))
            .environment(\.colorScheme, .light).defaultAppStorage(defaults))
        let size = view.fittingSize
        precondition(size.width > 0 && size.height > 0)
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: output.appendingPathComponent("\(name).png"), options: .atomic)
        window.close()
    }
}
