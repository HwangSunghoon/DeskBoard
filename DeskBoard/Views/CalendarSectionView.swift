import SwiftUI
import EventKit

struct CalendarSectionView: View {
    @Environment(\.compactSidebarSections) private var compact
    @ObservedObject var service: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: CalendarSectionMetrics.headerSpacing(compact: compact)) {
            SectionTitle(text: "Today")
                .frame(height: CalendarSectionMetrics.headerHeight, alignment: .leading)
            content
        }
        .padding(.vertical, CalendarSectionMetrics.verticalPadding(compact: compact))
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func timeLabel(for event: CalendarEventItem) -> String {
        event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private var content: some View {
        switch service.authorizationStatus {
        case .fullAccess:
            if service.events.isEmpty {
                PlaceholderText(text: "No events today")
            } else {
                let timeWidth = CalendarSectionMetrics.timeColumnWidth(for: service.events.map { timeLabel(for: $0) })
                ScrollView {
                    LazyVStack(spacing: CalendarSectionMetrics.rowSpacing) {
                        ForEach(service.events) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(timeLabel(for: event))
                                    .font(.system(size: CalendarSectionMetrics.timeFontSize))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: timeWidth, alignment: .leading)
                                Text(event.title)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .layoutPriority(1)
                                Spacer(minLength: 0)
                                if !event.isAllDay, let location = event.location {
                                    Text(location)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: 82, alignment: .trailing)
                                }
                            }
                            .frame(height: CalendarSectionMetrics.rowHeight, alignment: .leading)
                        }
                    }
                    .padding(.bottom, CalendarSectionMetrics.bottomInset)
                }
                .scrollIndicators(.never)
            }
        case .notDetermined:
            Button("Allow Calendar Access") { Task { await service.requestAccess() } }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        default:
            PlaceholderText(text: "Calendar access is disabled")
        }
    }
}
