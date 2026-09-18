import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Shared by the app and isolated lab so the quit warning cannot drift.
@MainActor enum StorageQuitConfirmation {
    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Some edits could not be saved"
        alert.informativeText = "Your edits are still on screen, but neither the database nor a recovery copy could be saved. Keep DeskBoard open to retry or export a copy using the save status control."
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert
    }
}

/// Invisible during normal saves and short failures. No automatic alerts.
struct StorageStatusView: View {
    @ObservedObject private var storage: PersistenceController
    @State private var showingDetails = false
    @State private var confirmingRestore = false
    @State private var exportError: String?

    init(storage: PersistenceController? = nil) {
        self.storage = storage ?? .shared
    }

    var body: some View {
        if storage.recoveryMessage != nil || storage.needsSaveAttention {
            Button(storage.recoveryMessage != nil ? "Recovery copy" : "Save issue") { showingDetails = true }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .help("Your edits stay on screen. Click for recovery options.")
                .popover(isPresented: $showingDetails) {
                    recoveryDetails
                }
        }
    }

    // Also rendered by the isolated error-UI check, using the same production content.
    var recoveryDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(storage.recoveryMessage ?? "Edits are still on screen, but saving and the recovery copy have both been unavailable for several minutes. DeskBoard keeps retrying. You can export a copy to another location.")
            HStack {
                Button(storage.hasPendingRecovery ? "Restore recovery copy…" : "Retry saving") {
                    if storage.isTemporary || storage.hasPendingRecovery { confirmingRestore = true }
                    else { storage.retry() }
                }
                Button("Export copy…", action: export)
            }
            if let exportError { Text(exportError).foregroundStyle(.secondary) }
        }
        .font(.system(size: 12)).padding(16).frame(width: 330)
        .confirmationDialog("Restore the recovery copy?", isPresented: $confirmingRestore) {
            Button("Restore copy") { storage.retry() }
        } message: {
            Text("This replaces the database's Todo, Important and Memo contents with the recovery copy. A separate archive of the old contents is saved first. Export the recovery copy if you want to inspect it before restoring.")
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DeskBoard-Recovery.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try storage.exportData().write(to: url, options: .atomic)
            exportError = nil
        } catch { exportError = "Could not export here. Try another folder or disk." }
    }
}

/// Used only if both disk and in-memory SwiftData initialization fail.
struct StorageUnavailableView: View {
    @ObservedObject var dashboard: DashboardModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DateWeatherView(model: dashboard, weather: dashboard.weather)
            Text("Your saved content is untouched. Data recovery is available below.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            StorageStatusView()
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }
        }
        .padding(18).background(.ultraThinMaterial)
    }
}
