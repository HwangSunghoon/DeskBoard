import AppKit
import SwiftUI

@MainActor
final class DeskBoardHelpWindowController: NSWindowController {
    static let shared = DeskBoardHelpWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "DeskBoard Help"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DeskBoardHelpView())
        window.contentMinSize = NSSize(width: 460, height: 400)
        window.center()
        window.setFrameAutosaveName("DeskBoardHelp")
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func showHelp() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct DeskBoardHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DeskBoard Help").font(.largeTitle.weight(.semibold))
                    Text("A lightweight dashboard for your Mac desktop.")
                        .foregroundStyle(.secondary)
                }
                topic("Getting started", "Use the gear button at the bottom of the sidebar to open Settings. Time, weather, and Memo are always available. Turn other sections on or off in Settings → Sections; hiding a section does not delete its saved content.")
                topic("Arrange your dashboard", "In Settings, drag a row using its three-line handle to reorder Sections, Quick Open applications, World Clock cities, or market indicators. Your order is saved automatically. Time, weather, and Quick Open stay at the top. Memo can move but cannot be turned off.")
                topic("Window and appearance", "Choose the left or right side and the display in General. Desktop mode keeps DeskBoard near the wallpaper; Always on Top keeps it above other windows. You can also choose launch at login, Dock and menu bar visibility, light or dark appearance, background opacity, and a digital or analog clock.")
                topic("Today and weather", "Allow Calendar access to show today's events. Choose a calendar in Settings → Data. Timed events can show their location on the right. To change the weather city, choose Change next to Weather location in Data, search for a city, and select the result with the correct region and country. Its name and coordinates are saved together, and the weather refreshes immediately. No device location permission is required. Search needs an internet connection; canceling leaves your current city unchanged.")
                topic("Todo", "Click +, type a task, and press Return to save it. Double-click a task to edit its title. Click its circle to mark it complete. Hover over a task to reveal its delete button. Long lists scroll inside the Todo section.")
                topic("Important", "Click + and enter an Event Title. Click Date to choose an optional date from the calendar, then press Return or click the checkmark to save. Items are grouped by upcoming dates, past dates, and undated reminders. Hover over an item to reveal its delete button.")
                topic("Memo", "Click the memo area to write. Your text saves automatically on this Mac. The placeholder disappears while you edit. Longer notes scroll inside the section, and Memo uses the space left after the other sections have been sized.")
                topic("Focus Timer", "Set focus and break lengths in Settings, then use Play, Pause, and Reset in the sidebar. This is a countdown timer. When a session ends, click Break or Focus to start the next session. Duration changes apply to the next session. Hiding the section does not pause an active timer.")
                topic("World Clock", "Add up to four cities in Settings. They appear in equal-width columns. Times use the 24-hour format and adjust for daylight saving time. A +1d or −1d label means that city's calendar date differs from the date on your Mac.")
                topic("Quick Open", "Choose Add Application in Settings and select a local .app. You can add up to six applications. Click an icon in the sidebar to launch or activate the app. If an application becomes unavailable, remove it and select it again. An empty Quick Open list takes no space in the sidebar.")
                topic("Market", "Choose 2–6 indicators in Settings and drag their three-line handles to arrange them. The sidebar follows this order from left to right, then top to bottom. Each entry shows its name, value, and percentage change. Set the refresh interval in Data. Quotes may be delayed or cached; Yahoo Finance's public endpoint can change or become unavailable. This information is for reference, not financial advice.")
                topic("System", "CPU, RAM, and BAT show processor use, memory use, and battery level. Download and Upload show network throughput per second, not your connection's maximum speed.")
                topic("Data and troubleshooting", "Tasks, important items, notes, and preferences are stored locally. Short connection or saving failures do not interrupt editing. Cached weather and quotes stay visible; a small dot marks prolonged update delays, with details on hover. Saving retries silently and keeps a local recovery copy when possible. A Save issue control appears only after both save paths have failed for several minutes. Recovery copy offers export and explicit restoration without deleting the original database. For missing events, check Calendar access in System Settings → Privacy & Security → Calendars.")
                Text("Weather data: [Open-Meteo](https://open-meteo.com/) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). City search: [GeoNames](https://www.geonames.org/) via Open-Meteo. Market data: Yahoo Finance; quotes may be delayed.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func topic(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(text).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
