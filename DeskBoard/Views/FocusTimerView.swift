import SwiftUI

struct FocusTimerView: View {
    @ObservedObject var timer: FocusTimerStore
    let now: Date
    @AppStorage("focusMinutes") private var focusMinutes = 25
    @AppStorage("breakMinutes") private var breakMinutes = 5

    var body: some View {
        HStack(spacing: 8) {
            Text(timer.session.phase == .rest ? "Break" : "Focus")
                .font(DashboardTypography.sectionTitle)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            let seconds = timer.remainingSeconds(at: now, focusMinutes: focusMinutes, breakMinutes: breakMinutes)
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 20, weight: .light, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("\(seconds / 60) minutes, \(seconds % 60) seconds remaining")
            Button { timer.toggle(focusMinutes: focusMinutes, breakMinutes: breakMinutes) } label: {
                if timer.session.status == .finished {
                    Text(timer.session.phase == .focus ? "Break" : "Focus").font(.system(size: 11))
                } else {
                    Image(systemName: timer.session.status == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 11))
                }
            }
            .frame(minWidth: 24, minHeight: 24)
            .help(actionTitle)
            .accessibilityLabel(actionTitle)
            Button { timer.reset() } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
            }
            .frame(width: 24, height: 24)
            .help("Reset Focus Timer")
            .accessibilityLabel("Reset Focus Timer")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var actionTitle: String {
        switch timer.session.status {
        case .idle: "Start Focus"
        case .running: "Pause Timer"
        case .paused: "Resume Timer"
        case .finished: timer.session.phase == .focus ? "Start Break" : "Start Focus"
        }
    }
}
