import AppKit
import SwiftUI

@main struct ErrorLabApp: App {
    @NSApplicationDelegateAdaptor(LabDelegate.self) private var delegate
    @StateObject private var lab = LabController.shared
    var body: some Scene {
        Window("DeskBoard Error Lab — isolated sandbox", id: "lab") {
            LabView(lab: lab)
                .task {
                    guard CommandLine.arguments.contains("--self-test") else { return }
                    await lab.runAutomatic()
                    if CommandLine.arguments.contains("--snapshots") { await lab.renderSnapshots() }
                    // Tests use local sessions; the interactive session remains healthy.
                    lab.choose(.healthy)
                    NSApp.terminate(nil)
                }
        }
        .defaultSize(width: 1060, height: 760)
        Settings { SettingsView() }
    }
}

final class LabDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        LabController.shared.shouldQuit()
    }
    func applicationWillTerminate(_ notification: Notification) {
        LabController.shared.hideDesktop()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
