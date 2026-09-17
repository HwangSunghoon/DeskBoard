import Combine
import Foundation
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable, Codable {
    case today, worldClock, system, todo, focusTimer, important, memo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .worldClock: "World Clock"
        case .focusTimer: "Focus Timer"
        default: rawValue.capitalized
        }
    }
}

@MainActor
final class DashboardPreferences: ObservableObject {
    static let shared = DashboardPreferences()
    @Published private(set) var visibleSections: Set<DashboardSection>
    @Published private(set) var sectionOrder: [DashboardSection]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.stringArray(forKey: "visibleSections.v1") {
            visibleSections = Set(stored.compactMap(DashboardSection.init(rawValue:))).union([.memo])
        } else {
            visibleSections = [.memo]
        }
        var order: [DashboardSection] = []
        for key in defaults.stringArray(forKey: "sectionOrder.v1") ?? [] {
            if let section = DashboardSection(rawValue: key), !order.contains(section) {
                order.append(section)
            }
        }
        // Keep saved positions while appending sections added in later versions.
        sectionOrder = order + DashboardSection.allCases.filter { !order.contains($0) }
    }

    var orderedVisibleSections: [DashboardSection] {
        sectionOrder.filter(visibleSections.contains)
    }

    func moveSection(_ section: DashboardSection, by offset: Int) {
        guard offset == -1 || offset == 1,
              let index = sectionOrder.firstIndex(of: section),
              sectionOrder.indices.contains(index + offset) else { return }
        sectionOrder.swapAt(index, index + offset)
        defaults.set(sectionOrder.map(\.rawValue), forKey: "sectionOrder.v1")
    }

    func moveSections(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, source.allSatisfy(sectionOrder.indices.contains),
              (0...sectionOrder.count).contains(destination) else { return }
        sectionOrder.move(fromOffsets: source, toOffset: destination)
        defaults.set(sectionOrder.map(\.rawValue), forKey: "sectionOrder.v1")
    }

    func setVisible(_ section: DashboardSection, _ visible: Bool) {
        guard section != .memo else { return }
        if visible { visibleSections.insert(section) }
        else { visibleSections.remove(section) }
        defaults.set(DashboardSection.allCases.filter(visibleSections.contains).map(\.rawValue), forKey: "visibleSections.v1")
    }

}
