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
        let alert = NSAlert()
        alert.messageText = "Some edits could not be saved"
        alert.informativeText = "Your edits are still on screen, but neither the database nor a recovery copy could be saved. Keep DeskBoard open to retry or export a copy using the save status control."
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
}
