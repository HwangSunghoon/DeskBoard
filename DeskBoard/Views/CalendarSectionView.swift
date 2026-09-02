import SwiftUI
import EventKit

struct CalendarSectionView: View {
    @ObservedObject var service: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(text: "Today")
            content
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch service.authorizationStatus {
        case .fullAccess:
            if service.events.isEmpty {
                PlaceholderText(text: "No events today")
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(service.events) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 48, alignment: .leading)
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
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
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
