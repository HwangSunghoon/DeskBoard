import AppKit
import SwiftUI

@MainActor extension LabController {
    /// Render only our own views, never the desktop or another app's UI.
    func renderSnapshots() async {
        let directory = root.appendingPathComponent("Snapshots")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for tab in 0..<6 {
                let host = NSHostingView(rootView: LabView(lab: self, tab: tab)
                    .frame(width: 1060, height: 760)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .light))
                host.frame = NSRect(x: 0, y: 0, width: 1060, height: 760)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: directory.appendingPathComponent("tab-\(tab).png"), options: .atomic)
                }
                window.close()
            }
        } catch { record("UI rendering", "ERROR", error.localizedDescription) }
    }
}
