import AppKit
import Combine
import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var now = Date()
    let system = SystemMonitor()
    let calendar = CalendarService()
    let weather = WeatherService()
    let focusTimer = FocusTimerStore.shared

    private var clock: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sectionObserver: AnyCancellable?

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .deskBoardDataSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.calendar.isRunning == true { await self?.calendar.refresh() }
            }
        })
    }

    func start() {
        guard clock == nil else { return }
        weather.start()
        sectionObserver = DashboardPreferences.shared.$visibleSections.sink { [weak self] sections in
            guard let self else { return }
            if sections.contains(.system) { self.system.start() } else { self.system.stop() }
            if sections.contains(.today) { self.calendar.start() } else { self.calendar.stop() }
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = .now
                self.focusTimer.update(now: self.now)
            }
        }
        timer.tolerance = 0.1
        clock = timer
    }

    func stop() {
        clock?.invalidate()
        clock = nil
        system.stop()
        calendar.stop()
        weather.stop()
        sectionObserver = nil
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

extension Notification.Name {
    static let deskBoardWindowSettingsChanged = Notification.Name("DeskBoard.windowSettingsChanged")
    static let deskBoardDataSettingsChanged = Notification.Name("DeskBoard.dataSettingsChanged")
    static let deskBoardShowSidebar = Notification.Name("DeskBoard.showSidebar")
}
