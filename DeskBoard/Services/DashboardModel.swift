import AppKit
import Combine
import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var now = Date()
    let system = SystemMonitor()
    let calendar = CalendarService()
    let weather = WeatherService()
    let market = MarketService()

    private var clock: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .deskBoardDataSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.market.schedule()
                await self?.calendar.refresh()
                await self?.weather.refresh()
                await self?.market.refresh()
            }
        })
    }

    func start() {
        guard clock == nil else { return }
        system.start()
        calendar.start()
        weather.start()
        market.start()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = .now }
        }
        timer.tolerance = 0.1
        clock = timer
    }

    func stop() {
        clock?.invalidate()
        clock = nil
        system.stop()
    }
}

extension Notification.Name {
    static let deskBoardWindowSettingsChanged = Notification.Name("DeskBoard.windowSettingsChanged")
    static let deskBoardDataSettingsChanged = Notification.Name("DeskBoard.dataSettingsChanged")
    static let deskBoardShowSidebar = Notification.Name("DeskBoard.showSidebar")
}
