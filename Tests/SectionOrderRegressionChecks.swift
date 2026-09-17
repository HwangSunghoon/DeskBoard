import Foundation

// Compile with DashboardPreferences.swift and SidebarLayout.swift.
@main
struct SectionOrderRegressionChecks {
    @MainActor static func main() {
        let suite = "DeskBoard.SectionOrderChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let all = DashboardSection.allCases
        let preferences = DashboardPreferences(defaults: defaults)
        precondition(preferences.sectionOrder == all)
        precondition(preferences.orderedVisibleSections == [.memo])
        preferences.moveSection(.today, by: -1)
        preferences.moveSection(.memo, by: 1)
        preferences.moveSection(.todo, by: Int.max)
        precondition(preferences.sectionOrder == all)

        for _ in 1..<all.count { preferences.moveSection(.memo, by: -1) }
        precondition(preferences.sectionOrder.first == .memo)
        precondition(Set(preferences.sectionOrder) == Set(all))
        preferences.setVisible(.memo, false)
        preferences.setVisible(.today, true)
        preferences.setVisible(.todo, true)
        precondition(preferences.orderedVisibleSections == [.memo, .today, .todo])
        precondition(DashboardPreferences(defaults: defaults).sectionOrder == preferences.sectionOrder)
        precondition(DashboardPreferences(defaults: defaults).orderedVisibleSections == [.memo, .today, .todo])
        let saved = preferences.sectionOrder
        preferences.setVisible(.today, false)
        precondition(preferences.orderedVisibleSections == [.memo, .todo])
        preferences.setVisible(.today, true)
        precondition(preferences.sectionOrder == saved)
        precondition(preferences.orderedVisibleSections == [.memo, .today, .todo])

        // Older installations keep their section selections and get the original order.
        defaults.removeObject(forKey: "sectionOrder.v1")
        defaults.set(["system", "market", "todo"], forKey: "visibleSections.v1")
        let legacy = DashboardPreferences(defaults: defaults)
        precondition(legacy.sectionOrder == all)
        precondition(legacy.orderedVisibleSections == [.system, .market, .todo, .memo])
        // Unknown and duplicate IDs must not produce duplicate views or omit new sections.
        defaults.set(["memo", "memo", "unknown", "todo"], forKey: "sectionOrder.v1")
        let partial = DashboardPreferences(defaults: defaults)
        precondition(partial.sectionOrder == [.memo, .todo] + all.filter { $0 != .memo && $0 != .todo })
        precondition(partial.sectionOrder.count == all.count)

        for section in all { partial.setVisible(section, true) }
        for height: CGFloat in [620, 800, 1080, 1440] {
            for editing in 0..<4 {
                func layout() -> SidebarSectionHeights {
                    SidebarSectionHeights.calculate(
                        height: height, visible: partial.visibleSections, marketCount: 6,
                        calendarCount: 20, todoHeight: 600, importantCount: 20,
                        addingTodo: editing & 1 != 0, addingImportant: editing & 2 != 0,
                        memoHeight: 400, worldClockCount: 4, quickOpenCount: 6
                    )
                }
                let before = layout()
                // Moving the expanding Memo must not change any section's allocation.
                for _ in 1..<all.count { partial.moveSection(.memo, by: 1) }
                precondition(partial.sectionOrder.last == .memo)
                let after = layout()
                precondition(before.total == after.total && after.total <= height + 0.01)
                precondition(before.memo == after.memo && before.todo == after.todo)
                precondition(before.calendar == after.calendar && before.important == after.important)
                precondition(before.system == after.system && before.market == after.market)
                precondition(before.worldClock == after.worldClock && before.focus == after.focus)
                for _ in 1..<all.count { partial.moveSection(.memo, by: -1) }
                precondition(partial.sectionOrder.first == .memo)
            }
        }
        print("PASS: order changes/restoration, Memo always on, hidden-section positions, migration/sanitization, layout invariance")
    }
}
