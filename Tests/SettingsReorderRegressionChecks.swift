import Foundation

// Compile with DashboardPreferences.swift, WorldClockStore.swift and QuickOpenStore.swift.
@main
struct SettingsReorderRegressionChecks {
    @MainActor static func main() throws {
        let suite = "DeskBoard.SettingsReorderChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DashboardPreferences(defaults: defaults)
        let original = preferences.sectionOrder
        preferences.moveSections(fromOffsets: IndexSet(integer: 0), toOffset: original.count)
        precondition(preferences.sectionOrder == Array(original.dropFirst()) + [original[0]])
        preferences.moveSections(fromOffsets: IndexSet(integer: original.count - 1), toOffset: 0)
        precondition(preferences.sectionOrder == original)
        preferences.moveSections(fromOffsets: IndexSet([0, 2]), toOffset: original.count)
        let moved = original.enumerated().filter { ![0, 2].contains($0.offset) }.map(\.element) + [original[0], original[2]]
        precondition(preferences.sectionOrder == moved)
        precondition(DashboardPreferences(defaults: defaults).sectionOrder == moved)
        precondition(preferences.visibleSections == [.memo])
        preferences.moveSections(fromOffsets: IndexSet(integer: 99), toOffset: 0)
        preferences.moveSections(fromOffsets: IndexSet(integer: 0), toOffset: -1)
        preferences.moveSections(fromOffsets: [], toOffset: 0)
        precondition(preferences.sectionOrder == moved)

        let cityIDs = ["Asia/Seoul", "Europe/London", "Africa/Accra", "America/New_York"]
        defaults.set(cityIDs, forKey: "worldClock.cities.v1")
        let world = WorldClockStore(defaults: defaults)
        world.moveCities(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        precondition(world.cities.map(\.id) == [cityIDs[1], cityIDs[2], cityIDs[3], cityIDs[0]])
        world.moveCities(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        precondition(world.cities.map(\.id) == cityIDs)
        world.moveCities(fromOffsets: IndexSet([1, 3]), toOffset: 0)
        precondition(world.cities.map(\.id) == [cityIDs[1], cityIDs[3], cityIDs[0], cityIDs[2]])
        precondition(WorldClockStore(defaults: defaults).cities == world.cities)

        // Test-only bookmarks and paths; no real application access or user settings involved.
        let applications = (0..<6).map { index in
            QuickOpenApplication(id: UUID(), name: "App \(index)", bundleIdentifier: "test.app\(index)",
                                 path: "/tmp/TestApp\(index).app", bookmarkData: Data([UInt8(index)]))
        }
        defaults.set(try JSONEncoder().encode(applications), forKey: "quickOpenApplications.v1")
        let quickOpen = QuickOpenStore(defaults: defaults)
        quickOpen.moveApplications(fromOffsets: IndexSet(integer: 0), toOffset: 6)
        precondition(quickOpen.applications == Array(applications.dropFirst()) + [applications[0]])
        quickOpen.moveApplications(fromOffsets: IndexSet(integer: 5), toOffset: 0)
        precondition(quickOpen.applications == applications)
        quickOpen.moveApplications(fromOffsets: IndexSet([0, 2]), toOffset: 6)
        let expected = [applications[1], applications[3], applications[4], applications[5], applications[0], applications[2]]
        precondition(quickOpen.applications == expected)
        precondition(QuickOpenStore(defaults: defaults).applications == expected)
        quickOpen.moveApplications(fromOffsets: IndexSet(integer: 0), toOffset: 0)
        quickOpen.moveApplications(fromOffsets: IndexSet(integer: 7), toOffset: 0)
        quickOpen.moveApplications(fromOffsets: IndexSet(integer: 0), toOffset: 7)
        precondition(quickOpen.applications == expected)
        print("PASS: three native move handlers; up/down/multi-row/no-op/boundaries; saved order, visibility, IDs and bookmarks preserved")
    }
}
