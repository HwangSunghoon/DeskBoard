import AppKit
import Combine
import EventKit
import SwiftData
import SwiftUI

enum LabStorageCase: String, CaseIterable, Identifiable {
    case healthy = "정상 저장"
    case primary = "DB 저장 실패 · 복구 사본 성공"
    case brief = "모든 저장 실패 · 5분 미만"
    case prolonged = "모든 저장 실패 · 5분 초과"
    case startup = "DB 열기 실패 · 복구 사본 있음"
    case noBackup = "DB 열기 실패 · 복구 사본 없음"
    case pending = "미저장 복구 사본 발견"
    case archive = "복원 전 안전 사본 저장 실패"
    case malformed = "손상된 pending.json"
    var id: String { rawValue }
}

final class LabStorageFaults {
    var open = false
    var save = false
}

@MainActor final class LabStorageSession: ObservableObject {
    let storage: PersistenceController
    let faults: LabStorageFaults
    let directory: URL
    let root: URL
    let scenario: LabStorageCase
    var offset: TimeInterval = 0
    var blocked = false

    init(root: URL, scenario: LabStorageCase) throws {
        self.root = root
        self.scenario = scenario
        directory = root.appendingPathComponent("Recovery")
        let faults = LabStorageFaults()
        self.faults = faults
        // A simulated filesystem blocker is a transient fault, not real corruption.
        // On a fresh process, remove only that test fault by preserving the blocker
        // and restoring this session's own recovery directory.
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), !isDirectory.boolValue,
           FileManager.default.fileExists(atPath: root.appendingPathComponent("PreservedRecovery").path) {
            try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("expired-blocker-\(UUID().uuidString).txt"))
            try FileManager.default.moveItem(at: root.appendingPathComponent("PreservedRecovery"), to: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: root.appendingPathComponent("test.store"))
        let makeDisk = {
            try ModelContainer(for: TodoItem.self, ImportantItem.self, MemoDocument.self, configurations: configuration)
        }
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent("test.store").path) {
            let seed = try makeDisk()
            seed.mainContext.insert(MemoDocument(text: "Current database memo — edit me."))
            seed.mainContext.insert(TodoItem(title: "Test task — not your real data", sortOrder: 0))
            try seed.mainContext.save()
        }
        if [.startup, .pending, .archive].contains(scenario) {
            let memory = try ModelContainer(for: TodoItem.self, ImportantItem.self, MemoDocument.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            memory.mainContext.insert(MemoDocument(text: "RECOVERY COPY — different from current database."))
            try JSONEncoder().encode(RecoverySnapshot(context: memory.mainContext))
                .write(to: directory.appendingPathComponent("pending.json"))
        }
        if scenario == .malformed {
            try Data("{invalid recovery JSON".utf8).write(to: directory.appendingPathComponent("pending.json"))
        }
        faults.open = [.startup, .noBackup].contains(scenario)
        faults.save = [.primary, .brief, .prolonged, .malformed].contains(scenario)
        storage = PersistenceController(directory: directory, makeDiskContainer: {
            if faults.open { throw CocoaError(.fileReadCorruptFile) }
            return try makeDisk()
        }, saveDiskContext: {
            if faults.save { throw CocoaError(.fileWriteOutOfSpace) }
            try $0.save()
        })
        if [.brief, .prolonged, .archive].contains(scenario) { try blockRecovery() }
        if scenario != .archive && scenario != .pending {
            _ = storage.checkpoint()
        }
        if scenario == .prolonged {
            offset = 301
            _ = storage.checkpoint(now: Date().addingTimeInterval(offset))
        }
    }

    func blockRecovery() throws {
        guard !blocked else { return }
        try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("PreservedRecovery"))
        try Data("Error Lab blocker, not user data".utf8).write(to: directory)
        blocked = true
    }

    func heal() throws {
        faults.open = false
        faults.save = false
        if blocked {
            try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("blocker-\(UUID().uuidString).txt"))
            try FileManager.default.moveItem(at: root.appendingPathComponent("PreservedRecovery"), to: directory)
            blocked = false
        }
        offset = 0
        // Do not silently restore pending/temporary copies; require the real UI's confirmation.
        if !storage.isTemporary && !storage.hasPendingRecovery { _ = storage.checkpoint() }
    }

    @discardableResult func checkpoint() -> Bool {
        storage.checkpoint(now: Date().addingTimeInterval(offset))
    }

    func memo() throws -> String {
        try storage.container?.mainContext.fetch(FetchDescriptor<MemoDocument>()).first?.text ?? ""
    }
}

enum LabWeatherMode: String, CaseIterable, Identifiable {
    case success = "정상 응답", offline = "오프라인", timeout = "시간 초과"
    case server = "서버 오류", decoding = "응답 파싱 오류"
    var id: String { rawValue }
}

