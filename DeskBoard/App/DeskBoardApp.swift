import SwiftUI

@main
struct DeskBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        Settings {
            SettingsView()
        }

        MenuBarExtra(
            "DeskBoard",
            systemImage: "rectangle.rightthird.inset.filled",
            isInserted: $showMenuBarIcon
        ) {
            Button("Show DeskBoard") {
                NotificationCenter.default.post(name: .deskBoardShowSidebar, object: nil)
            }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit DeskBoard") { NSApp.terminate(nil) }
        }
    }
}
