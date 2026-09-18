import AppKit
import Foundation

@main
struct CalendarLayoutRegressionChecks {
    @MainActor static func main() {
        let font = NSFont.systemFont(ofSize: CalendarSectionMetrics.timeFontSize)
        let labels = ["10:00 AM", "11:59 PM", "10:00\u{202F}AM", "오전 10:00", "下午12:00", "23:59", "All day"]
        let width = CalendarSectionMetrics.timeColumnWidth(for: labels)
        for label in labels {
            let measured = (label as NSString).size(withAttributes: [.font: font]).width
            precondition(width >= ceil(measured) + 2, "Every time label must fit without wrapping or shrinking")
        }
        precondition(CalendarSectionMetrics.timeColumnWidth(for: ["10:00 AM"]) > 48)
        precondition(CalendarSectionMetrics.timeColumnWidth(for: []) == 48)

        for compact in [false, true] {
            for count in 1...20 {
                let height = CalendarSectionMetrics.height(rowCount: count, compact: compact)
                let viewport = height - 2 * CalendarSectionMetrics.verticalPadding(compact: compact)
                    - CalendarSectionMetrics.headerHeight - CalendarSectionMetrics.headerSpacing(compact: compact)
                let rows = CGFloat(count) * CalendarSectionMetrics.rowHeight
                    + CGFloat(count - 1) * CalendarSectionMetrics.rowSpacing + CalendarSectionMetrics.bottomInset
                precondition(viewport == rows, "Last row and bottom padding must fit exactly")
            }
        }

        let all = Set(DashboardSection.allCases)
        for height: CGFloat in [620, 726, 727, 728, 755, 800, 930, 1080, 1440] {
            for count in [0, 1, 2, 3, 4, 5, 20] {
                let layout = SidebarSectionHeights.calculate(height: height, visible: all,
                    calendarCount: count, todoHeight: 131, importantCount: 0,
                    addingTodo: false, addingImportant: false, memoHeight: 180,
                    worldClockCount: 4, quickOpenCount: 6)
                precondition(abs(layout.total - height) < 0.01)
                precondition(layout.calendar <= CalendarSectionMetrics.height(rowCount: 4, compact: layout.compact))
                if count >= 4, height >= 930 {
                    precondition(layout.calendar == CalendarSectionMetrics.height(rowCount: 4, compact: layout.compact),
                                 "Four events must fit; fifth and later events must scroll")
                }
                precondition(layout.calendar >= CalendarSectionMetrics.height(rowCount: 1, compact: layout.compact))
                if count <= 2, height >= 800 {
                    precondition(layout.calendar >= CalendarSectionMetrics.height(rowCount: count, compact: layout.compact),
                                 "Two events must be fully visible when the screen has room")
                }
                if CalendarSectionMetrics.height(rowCount: count, compact: layout.compact) > layout.calendar {
                    let first = CalendarSectionMetrics.height(rowCount: 1, compact: layout.compact)
                    let rowSteps = (layout.calendar - first) / (CalendarSectionMetrics.rowHeight + CalendarSectionMetrics.rowSpacing)
                    precondition(abs(rowSteps - rowSteps.rounded()) < 0.01, "Overflow viewport must end on a full row")
                }
            }
        }
        print("PASS: time widths, localized labels, exact row/padding height, two-event visibility, four-row cap and internal scrolling")
    }
}
