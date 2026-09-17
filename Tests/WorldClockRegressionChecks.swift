import Foundation

// Run with swiftc alongside DeskBoard/Services/WorldClockStore.swift.
@main
struct WorldClockRegressionChecks {
    @MainActor static func main() {
        let suite = "DeskBoard.WorldClockChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = ["Africa/Accra", "Asia/Seoul", "Europe/London"]
        defaults.set(initial, forKey: "worldClock.cities.v1")
        let store = WorldClockStore(defaults: defaults)
        precondition(store.cities.map(\.id) == initial)
        store.add("Asia/Tokyo")
        precondition(store.cities.count == 4)
        store.add("America/New_York")
        precondition(store.cities.count == 4)
        store.move("Asia/Tokyo", by: -1)
        precondition(store.cities.map(\.id) == ["Africa/Accra", "Asia/Seoul", "Asia/Tokyo", "Europe/London"])
        precondition(WorldClockStore(defaults: defaults).cities == store.cities)
        store.remove("Africa/Accra")
        store.add("America/New_York")
        precondition(store.cities.count == 4 && store.cities.last?.id == "America/New_York")

        defaults.set(["Asia/Seoul", "Asia/Seoul", "invalid", "Europe/London", "Asia/Tokyo", "Africa/Accra", "America/New_York"], forKey: "worldClock.cities.v1")
        let sanitized = WorldClockStore(defaults: defaults)
        precondition(sanitized.cities.map(\.id) == ["Asia/Seoul", "Europe/London", "Asia/Tokyo", "Africa/Accra"])
        sanitized.remove("Africa/Accra")
        sanitized.add("Asia/Seoul")
        sanitized.add("invalid")
        precondition(sanitized.cities.count == 3)
        sanitized.add("America/New_York")
        precondition(sanitized.cities.count == WorldClockStore.maximumCities)
        print("PASS: existing cities retained, four-city cap, add/remove/reorder/persistence, invalid and duplicate IDs")
    }
}
