import AppKit
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sidebarWindowController: DesktopWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DesktopWindowController(modelContainer: PersistenceController.shared.container)
        sidebarWindowController = controller
        controller.showSidebar()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        sidebarWindowController?.stop()
        try? PersistenceController.shared.container.mainContext.save()
    }
}
