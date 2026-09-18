import Foundation
import AppKit

enum SidebarWindowGeometry {
    static func frame(visibleFrame: CGRect, screenWidth: CGFloat, isLeft: Bool) -> CGRect {
        let horizontalInset = min(CGFloat(12), max(0, (visibleFrame.width - 1) / 2))
        let verticalInset = min(CGFloat(12), max(0, (visibleFrame.height - 1) / 2))
        let width = min(max(320, screenWidth * 0.25), max(1, visibleFrame.width - horizontalInset * 2))
        return CGRect(
            x: isLeft ? visibleFrame.minX + horizontalInset : visibleFrame.maxX - width - horizontalInset,
            y: visibleFrame.minY + verticalInset,
            width: width,
            height: max(1, visibleFrame.height - verticalInset * 2)
        )
    }
}

enum TodoRowMetrics {
    static let controlWidth: CGFloat = 14
    static let spacing: CGFloat = 8
    static let minimumSpacer: CGFloat = 4

    static func textWidth(rowWidth: CGFloat) -> CGFloat {
        max(1, rowWidth - 2 * controlWidth - 3 * spacing - minimumSpacer)
    }
}

/// Shared by the calendar view and the sidebar allocator so wrapping, gaps,
/// and padding cannot silently make a row taller than its reserved space.
enum CalendarSectionMetrics {
    static let maximumVisibleRows = 4
    static let timeFontSize: CGFloat = 11
    static let headerHeight: CGFloat = 20
    static let rowHeight: CGFloat = 20
    static let rowSpacing: CGFloat = 7
    static let bottomInset: CGFloat = 4

    static func verticalPadding(compact: Bool) -> CGFloat { compact ? 4 : 12 }
    static func headerSpacing(compact: Bool) -> CGFloat { compact ? 4 : 9 }

    static func timeColumnWidth(for labels: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: timeFontSize)
        return labels.reduce(CGFloat(48)) { width, label in
            max(width, ceil((label as NSString).size(withAttributes: [.font: font]).width) + 2)
        }
    }

    static func height(rowCount: Int, compact: Bool) -> CGFloat {
        let rows = max(1, rowCount)
        return 2 * verticalPadding(compact: compact) + headerHeight + headerSpacing(compact: compact)
            + CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing + bottomInset
    }

    static func fittingHeight(available: CGFloat, rowCount: Int, compact: Bool) -> CGFloat {
        let capped = min(available, height(rowCount: maximumVisibleRows, compact: compact))
        guard rowCount > 0, height(rowCount: rowCount, compact: compact) > capped else { return capped }
        let firstRow = height(rowCount: 1, compact: compact)
        let rows = max(1, 1 + Int(floor((capped - firstRow) / (rowHeight + rowSpacing))))
        // At rest, show whole rows at the viewport edge. Reallocate surplus below.
        return min(capped, height(rowCount: rows, compact: compact))
    }
}

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
            calendar: value(.today, max(100, CalendarSectionMetrics.height(rowCount: min(calendarCount, CalendarSectionMetrics.maximumVisibleRows), compact: false))),
            system: value(.system, 82),
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
        shrink(&result.calendar, to: value(.today, CalendarSectionMetrics.height(rowCount: 1, compact: false)))
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
            shrink(&result.calendar, to: value(.today, CalendarSectionMetrics.height(rowCount: 1, compact: true)))
            shrink(&result.todo, to: value(.todo, 54))
            shrink(&result.important, to: value(.important, addingImportant ? 80 : 54))
            // Reserve one full row per editor even with all sections on a short display.
            shrink(&result.focus, to: value(.focusTimer, 24))
            shrink(&result.quickOpen, to: 34)
            shrink(&result.memo, to: value(.memo, 48))
            shrink(&result.calendar, to: value(.today, CalendarSectionMetrics.height(rowCount: 1, compact: true)))
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
        grow(&result.calendar, to: CalendarSectionMetrics.height(rowCount: min(calendarCount, CalendarSectionMetrics.maximumVisibleRows), compact: result.compact))
        if visible.contains(.today) {
            let fitted = CalendarSectionMetrics.fittingHeight(available: result.calendar, rowCount: calendarCount, compact: result.compact)
            extra += result.calendar - fitted
            result.calendar = fitted
        }
        grow(&result.important, to: importantTarget)
        grow(&result.todo, to: todoTarget)
        grow(&result.memo, to: memoHeight)
        if visible.contains(.memo) { result.memo += extra }
        else if visible.contains(.todo) { result.todo += extra }
        // With neither editor visible, spare space remains below the content.
        return result
    }
}