final class LabWeatherProvider: WeatherProviding, WeatherLocationSearching {
    var mode: LabWeatherMode = .success
    func validate() throws {
        switch mode {
        case .success: break
        case .offline: throw URLError(.notConnectedToInternet)
        case .timeout: throw URLError(.timedOut)
        case .server: throw URLError(.badServerResponse)
        case .decoding: throw URLError(.cannotParseResponse)
        }
    }
    func fetch(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        try validate()
        return WeatherSnapshot(temperature: 20, high: 26, low: 17, precipitationProbability: 10, weatherCode: 0, updatedAt: .now)
    }
    func search(_ query: String) async throws -> [WeatherLocation] {
        try validate()
        return [.seoul, WeatherLocation(name: "Paris", country: "France", admin1: nil, latitude: 48.85, longitude: 2.35)]
    }
}

struct LabResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    let name: String
    let status: String
    let detail: String
    init(_ name: String, _ status: String, _ detail: String) {
        id = UUID(); date = .now; self.name = name; self.status = status; self.detail = detail
    }
}

@MainActor final class LabController: ObservableObject {
    static let shared = LabController()
    let root: URL
    let weatherProvider = LabWeatherProvider()
    let locations = WeatherLocationStore()
    let dashboard: DashboardModel
    let calendar = CalendarService()
    let missingApps: QuickOpenStore
    @Published var session: LabStorageSession?
    @Published var weather: WeatherService
    @Published var weatherMode = LabWeatherMode.success
    @Published var results: [LabResult] = []
    @Published var busy = false
    @Published var notice = ""
    @Published var now = Date()
    private var ticker: AnyCancellable?
    private var preview: NSWindow?
    private var desktop: DesktopWindowController?

    private init() {
        // Hard fail before touching shared production services outside this sandbox.
        precondition(Bundle.main.bundleIdentifier == "com.local.DeskBoard.ErrorLab")
        precondition(NSHomeDirectory().contains("/Containers/com.local.DeskBoard.ErrorLab/Data"), "The lab MUST run sandboxed")
        root = URL.applicationSupportDirectory.appendingPathComponent("DeskBoardErrorLab", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let initialWeather = WeatherService(provider: weatherProvider, locations: locations)
        weather = initialWeather
        dashboard = DashboardModel(weather: initialWeather)
        let missingDefaults = UserDefaults(suiteName: "com.local.DeskBoard.ErrorLab.missing-app")!
        let missing = QuickOpenApplication(id: UUID(), name: "Missing Test App", bundleIdentifier: "com.deskboard.errorlab.nonexistent.\(UUID().uuidString)", path: root.appendingPathComponent("DoesNotExist.app").path, bookmarkData: Data())
        missingDefaults.set(try! JSONEncoder().encode([missing]), forKey: "quickOpenApplications.v1")
        missingApps = QuickOpenStore(defaults: missingDefaults)
        if let data = try? Data(contentsOf: root.appendingPathComponent("results.json")),
           let previous = try? JSONDecoder().decode([LabResult].self, from: data) { results = previous }
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in
            guard let self else { return }
            self.now = date
            self.dashboard.setLabDate(date)
            self.dashboard.focusTimer.update(now: date)
            if !self.busy {
                _ = self.session?.checkpoint()
                _ = PersistenceController.shared.checkpoint()
            }
        }
        if let token = UserDefaults.standard.string(forKey: "lab.lastSession"), UUID(uuidString: token) != nil {
            do {
                session = try LabStorageSession(root: root.appendingPathComponent("Sessions/\(token)"), scenario: .healthy)
                notice = "이전 세션을 다시 열었습니다. 실패 주입은 해제되어 있고 미저장 복구 사본은 실제 복구 안내로 표시됩니다."
            } catch { record("세션 재실행", "ERROR", error.localizedDescription); choose(.healthy) }
        } else { choose(.healthy) }
    }

    func perform(_ name: String, _ body: () throws -> Void) {
        do { try body() } catch { record(name, "ERROR", error.localizedDescription) }
    }

    func record(_ name: String, _ status: String, _ detail: String) {
        results.append(LabResult(name, status, detail))
        notice = "\(status) · \(name): \(detail)"
        do { try JSONEncoder().encode(results).write(to: root.appendingPathComponent("results.json"), options: .atomic) }
        catch { notice += " · 결과 기록 저장 실패: \(error.localizedDescription)" }
    }

    func choose(_ scenario: LabStorageCase) {
        perform("시나리오 준비") {
            if let current = session, let context = current.storage.container?.mainContext {
                try JSONEncoder().encode(RecoverySnapshot(context: context))
                    .write(to: current.root.appendingPathComponent("editor-before-switch-\(UUID().uuidString).json"), options: .atomic)
            }
            let token = UUID().uuidString
            let path = root.appendingPathComponent("Sessions/\(token)")
            session = try LabStorageSession(root: path, scenario: scenario)
            UserDefaults.standard.set(token, forKey: "lab.lastSession")
            notice = "준비됨 · \(scenario.rawValue). 이전 테스트 사본은 보존됩니다."
        }
    }

