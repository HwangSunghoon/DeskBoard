import AppKit
import EventKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var quickOpenStore = QuickOpenStore.shared
    @ObservedObject private var preferences = DashboardPreferences.shared
    @ObservedObject private var worldClock = WorldClockStore.shared
    @ObservedObject private var weatherLocation = WeatherLocationStore.shared
    @AppStorage("focusMinutes") private var focusMinutes = 25
    @AppStorage("breakMinutes") private var breakMinutes = 5
    @State private var showingCityPicker = false
    @State private var showingIndicatorPicker = false
    @State private var showingWeatherPicker = false

    @AppStorage("windowMode") private var windowMode = "desktop"
    @AppStorage("sidebarSide") private var sidebarSide = "right"
    @AppStorage("selectedDisplayID") private var selectedDisplayID = ""
    @AppStorage("showDockIcon") private var showDockIcon = true
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("appearance") private var appearance = "light"
    @AppStorage("backgroundOpacity") private var backgroundOpacity = 0.82
    @AppStorage("clockStyle") private var clockStyle = "digital"
    @AppStorage("marketRefreshInterval") private var marketRefreshInterval = 60.0
    @AppStorage("selectedCalendarID") private var selectedCalendarID = ""

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var displays: [DisplayChoice] = []
    @State private var calendars: [CalendarChoice] = []
    @State private var dataChangeTask: Task<Void, Never>?
    @State private var quickOpenError: String?

    var body: some View {
        dataObservedSettings
    }

    private var settingsForm: some View {
        Form {
            generalSection
            appearanceSection
            sectionsSection
            focusTimerSection
            worldClockSection
            quickOpenSection
            marketSection
            dataSection
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 660)
        .sheet(isPresented: $showingCityPicker) {
            WorldClockCityPicker(store: worldClock)
        }
        .sheet(isPresented: $showingIndicatorPicker) {
            MarketInstrumentPicker(preferences: preferences)
        }
        .sheet(isPresented: $showingWeatherPicker) {
            WeatherLocationPicker(store: weatherLocation)
        }
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
        .onChange(of: marketRefreshInterval) { scheduleDataChange() }
        .onChange(of: selectedCalendarID) { scheduleDataChange() }
        .onDisappear {
            if dataChangeTask != nil {
                dataChangeTask?.cancel()
                dataChangeTask = nil
                NotificationCenter.default.post(name: .deskBoardDataSettingsChanged, object: nil)
            }
        }
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

            LabeledContent("Weather location") {
                HStack(spacing: 8) {
                    Text(weatherLocation.selected.displayName)
                        .lineLimit(1).truncationMode(.middle)
                        .help(weatherLocation.selected.displayName)
                    Button("Change…") { showingWeatherPicker = true }
                }
            }

            Picker("Market refresh", selection: $marketRefreshInterval) {
                Text("1 minute").tag(60.0)
                Text("5 minutes").tag(300.0)
                Text("15 minutes").tag(900.0)
            }
        }
    }

    private var sectionsSection: some View {
        Section("Sections") {
            ReorderableSettingsList(items: preferences.sectionOrder, onMove: preferences.moveSections) { section in
                HStack {
                    if section == .memo {
                        Text(section.title)
                        Spacer()
                        Text("Always on").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Toggle(section.title, isOn: Binding(
                            get: { preferences.visibleSections.contains(section) },
                            set: { preferences.setVisible(section, $0) }
                        ))
                        Spacer(minLength: 8)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var focusTimerSection: some View {
        Section("Focus Timer") {
            Stepper("Focus: \(focusMinutes) min", value: $focusMinutes, in: 1...180)
            Stepper("Break: \(breakMinutes) min", value: $breakMinutes, in: 1...60)
        }
    }

    private var worldClockSection: some View {
        Section("World Clock") {
            ReorderableSettingsList(items: worldClock.cities, onMove: worldClock.moveCities) { city in
                HStack {
                    Text(city.name)
                    Spacer()
                    Button { worldClock.remove(city.id) } label: { Image(systemName: "xmark") }
                        .help("Remove \(city.name)")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                Button("Add City", systemImage: "plus") { showingCityPicker = true }
                    .disabled(worldClock.cities.count >= WorldClockStore.maximumCities)
                Spacer()
                Text("\(worldClock.cities.count)/\(WorldClockStore.maximumCities)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var marketSection: some View {
        Section("Market") {
            ReorderableSettingsList(items: preferences.marketInstruments, onMove: preferences.moveInstruments) { instrument in
                HStack {
                    Text(instrument.displayName)
                    Spacer()
                    Button { preferences.setSelected(instrument, false) } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .disabled(preferences.marketInstruments.count <= 2)
                    .help(preferences.marketInstruments.count <= 2 ? "Keep at least two indicators" : "Remove \(instrument.displayName)")
                }
            }
            HStack {
                Button("Add Indicator", systemImage: "plus") { showingIndicatorPicker = true }
                    .disabled(preferences.marketInstruments.count >= 6)
                Spacer()
                Text("\(preferences.marketInstruments.count)/6 selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickOpenSection: some View {
        Section("Quick Open") {
            if quickOpenStore.applications.isEmpty {
                Text("Choose up to six applications to show in the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ReorderableSettingsList(items: quickOpenStore.applications, onMove: quickOpenStore.moveApplications) { application in
                    HStack(spacing: 10) {
                        Text(application.name).lineLimit(1)

                        Spacer(minLength: 8)

                        Button { quickOpenStore.removeApplication(id: application.id) } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(application.name)")
                    }
                }
            }

            HStack {
                Button("Add Application", systemImage: "plus") { selectQuickOpenApplication() }
                    .disabled(quickOpenStore.applications.count >= QuickOpenStore.maximumApplicationCount)
                Spacer()
                Text("\(quickOpenStore.applications.count)/\(QuickOpenStore.maximumApplicationCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let quickOpenError {
                Text(quickOpenError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func selectQuickOpenApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.message = "Select a macOS application to add to Quick Open."
        panel.prompt = "Add Application"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.resolvesAliases = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let applicationURL = panel.url else { return }
        do {
            try quickOpenStore.addApplication(at: applicationURL)
            quickOpenError = nil
        } catch {
            quickOpenError = error.localizedDescription
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
            dataChangeTask = nil
            NotificationCenter.default.post(name: .deskBoardDataSettingsChanged, object: nil)
        }
    }
}

/// A native macOS list owns the drag session, insertion marker, and cancellation.
struct ReorderableSettingsList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let onMove: (IndexSet, Int) -> Void
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        if !items.isEmpty {
            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        row(item)
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .help("Drag to reorder")
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .listRowSeparator(.hidden)
                    .accessibilityAction(named: Text("Move Up")) {
                        guard index > 0 else { return }
                        onMove(IndexSet(integer: index), index - 1)
                    }
                    .accessibilityAction(named: Text("Move Down")) {
                        guard index + 1 < items.count else { return }
                        onMove(IndexSet(integer: index), index + 2)
                    }
                }
                .onMove(perform: onMove)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 32)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(items.count) * 32 + 8)
        }
    }
}

private struct MarketInstrumentPicker: View {
    @ObservedObject var preferences: DashboardPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matchingInstruments: [MarketInstrument] {
        MarketInstrument.allCases.filter { instrument in
            !preferences.marketInstruments.contains(instrument) && (search.isEmpty
                || instrument.displayName.localizedCaseInsensitiveContains(search)
                || instrument.symbol.localizedCaseInsensitiveContains(search)
                || instrument.category.rawValue.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add Indicator").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("Search indicators", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(MarketCategory.allCases) { category in
                        let instruments = matchingInstruments.filter { $0.category == category }
                        if !instruments.isEmpty {
                            Text(category.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            ForEach(instruments) { instrument in
                                Button {
                                    preferences.setSelected(instrument, true)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(instrument.displayName)
                                        Spacer()
                                        Image(systemName: "plus").foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(preferences.marketInstruments.count >= 6)
                            }
                        }
                    }
                    if matchingInstruments.isEmpty {
                        Text("No matching indicators").foregroundStyle(.secondary).padding(.vertical)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 400, height: 420)
    }
}

private struct WorldClockCityPicker: View {
    @ObservedObject var store: WorldClockStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matchingCities: [WorldClockCity] {
        WorldClockStore.availableCities.filter { city in
            !store.cities.contains(city) && (search.isEmpty || city.name.localizedCaseInsensitiveContains(search)
                || city.region.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add City").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("Search city or region", text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(matchingCities) { city in
                        Button {
                            store.add(city.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(city.name)
                                Spacer()
                                Text(city.region).foregroundStyle(.secondary).font(.caption)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(store.cities.count >= WorldClockStore.maximumCities)
                    }
                    if matchingCities.isEmpty {
                        Text("No matching cities").foregroundStyle(.secondary).padding(.vertical)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 380, height: 360)
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
