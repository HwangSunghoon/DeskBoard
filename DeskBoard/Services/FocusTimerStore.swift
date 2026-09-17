import Combine
import Foundation

@MainActor
final class FocusTimerStore: ObservableObject {
    static let shared = FocusTimerStore()

    enum Phase: String, Codable { case focus, rest }
    enum Status: String, Codable { case idle, running, paused, finished }
    struct Session: Codable {
        var phase: Phase = .focus
        var status: Status = .idle
        var remaining: TimeInterval = 0
        var deadline: Date?
    }

    @Published private(set) var session: Session
    private let defaults: UserDefaults
    private let key = "focusTimer.session.v1"

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        session = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(Session.self, from: $0) } ?? Session()
        update(now: now)
    }

    func remainingSeconds(at now: Date, focusMinutes: Int, breakMinutes: Int) -> Int {
        switch session.status {
        case .idle: return (session.phase == .focus ? focusMinutes : breakMinutes) * 60
        case .running: return Int(ceil(runningRemaining(at: now)))
        case .paused: return max(0, Int(ceil(session.remaining)))
        case .finished: return 0
        }
    }

    func toggle(focusMinutes: Int, breakMinutes: Int, now: Date = .now) {
        update(now: now)
        switch session.status {
        case .running:
            session.remaining = runningRemaining(at: now)
            session.deadline = nil
            session.status = .paused
        case .paused:
            session.deadline = now.addingTimeInterval(session.remaining)
            session.status = .running
        case .idle, .finished:
            if session.status == .finished {
                session.phase = session.phase == .focus ? .rest : .focus
            }
            let minutes = session.phase == .focus ? focusMinutes : breakMinutes
            session.remaining = TimeInterval(max(1, min(180, minutes)) * 60)
            session.deadline = now.addingTimeInterval(session.remaining)
            session.status = .running
        }
        save()
    }

    func reset() {
        session = Session()
        save()
    }

    func update(now: Date) {
        guard session.status == .running, session.deadline.map({ $0 <= now }) ?? true else { return }
        session.remaining = 0
        session.deadline = nil
        session.status = .finished
        save()
    }

    private func runningRemaining(at now: Date) -> TimeInterval {
        // The dashboard tick can precede a start/resume click. Never display more
        // than the duration captured at that click, even with a stale render time.
        max(0, min(session.remaining, (session.deadline ?? now).timeIntervalSince(now)))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: key) }
    }
}