    func configureWeather(age: TimeInterval?) async {
        struct Cache: Encodable { let locationID: String; let snapshot: WeatherSnapshot }
        weatherProvider.mode = weatherMode
        if let age {
            let value = WeatherSnapshot(temperature: 20, high: 26, low: 17, precipitationProbability: 10, weatherCode: 0, updatedAt: Date().addingTimeInterval(-age))
            UserDefaults.standard.set(try? JSONEncoder().encode(Cache(locationID: locations.selected.id, snapshot: value)), forKey: "weather.cache.v2")
        } else { UserDefaults.standard.removeObject(forKey: "weather.cache.v2") }
        weather = WeatherService(provider: weatherProvider, locations: locations)
        await weather.refresh()
        notice = "가짜 응답 적용됨: \(weatherMode.rawValue). 실제 네트워크는 변경하지 않았습니다."
    }

    func setCalendar(_ status: EKAuthorizationStatus, count: Int = 0) {
        calendar.setLabFixture(status: status, events: (0..<count).map {
            CalendarEventItem(id: "fixture-\($0)", title: "Test event \($0 + 1) — a long calendar title",
                startDate: Calendar.current.date(bySettingHour: 10 + $0, minute: 0, second: 0, of: .now)!,
                isAllDay: false, location: "서울역")
        })
    }

    func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform("앱 추가") { try QuickOpenStore.shared.addApplication(at: url) }
    }

    func seedLayout() {
        perform("레이아웃 샘플 추가") {
            guard let context = PersistenceController.shared.container?.mainContext else { return }
            let count = try context.fetchCount(FetchDescriptor<TodoItem>())
            for index in 0..<12 {
                context.insert(TodoItem(title: "Test \(count + index + 1) — 긴 Todo 행을 입력하고 수정·추가·스크롤을 확인하세요.", sortOrder: count + index))
                context.insert(ImportantItem(title: "Test event \(count + index + 1)", date: .now, sortOrder: count + index))
            }
            if try context.fetchCount(FetchDescriptor<MemoDocument>()) == 0 { context.insert(MemoDocument(text: "Test memo — edit and relaunch to verify persistence.")) }
            _ = PersistenceController.shared.checkpoint()
            for section in DashboardSection.allCases { DashboardPreferences.shared.setVisible(section, true) }
            setCalendar(.fullAccess, count: 6)
            notice = "테스트 앱의 Sidebar 데이터에 샘플 12개를 추가했습니다."
        }
    }

    func showPreview() {
        guard let container = PersistenceController.shared.container else { return }
        let view = NSHostingView(rootView: SidebarView(calendar: calendar).environmentObject(dashboard).modelContainer(container))
        view.sizingOptions = []
        if preview == nil {
            preview = NSWindow(contentRect: NSRect(x: 150, y: 120, width: 380, height: 760),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            preview?.isReleasedWhenClosed = false
            preview?.title = "ERROR LAB — Resizable Sidebar"
        }
        preview?.contentView = view
        preview?.makeKeyAndOrderFront(nil)
    }

    func showDesktop() {
        // Explicit opt-in: this production controller starts real weather/system services.
        if desktop == nil { desktop = DesktopWindowController(modelContainer: PersistenceController.shared.container) }
        desktop?.showSidebar()
    }

    func hideDesktop() { desktop?.stop(); desktop?.close(); desktop = nil }

    func exportResults() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DeskBoard-ErrorLab-Results.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        perform("결과 내보내기") { try JSONEncoder().encode(results).write(to: url, options: .atomic) }
    }

    func testQuit() {
        guard let storage = session?.storage, !storage.checkpoint() else {
            notice = "저장 가능한 상태입니다. ‘모든 저장 실패’ 시나리오를 먼저 선택하세요."; return
        }
        storage.requestSaveHelp()
        let response = StorageQuitConfirmation.makeAlert().runModal()
        record("종료 확인창 연습", "OBSERVED", response == .alertFirstButtonReturn ? "Keep Open 선택; 이 연습은 앱을 종료하지 않음" : "Quit Without Saving 선택; 이 연습은 앱을 종료하지 않음")
    }

    func shouldQuit() -> NSApplication.TerminateReply {
        let scenarioSafe = session?.storage.checkpoint() ?? true
        let sidebarSafe = PersistenceController.shared.checkpoint()
        guard !scenarioSafe || !sidebarSafe else { return .terminateNow }
        if !scenarioSafe { session?.storage.requestSaveHelp() }
        if !sidebarSafe { PersistenceController.shared.requestSaveHelp() }
        return StorageQuitConfirmation.makeAlert().runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
}
