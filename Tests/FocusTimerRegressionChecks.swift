import Foundation

// Run with swiftc alongside DeskBoard/Services/FocusTimerStore.swift.
@main
struct FocusTimerRegressionChecks {
    @MainActor static func main() {
        let suite = "DeskBoard.FocusTimerChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tick = Date(timeIntervalSince1970: 1_800_000_000)
        let start = tick.addingTimeInterval(0.8)
        let timer = FocusTimerStore(defaults: defaults, now: tick)
        func seconds(_ date: Date) -> Int {
            timer.remainingSeconds(at: date, focusMinutes: 55, breakMinutes: 5)
        }

        precondition(seconds(tick) == 3300)
        timer.toggle(focusMinutes: 55, breakMinutes: 5, now: start)
        // The view still has the previous dashboard tick when the button publishes a session.
        precondition(seconds(tick) == 3300, "Starting between ticks must not show 55:01")
        precondition(seconds(tick.addingTimeInterval(1)) == 3300)
        precondition(seconds(tick.addingTimeInterval(2)) == 3299)
        precondition(seconds(start.addingTimeInterval(1)) == 3299)

        let pause = start.addingTimeInterval(60.25)
        timer.toggle(focusMinutes: 55, breakMinutes: 5, now: pause)
        precondition(timer.session.status == .paused)
        precondition(seconds(pause) == 3240)
        precondition(seconds(pause.addingTimeInterval(600)) == 3240)
        let resume = pause.addingTimeInterval(600)
        timer.toggle(focusMinutes: 55, breakMinutes: 5, now: resume)
        precondition(seconds(resume.addingTimeInterval(-0.9)) == 3240, "Resume must not add a displayed second")
        precondition(seconds(resume.addingTimeInterval(1)) == 3239)

        let restored = FocusTimerStore(defaults: defaults, now: resume.addingTimeInterval(10))
        precondition(restored.remainingSeconds(at: resume.addingTimeInterval(10), focusMinutes: 55, breakMinutes: 5) == 3230)
        let deadline = timer.session.deadline!
        precondition(seconds(deadline.addingTimeInterval(-0.1)) == 1)
        precondition(seconds(deadline) == 0)
        timer.update(now: deadline)
        precondition(timer.session.status == .finished)
        precondition(seconds(deadline.addingTimeInterval(10)) == 0)
        timer.toggle(focusMinutes: 55, breakMinutes: 5, now: deadline.addingTimeInterval(0.5))
        precondition(timer.session.phase == .rest)
        precondition(seconds(deadline) == 300, "Starting a break must not show 05:01")
        precondition(seconds(deadline.addingTimeInterval(1.5)) == 299)
        timer.reset()
        precondition(timer.session.status == .idle && timer.session.phase == .focus)
        precondition(seconds(deadline) == 3300)
        print("PASS: start/resume with stale ticks, countdown boundaries, pause, restoration, completion, break, reset")
    }
}
