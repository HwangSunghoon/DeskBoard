import Foundation

struct SidebarSectionHeights {
    var date: CGFloat
    var quickOpen: CGFloat
    var calendar: CGFloat
    var system: CGFloat
    var todo: CGFloat
    var important: CGFloat
    var memo: CGFloat
    var focus: CGFloat
    var worldClock: CGFloat
    var compact: Bool
    var footer: CGFloat = 24
    var dividers: CGFloat

    var total: CGFloat {
        date + quickOpen + calendar + system + todo + important + memo + focus + worldClock + footer + dividers
    }

    static func calculate(
        height: CGFloat, visible: Set<DashboardSection>,
        calendarCount: Int, todoHeight: CGFloat, importantCount: Int,
        addingTodo: Bool, addingImportant: Bool, memoHeight: CGFloat, worldClockCount: Int = 2,
        quickOpenCount: Int = 0
    ) -> Self {
        let dividerCount = CGFloat(visible.count) // One divider before each visible section.
        func value(_ section: DashboardSection, _ height: CGFloat) -> CGFloat {
            visible.contains(section) ? height : 0
        }
        var result = Self(
            date: 104, quickOpen: quickOpenCount > 0 ? 42 : 0,
            calendar: value(.today, 100), system: value(.system, 82),
            todo: value(.todo, 100), important: value(.important, addingImportant ? 105 : 78),
            memo: value(.memo, 180), focus: value(.focusTimer, 48),
            worldClock: value(.worldClock, worldClockCount > 0 ? 76 : 56),
            compact: false, dividers: dividerCount
        )
        var deficit = max(0, result.total - height)
        func shrink(_ value: inout CGFloat, to floor: CGFloat) {
            let reduction = min(deficit, max(0, value - floor))
            value -= reduction
            deficit -= reduction
        }
        shrink(&result.memo, to: value(.memo, 90))
        shrink(&result.calendar, to: value(.today, 76))
        shrink(&result.todo, to: value(.todo, 78))
        shrink(&result.important, to: value(.important, addingImportant ? 103 : 76))
        if deficit > 0 {
            // Tight screens use smaller section padding, never smaller text or clipped headers.
            result.compact = true
            shrink(&result.focus, to: value(.focusTimer, 28))
            // City and time always stay together in two-line, equal-width columns.
            shrink(&result.worldClock, to: value(.worldClock, worldClockCount > 0 ? 60 : 40))
            // The analog face is 84pt plus 20pt padding; keep its natural height.
            shrink(&result.quickOpen, to: 36)
            shrink(&result.system, to: value(.system, 62))
            shrink(&result.memo, to: value(.memo, 64))
            shrink(&result.calendar, to: value(.today, 54))
            shrink(&result.todo, to: value(.todo, 54))
            shrink(&result.important, to: value(.important, addingImportant ? 80 : 54))
            // Reserve one full row per editor even with all sections on a short display.
            shrink(&result.focus, to: value(.focusTimer, 24))
            shrink(&result.quickOpen, to: 34)
            shrink(&result.memo, to: value(.memo, 48))
            shrink(&result.calendar, to: value(.today, 50))
            shrink(&result.todo, to: value(.todo, 50))
            shrink(&result.important, to: value(.important, addingImportant ? 76 : 50))
            shrink(&result.footer, to: 20)
        }

        var extra = max(0, height - result.total)
        func grow(_ value: inout CGFloat, to target: CGFloat) {
            guard value > 0 else { return }
            let addition = min(extra, max(0, target - value))
            value += addition
            extra -= addition
        }
        let chrome: CGFloat = result.compact ? 34 : 54
        let todoTarget = max(result.todo, todoHeight - (result.compact ? 20 : 0) + (addingTodo ? 27 : 0))
        let importantTarget = min(addingImportant ? 207 : 180, chrome + CGFloat(importantCount) * 24 + (addingImportant ? 27 : 0))
        // An open editor receives space before passive content growth.
        if addingTodo { grow(&result.todo, to: todoTarget) }
        if addingImportant { grow(&result.important, to: importantTarget) }
        grow(&result.calendar, to: min(210, chrome + CGFloat(calendarCount) * 24))
        grow(&result.important, to: importantTarget)
        grow(&result.todo, to: todoTarget)
        grow(&result.memo, to: memoHeight)
        if visible.contains(.memo) { result.memo += extra }
        else if visible.contains(.todo) { result.todo += extra }
        // With neither editor visible, spare space remains below the content.
        return result
    }
}
