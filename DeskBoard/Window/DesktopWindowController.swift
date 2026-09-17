import AppKit
import SwiftData
import SwiftUI

final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DesktopWindowController: NSWindowController {
    private let sidebarWidthRatio: CGFloat = 0.25
    private let horizontalInset: CGFloat = 12
    private let verticalInset: CGFloat = 12
    private let dashboard = DashboardModel()
    private var observers: [NSObjectProtocol] = []

    convenience init(modelContainer: ModelContainer?) {
        let panel = SidebarPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.init(window: panel)
        configure(panel, modelContainer: modelContainer)
        observeChanges()
        dashboard.start()
    }

    func showSidebar(on screen: NSScreen? = nil) {
        guard let window else { return }
        let targetScreen = screen ?? preferredScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else { return }

        let visibleFrame = targetScreen.visibleFrame
        let width = max(320, targetScreen.frame.width * sidebarWidthRatio)
        let isLeft = UserDefaults.standard.string(forKey: "sidebarSide") == "left"
        let frame = NSRect(
            x: isLeft ? visibleFrame.minX + horizontalInset : visibleFrame.maxX - width - horizontalInset,
            y: visibleFrame.minY + verticalInset,
            width: width,
            height: max(560, visibleFrame.height - verticalInset * 2)
        )

        window.setFrame(frame, display: true)
        applyWindowPreferences()
        showWindow(nil)
        window.orderFrontRegardless()
    }

    func stop() {
        dashboard.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func configure(_ panel: NSPanel, modelContainer: ModelContainer?) {
        panel.title = "DeskBoard"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.level = .normal
        if let modelContainer {
            panel.contentView = NSHostingView(
            rootView: SidebarView(calendar: dashboard.calendar)
                .environmentObject(dashboard)
                .modelContainer(modelContainer)
            )
            modelContainer.mainContext.autosaveEnabled = false
        } else {
            panel.contentView = NSHostingView(rootView: StorageUnavailableView(dashboard: dashboard))
        }
    }

    private func observeChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: PersistenceController.didRecover, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.window as? SidebarPanel else { return }
                self.configure(panel, modelContainer: PersistenceController.shared.container)
            }
        })
        observers.append(center.addObserver(forName: .deskBoardWindowSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.showSidebar()
        })
        observers.append(center.addObserver(forName: .deskBoardShowSidebar, object: nil, queue: .main) { [weak self] _ in
            self?.showSidebar()
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.showSidebar()
        })
    }

    private func applyWindowPreferences() {
        guard let window else { return }
        let floating = UserDefaults.standard.string(forKey: "windowMode") == "floating"
        if floating {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        } else {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
        let showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    private func preferredScreen() -> NSScreen? {
        guard let selectedID = UserDefaults.standard.string(forKey: "selectedDisplayID"), !selectedID.isEmpty else { return nil }
        return NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.stringValue == selectedID
        }
    }
}
