import SwiftUI
import SwiftData

struct SidebarView: View {
    @EnvironmentObject private var dashboard: DashboardModel
    @AppStorage("appearance") private var appearance = "light"
    @AppStorage("backgroundOpacity") private var backgroundOpacity = 0.82
    @Query(sort: [SortDescriptor(\ImportantItem.sortOrder)]) private var importantItems: [ImportantItem]

    var body: some View {
        GeometryReader { proxy in
            let layout = adaptiveLayout(for: proxy.size.height)
            VStack(spacing: 0) {
                DateWeatherView(model: dashboard, weather: dashboard.weather)
                    .frame(height: layout.date)
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
                MemoSectionView()
                    .frame(height: layout.memo)
            }
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

    private func adaptiveLayout(for height: CGFloat) -> SidebarSectionHeights {
        let date: CGFloat = 104
        let system: CGFloat = 104
        let market: CGFloat = 68
        let minimumCalendar: CGFloat = 110
        let minimumTodo: CGFloat = 220
        let minimumImportant: CGFloat = 100
        let minimumMemo: CGFloat = 180
        let dividerSpace: CGFloat = 6

        let calendarTarget = min(210, max(minimumCalendar, 54 + CGFloat(dashboard.calendar.events.count) * 24))
        let importantTarget = min(180, max(minimumImportant, 54 + CGFloat(importantItems.count) * 24))
        let minimumTotal = date + system + market + minimumCalendar + minimumTodo + minimumImportant + minimumMemo + dividerSpace
        let availableExtra = max(0, height - minimumTotal)
        let calendarNeed = calendarTarget - minimumCalendar
        let importantNeed = importantTarget - minimumImportant
        let adaptiveNeed = calendarNeed + importantNeed
        let adaptiveBudget = min(availableExtra, adaptiveNeed)
        let scale = adaptiveNeed > 0 ? adaptiveBudget / adaptiveNeed : 0
        let calendar = minimumCalendar + calendarNeed * scale
        let important = minimumImportant + importantNeed * scale
        let flexibleExtra = max(0, availableExtra - adaptiveBudget)

        return SidebarSectionHeights(
            date: date,
            calendar: calendar,
            system: system,
            market: market,
            todo: minimumTodo + flexibleExtra * 0.42,
            important: important,
            memo: minimumMemo + flexibleExtra * 0.58
        )
    }
}

private struct SidebarSectionHeights {
    let date: CGFloat
    let calendar: CGFloat
    let system: CGFloat
    let market: CGFloat
    let todo: CGFloat
    let important: CGFloat
    let memo: CGFloat
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlaceholderText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
