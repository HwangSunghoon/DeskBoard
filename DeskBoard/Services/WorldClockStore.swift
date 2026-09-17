import Combine
import Foundation
import SwiftUI

struct WorldClockCity: Identifiable, Equatable {
    let id: String
    var name: String { id.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? id }
    var region: String { id.split(separator: "/").dropLast().joined(separator: "/").replacingOccurrences(of: "_", with: " ") }
    var timeZone: TimeZone { TimeZone(identifier: id) ?? .gmt }

    func timeText(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    func dayOffset(at date: Date, relativeTo localZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = localZone
        let local = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = timeZone
        let remote = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = .gmt
        guard let localDay = calendar.date(from: local), let remoteDay = calendar.date(from: remote) else { return 0 }
        return calendar.dateComponents([.day], from: localDay, to: remoteDay).day ?? 0
    }
}

@MainActor
final class WorldClockStore: ObservableObject {
    static let shared = WorldClockStore()
    static let maximumCities = 4
    static let availableCities = TimeZone.knownTimeZoneIdentifiers
        .filter { $0.contains("/") && !$0.hasPrefix("Etc/") && !$0.hasPrefix("SystemV/") }
        .map { WorldClockCity(id: $0) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    @Published private(set) var cities: [WorldClockCity]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let ids = defaults.stringArray(forKey: "worldClock.cities.v1") ?? ["Asia/Seoul", "America/New_York"]
        var valid: [WorldClockCity] = []
        for id in ids where TimeZone(identifier: id) != nil && !valid.contains(where: { $0.id == id }) {
            valid.append(WorldClockCity(id: id))
        }
        cities = Array(valid.prefix(Self.maximumCities))
    }

    func add(_ id: String) {
        guard cities.count < Self.maximumCities, TimeZone(identifier: id) != nil, !cities.contains(where: { $0.id == id }) else { return }
        cities.append(WorldClockCity(id: id))
        save()
    }

    func remove(_ id: String) {
        cities.removeAll { $0.id == id }
        save()
    }

    func move(_ id: String, by offset: Int) {
        guard let index = cities.firstIndex(where: { $0.id == id }), cities.indices.contains(index + offset) else { return }
        cities.swapAt(index, index + offset)
        save()
    }

    func moveCities(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, source.allSatisfy(cities.indices.contains),
              (0...cities.count).contains(destination) else { return }
        cities.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() { defaults.set(cities.map(\.id), forKey: "worldClock.cities.v1") }
}
