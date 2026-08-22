import SwiftUI

@main
struct DeskBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }

        MenuBarExtra("DeskBoard", systemImage: "rectangle.rightthird.inset.filled") {
            Button("Show DeskBoard") {
                NotificationCenter.default.post(name: .deskBoardShowSidebar, object: nil)
            }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit DeskBoard") { NSApp.terminate(nil) }
        }
    }
}
