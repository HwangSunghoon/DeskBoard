import AppKit
import SwiftUI
import SwiftData

struct SidebarView: View {
    @EnvironmentObject private var dashboard: DashboardModel
    @AppStorage("appearance") private var appearance = "light"
    @AppStorage("backgroundOpacity") private var backgroundOpacity = 0.82
    @Query(sort: [SortDescriptor(\TodoItem.sortOrder), SortDescriptor(\TodoItem.createdAt)]) private var todoItems: [TodoItem]
    @Query(sort: [SortDescriptor(\ImportantItem.sortOrder)]) private var importantItems: [ImportantItem]
    @State private var memoPreferredHeight: CGFloat = 180

    var body: some View {
        GeometryReader { proxy in
            let layout = adaptiveLayout(for: proxy.size)
            VStack(spacing: 0) {
                DateWeatherView(model: dashboard, weather: dashboard.weather)
                    .frame(height: layout.date)
                QuickOpenView()
                    .frame(height: layout.quickOpen)
                sectionDivider
                CalendarSectionView(service: dashboard.calendar)
                    .frame(height: layout.calendar)
                sectionDivider
                SystemSectionView(monitor: dashboard.system)
                    .frame(height: layout.system)
                sectionDivider
                MarketSectionView(service: dashboard.market)
                    .frame(height: layout.market)
                productivityDivider
                TodoSectionView()
                    .frame(height: layout.todo)
                sectionDivider
                ImportantSectionView()
                    .frame(height: layout.important)
                sectionDivider
                MemoSectionView(
                    availableWidth: max(80, proxy.size.width - 36),
                    onPreferredHeightChange: { height in
                        guard abs(memoPreferredHeight - height) >= 1 else { return }
                        memoPreferredHeight = height
                    }
                )
                    .frame(height: layout.memo)
            }
            .animation(.easeInOut(duration: 0.18), value: dashboard.calendar.events.count)
            .animation(.easeInOut(duration: 0.18), value: todoItems.count)
            .animation(.easeInOut(duration: 0.18), value: importantItems.count)
            .animation(.easeInOut(duration: 0.18), value: memoPreferredHeight)
            .padding(.horizontal, 18)
            .background {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(backgroundOpacity)
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(backgroundOpacity * 0.28)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("DeskBoard Settings")
                .padding(7)
            }
        }
        .frame(minWidth: 320, minHeight: 620)
        .preferredColorScheme(preferredColorScheme)
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.04))
    }

    private var productivityDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.13))
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private func adaptiveLayout(for size: CGSize) -> SidebarSectionHeights {
        let height = size.height
        var base = SidebarSectionHeights(
            date: 104,
            quickOpen: 42,
            calendar: 100,
            system: 104,
            market: 112,
            todo: 100,
            important: 100,
            memo: 200
        )
        let dividerSpace: CGFloat = 6

        var deficit = max(0, base.total + dividerSpace - height)
        func shrink(_ value: inout CGFloat, to floor: CGFloat) {
            let reduction = min(deficit, max(0, value - floor))
            value -= reduction
            deficit -= reduction
        }
        shrink(&base.memo, to: 100)
        shrink(&base.todo, to: 80)
        shrink(&base.calendar, to: 80)
        shrink(&base.important, to: 70)
        shrink(&base.market, to: 104)
        shrink(&base.system, to: 96)
        shrink(&base.date, to: 96)
        shrink(&base.quickOpen, to: 36)

        let calendarTarget = min(210, max(base.calendar, 54 + CGFloat(dashboard.calendar.events.count) * 24))
        let importantTarget = min(180, max(base.important, 54 + CGFloat(importantItems.count) * 24))
        let todoTarget = max(base.todo, preferredTodoHeight(for: size.width))
        let memoTarget = max(base.memo, memoPreferredHeight)
        var result = base
        var availableExtra = max(0, height - base.total - dividerSpace)

        func grow(_ value: inout CGFloat, toward target: CGFloat) {
            let addition = min(availableExtra, max(0, target - value))
            value += addition
            availableExtra -= addition
        }
        grow(&result.calendar, toward: calendarTarget)
        grow(&result.important, toward: importantTarget)
        grow(&result.todo, toward: todoTarget)
        grow(&result.memo, toward: memoTarget)

        // Todo and Important start at the same visual height. Content can grow
        // either section, while otherwise unused room belongs to the memo.
        result.memo += availableExtra
        return result
    }

    private func preferredTodoHeight(for width: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let textWidth = max(100, width - 78)
        let rowsHeight = todoItems.reduce(CGFloat.zero) { total, item in
            let measurementText = item.title.isEmpty ? " " : item.title
            let bounds = (measurementText as NSString).boundingRect(
                with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            )
            return total + max(20, max(lineHeight, ceil(bounds.height))) + 7
        }
        return 50 + rowsHeight
    }
}

private struct SidebarSectionHeights {
    var date: CGFloat
    var quickOpen: CGFloat
    var calendar: CGFloat
    var system: CGFloat
    var market: CGFloat
    var todo: CGFloat
    var important: CGFloat
    var memo: CGFloat

    var total: CGFloat {
        date + quickOpen + calendar + system + market + todo + important + memo
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DashboardTypography.sectionTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlaceholderText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DashboardTypography.item)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum DashboardTypography {
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let item = Font.system(size: 13)
}
