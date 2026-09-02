import AppKit
import EventKit
import Foundation

struct CalendarEventItem: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let isAllDay: Bool
    let location: String?
}

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var events: [CalendarEventItem] = []
    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private let store = EKEventStore()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.refresh() } })
    }

    func start() {
        Task { await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = 30
    }

    func requestAccess() async {
        do { _ = try await store.requestFullAccessToEvents() } catch { }
        await refresh()
    }

    func refresh() async {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard authorizationStatus == .fullAccess else {
            events = []
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let selectedID = UserDefaults.standard.string(forKey: "selectedCalendarID") ?? ""
        let selectedCalendars = selectedID.isEmpty ? nil : store.calendars(for: .event).filter { $0.calendarIdentifier == selectedID }
        let matches = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: selectedCalendars))
        events = matches.sorted { $0.startDate < $1.startDate }.map {
            let location = shortLocation(for: $0)
            return CalendarEventItem(
                id: $0.eventIdentifier ?? UUID().uuidString,
                title: $0.title,
                startDate: $0.startDate,
                isAllDay: $0.isAllDay,
                location: location?.isEmpty == false ? location : nil
            )
        }
    }

    private func shortLocation(for event: EKEvent) -> String? {
        let rawLocation = event.structuredLocation?.title ?? event.location
        guard let rawLocation else { return nil }
        return rawLocation
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    deinit {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
