import AppKit
import EventKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("windowMode") private var windowMode = "desktop"
    @AppStorage("sidebarSide") private var sidebarSide = "right"
    @AppStorage("selectedDisplayID") private var selectedDisplayID = ""
    @AppStorage("showDockIcon") private var showDockIcon = true
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("appearance") private var appearance = "light"
    @AppStorage("backgroundOpacity") private var backgroundOpacity = 0.82
    @AppStorage("clockStyle") private var clockStyle = "digital"
    @AppStorage("weatherLocationName") private var weatherLocationName = "Seoul"
    @AppStorage("weatherLatitude") private var weatherLatitude = 37.5665
    @AppStorage("weatherLongitude") private var weatherLongitude = 126.9780
    @AppStorage("marketRefreshInterval") private var marketRefreshInterval = 60.0
    @AppStorage("selectedCalendarID") private var selectedCalendarID = ""

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var displays: [DisplayChoice] = []
    @State private var calendars: [CalendarChoice] = []
    @State private var dataChangeTask: Task<Void, Never>?

    var body: some View {
        dataObservedSettings
    }

    private var settingsForm: some View {
        Form {
            generalSection
            appearanceSection
            dataSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .onAppear {
            reloadDisplays()
            reloadCalendars()
        }
        .onChange(of: windowMode) { notifyWindowChange() }
        .onChange(of: sidebarSide) { notifyWindowChange() }
        .onChange(of: selectedDisplayID) { notifyWindowChange() }
        .onChange(of: showDockIcon) { notifyWindowChange() }
    }

    private var dataObservedSettings: some View {
        settingsForm
        .onChange(of: weatherLocationName) { scheduleDataChange() }
        .onChange(of: weatherLatitude) { scheduleDataChange() }
        .onChange(of: weatherLongitude) { scheduleDataChange() }
        .onChange(of: marketRefreshInterval) { scheduleDataChange() }
        .onChange(of: selectedCalendarID) { scheduleDataChange() }
        .onDisappear { dataChangeTask?.cancel() }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: updateLaunchAtLogin))
            Picker("Window", selection: $windowMode) {
                Text("Desktop").tag("desktop")
                Text("Always on Top").tag("floating")
            }
            Picker("Side", selection: $sidebarSide) {
                Text("Left").tag("left")
                Text("Right").tag("right")
            }
            Picker("Display", selection: $selectedDisplayID) {
                Text("Main Display").tag("")
                ForEach(displays) { display in Text(display.name).tag(display.id) }
            }
            .help("Choose which monitor shows the DeskBoard sidebar.")
            Toggle("Show Dock Icon", isOn: $showDockIcon)
                .help("Also show DeskBoard in the Dock and Command-Tab app switcher.")
            Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
                .help("Show DeskBoard controls in the macOS menu bar.")
            if let launchError {
                Text(launchError).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Appearance", selection: $appearance) {
                Text("Light").tag("light")
                Text("Dark").tag("dark")
                Text("System").tag("system")
            }
            Picker("Clock", selection: $clockStyle) {
                Text("Digital").tag("digital")
                Text("Analog").tag("analog")
            }
            LabeledContent("Background Opacity") {
                HStack {
                    Slider(value: $backgroundOpacity, in: 0.45...0.96)
                    Text("\(Int((backgroundOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Picker("Calendar", selection: $selectedCalendarID) {
                Text("All Calendars").tag("")
                ForEach(calendars) { calendar in Text(calendar.name).tag(calendar.id) }
            }

            TextField("Weather location", text: $weatherLocationName)

            Picker("Market refresh", selection: $marketRefreshInterval) {
                Text("1 minute").tag(60.0)
                Text("5 minutes").tag(300.0)
                Text("15 minutes").tag(900.0)
            }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
            launchError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchError = error.localizedDescription
        }
    }

    private func reloadDisplays() {
        displays = NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return DisplayChoice(id: number?.stringValue ?? screen.localizedName, name: screen.localizedName)
        }
    }

    private func reloadCalendars() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            calendars = []
            return
        }
        calendars = EKEventStore().calendars(for: .event)
            .map { CalendarChoice(id: $0.calendarIdentifier, name: $0.title) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func notifyWindowChange() {
        NotificationCenter.default.post(name: .deskBoardWindowSettingsChanged, object: nil)
    }

    private func scheduleDataChange() {
        dataChangeTask?.cancel()
        dataChangeTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .deskBoardDataSettingsChanged, object: nil)
        }
    }
}

private struct DisplayChoice: Identifiable {
    let id: String
    let name: String
}

private struct CalendarChoice: Identifiable {
    let id: String
    let name: String
}
