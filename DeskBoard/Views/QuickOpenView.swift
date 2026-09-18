import AppKit
import SwiftUI

struct QuickOpenView: View {
    @ObservedObject private var store: QuickOpenStore

    init(store: QuickOpenStore? = nil) { self.store = store ?? .shared }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let iconWidth = width * 0.10
            let buttonWidth = width * 0.12
            let count = store.applications.count
            let spacing = count > 1 ? min(width * 0.075, (width * 0.90 - CGFloat(count) * buttonWidth) / CGFloat(count - 1)) : 0

            HStack(spacing: spacing) {
                ForEach(store.applications) { application in
                    QuickOpenButton(application: application, iconWidth: iconWidth, store: store)
                        .frame(width: buttonWidth, height: 34)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct QuickOpenButton: View {
    let application: QuickOpenApplication
    let iconWidth: CGFloat
    let store: QuickOpenStore
    @State private var showingLaunchError = false

    private var applicationURL: URL? { application.resolvedURL() }

    var body: some View {
        Button { openApplication() } label: {
            Group {
                if let icon = applicationIcon {
                    Image(nsImage: icon)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: iconWidth, height: 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(applicationURL == nil ? 0.24 : 1)
        .help(applicationURL == nil ? "\(application.name) is unavailable" : "Open \(application.name)")
        .accessibilityLabel(application.name)
        .popover(isPresented: $showingLaunchError) {
            Text("Could not open \(application.name). If it was moved or removed, select it again in Settings → Quick Open.")
                .font(.system(size: 12)).padding(12).frame(width: 240)
        }
    }

    private var applicationIcon: NSImage? {
        guard let applicationURL else { return nil }
        let didAccess = applicationURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { applicationURL.stopAccessingSecurityScopedResource() }
        }

        guard let icon = NSWorkspace.shared.icon(forFile: applicationURL.path).copy() as? NSImage else {
            return nil
        }
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }

    private func openApplication() {
        guard let applicationURL = store.urlForOpening(application) else {
            showingLaunchError = true
            return
        }
        let didAccess = applicationURL.startAccessingSecurityScopedResource()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.addsToRecentItems = false

        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { runningApplication, error in
            runningApplication?.unhide()
            runningApplication?.activate(options: [.activateAllWindows])
            if didAccess { applicationURL.stopAccessingSecurityScopedResource() }
            if error != nil || runningApplication == nil {
                Task { @MainActor in showingLaunchError = true }
            }
        }
    }
}
