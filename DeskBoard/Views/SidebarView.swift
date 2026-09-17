import AppKit
import SwiftUI
import SwiftData

struct SidebarView: View {
    @EnvironmentObject private var dashboard: DashboardModel
    @AppStorage("appearance") private var appearance = "light"
    @AppStorage("backgroundOpacity") private var backgroundOpacity = 0.82
    @Query(sort: [SortDescriptor(\TodoItem.sortOrder), SortDescriptor(\TodoItem.createdAt)]) private var todoItems: [TodoItem]
    @Query(sort: [SortDescriptor(\ImportantItem.sortOrder)]) private var importantItems: [ImportantItem]
    @ObservedObject private var preferences = DashboardPreferences.shared
    @ObservedObject private var worldClock = WorldClockStore.shared
    @ObservedObject private var quickOpen = QuickOpenStore.shared
    @ObservedObject private var calendar: CalendarService
    @State private var isAddingTodo = false
    @State private var isAddingImportant = false
    @State private var memoPreferredHeight: CGFloat = 180

    init(calendar: CalendarService) {
        self.calendar = calendar
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = adaptiveLayout(for: proxy.size)
            VStack(spacing: 0) {
                DateWeatherView(model: dashboard, weather: dashboard.weather)
                    .frame(height: layout.date)
                if !quickOpen.applications.isEmpty {
                    QuickOpenView()
                        .frame(height: layout.quickOpen)
                }
                ForEach(preferences.orderedVisibleSections) { section in
                    if section == .todo { productivityDivider }
                    else { sectionDivider }
                    sectionContent(section, layout: layout, width: proxy.size.width)
                }
                Spacer(minLength: 0)
                Color.clear.frame(height: layout.footer)
            }
            .environment(\.compactSidebarSections, layout.compact)
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
            .overlay(alignment: .bottomLeading) {
                StorageStatusView().padding(.leading, 18).padding(.bottom, 8)
            }
        }
        .frame(minWidth: 320, minHeight: 620)
        .preferredColorScheme(preferredColorScheme)
    }

    @ViewBuilder
    private func sectionContent(_ section: DashboardSection, layout: SidebarSectionHeights, width: CGFloat) -> some View {
        switch section {
        case .today:
            CalendarSectionView(service: calendar)
                .frame(height: layout.calendar)
        case .worldClock:
            WorldClockView(store: worldClock, now: dashboard.now)
                .frame(height: layout.worldClock)
        case .system:
            SystemSectionView(monitor: dashboard.system)
                .frame(height: layout.system)
        case .market:
            MarketSectionView(service: dashboard.market)
                .frame(height: layout.market)
        case .todo:
            TodoSectionView(isAdding: $isAddingTodo, availableHeight: layout.todo)
                .frame(height: layout.todo)
        case .focusTimer:
            FocusTimerView(timer: dashboard.focusTimer, now: dashboard.now)
                .frame(height: layout.focus)
        case .important:
            ImportantSectionView(isAdding: $isAddingImportant)
                .frame(height: layout.important)
        case .memo:
            MemoSectionView(
                availableWidth: max(80, width - 36),
                onPreferredHeightChange: { height in
                    guard abs(memoPreferredHeight - height) >= 1 else { return }
                    memoPreferredHeight = height
                }
            )
            .frame(height: layout.memo)
        }
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
        SidebarSectionHeights.calculate(
            height: size.height, visible: preferences.visibleSections,
            marketCount: preferences.marketInstruments.count,
            calendarCount: calendar.events.count,
            todoHeight: preferredTodoHeight(for: size.width),
            importantCount: importantItems.count,
            addingTodo: isAddingTodo && preferences.visibleSections.contains(.todo),
            addingImportant: isAddingImportant && preferences.visibleSections.contains(.important),
            memoHeight: memoPreferredHeight, worldClockCount: worldClock.cities.count,
            quickOpenCount: quickOpen.applications.count
        )
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

private struct CompactSidebarSectionsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var compactSidebarSections: Bool {
        get { self[CompactSidebarSectionsKey.self] }
        set { self[CompactSidebarSectionsKey.self] = newValue }
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
