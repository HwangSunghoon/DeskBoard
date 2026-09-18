import AppKit
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sidebarWindowController: DesktopWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DesktopWindowController(modelContainer: PersistenceController.shared.container)
        sidebarWindowController = controller
        controller.showSidebar()
        PersistenceController.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        sidebarWindowController?.stop()
        PersistenceController.shared.checkpoint()
    }

    func applicationDidResignActive(_ notification: Notification) {
        PersistenceController.shared.checkpoint()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !PersistenceController.shared.checkpoint() else { return .terminateNow }
        PersistenceController.shared.requestSaveHelp()
        // The only blocking warning: an explicit quit would discard unprotected edits.
        let alert = StorageQuitConfirmation.makeAlert()
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
}
