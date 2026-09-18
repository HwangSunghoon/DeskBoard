import AppKit
import SwiftData
import SwiftUI

struct LabView: View {
    @ObservedObject var lab: LabController
    @ObservedObject private var quick = QuickOpenStore.shared
    @State private var search = false
    @State private var note = ""
    @State private var selection: Int

    init(lab: LabController, tab: Int = 0) {
        self.lab = lab
        _selection = State(initialValue: tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DeskBoard Error Lab").font(.title2.bold())
                    Text("별도 샌드박스 · 실제 DeskBoard 데이터와 분리 · 자동 재현 + 수동 검사")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(lab.busy ? "검사 중…" : "자동 검사 실행") { Task { await lab.runAutomatic() } }
                    .disabled(lab.busy)
                Button("결과 내보내기", action: lab.exportResults)
                SettingsLink { Image(systemName: "gearshape") }.help("테스트 앱 전용 Settings")
            }
            Text("이 앱은 알려진 오류 경로의 검사 도구입니다. 모든 미래 오류나 App Store 배포 적합성을 보증하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                let titles = ["Storage", "Weather", "Calendar", "Quick Open", "Layout / Clock", "Checklist / Results"]
                ForEach(titles.indices, id: \.self) { index in
                    Button(titles[index]) { selection = index }
                        .buttonStyle(.bordered)
                        .tint(selection == index ? .accentColor : .secondary)
                }
                Spacer(minLength: 0)
            }
            .disabled(lab.busy)
            Group {
                switch selection {
                case 1: weather
                case 2: calendar
                case 3: quickOpen
                case 4: layout
                case 5: checklist
                default: storage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(lab.busy)
            Text(lab.notice).font(.caption).textSelection(.enabled).lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        }
        .padding(20).frame(minWidth: 920, minHeight: 660)
    }

    private var storage: some View {
        HStack(alignment: .top, spacing: 24) {
            ScrollView {
              VStack(alignment: .leading, spacing: 12) {
                Text("오류 주입").font(.headline)
                ForEach(LabStorageCase.allCases) { scenario in
                    Button(scenario.rawValue) { lab.choose(scenario) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                Button("오류 해제 · 저장 재시도") {
                    lab.perform("오류 해제") { try lab.session?.heal(); lab.notice = "실패 조건 해제됨. 복구 사본 복원은 오른쪽 안내에서 직접 승인하세요." }
                }
                Button("종료 확인창 연습 (종료하지 않음)", action: lab.testQuit)
                Text("실제 종료 검사는 ⌘Q. 짧은 실패를 선택해도 5분 이상 두면 실제 경과시간에 따라 안내가 표시됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("테스트 입력은 시나리오 변경 전 보존. 복원 전 아카이브·내보내기 파일도 아래 폴더에서 확인할 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("테스트 폴더 열기") { if let root = lab.session?.root { NSWorkspace.shared.open(root) } }
              }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 330)
            Divider()
            if let session = lab.session {
                LabStoragePanel(session: session).id(ObjectIdentifier(session))
            }
        }.padding(20)
    }

    private var weather: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("실제 네트워크를 끊지 않고 provider 실패를 주입합니다. 서버/파싱 오류는 해당 오류를 던지는 시뮬레이션입니다.")
            Picker("응답", selection: $lab.weatherMode) {
                ForEach(LabWeatherMode.allCases) { Text($0.rawValue).tag($0) }
            }.frame(width: 360)
            HStack {
                Button("최근 캐시 + 요청") { Task { await lab.configureWeather(age: 60) } }
                Button("2시간 초과 캐시 + 요청") { Task { await lab.configureWeather(age: 7201) } }
                Button("캐시 없음 + 요청") { Task { await lab.configureWeather(age: nil) } }
            }
            DateWeatherView(model: lab.dashboard, weather: lab.weather)
                .frame(width: 340).padding(18).background(.regularMaterial).cornerRadius(12)
            Text("오류 + 최근 캐시: 기존 표시 유지 / 오래된 캐시: 작은 점 / 캐시 없음: unavailable.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("도시 검색 UI 열기") { lab.weatherProvider.mode = lab.weatherMode; search = true }
            Text("오프라인을 선택한 뒤 검색 창의 Try Again·Cancel을 검사하세요. 성공 모드는 테스트 도시만 반환합니다.")
                .font(.caption)
            Text("현재 테스트 도시: \(lab.locations.selected.displayName)").font(.caption)
            Spacer()
        }.padding(20)
        .sheet(isPresented: $search) { WeatherLocationPicker(store: lab.locations, initialQuery: "Seoul", provider: lab.weatherProvider) }
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("권한 시뮬레이션 — 시스템 권한을 바꾸지 않음").font(.headline)
            HStack {
                Button("미결정") { lab.setCalendar(.notDetermined) }
                Button("거절") { lab.setCalendar(.denied) }
                Button("제한됨") { lab.setCalendar(.restricted) }
                Button("일정 없음") { lab.setCalendar(.fullAccess) }
                Button("일정 2개") { lab.setCalendar(.fullAccess, count: 2) }
                Button("일정 6개") { lab.setCalendar(.fullAccess, count: 6) }
            }
            CalendarSectionView(service: lab.calendar)
                .frame(width: 340, height: CalendarSectionMetrics.height(rowCount: 4, compact: false))
                .padding(18).background(.regularMaterial).cornerRadius(12)
            Divider()
            Text("실제 OS 권한 — 직접 선택했을 때만 읽기 요청").font(.headline)
            Text("DeskBoard Error Lab의 권한만 변경하세요. 실제 캘린더 일정은 화면에 보일 수 있지만 결과 파일에는 복사하지 않습니다.")
                .font(.caption)
            HStack {
                Button("실제 Calendar 권한 요청") { Task { await lab.calendar.requestAccess() } }
                Button("실제 상태 새로고침") { Task { await lab.calendar.refresh() } }
            }
            Text("거절/허용/해제는 macOS 시스템 설정 → 개인정보 보호 및 보안 → 캘린더에서 Error Lab만 변경.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(20)
    }

    private var quickOpen: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("실제 로컬 앱·bookmark·NSWorkspace 검사").font(.headline)
            Button("Add Application…", action: lab.addApp)
            QuickOpenView().frame(width: 340, height: 48).padding(12).background(.regularMaterial).cornerRadius(12)
            ForEach(quick.applications) { app in
                HStack {
                    Text(app.name)
                    Spacer()
                    Button("선택 해제") { quick.removeApplication(id: app.id) }
                }
            }
            Text("설정에서 순서 변경 후 재실행하세요. 선택 해제는 앱 파일을 삭제하지 않습니다.").font(.caption)
            Divider()
            Text("누락 앱 — 실제 설치 앱을 삭제하지 않는 검사").font(.headline)
            QuickOpenView(store: lab.missingApps).frame(width: 340, height: 48)
            Text("위의 흐린 아이콘을 누르면 실제 Quick Open 오류 팝오버가 표시되어야 합니다.").font(.caption)
            Spacer()
        }.padding(20)
    }

    private var layout: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("레이아웃 · 모니터 · 타이머 · 재실행").font(.headline)
            HStack {
                Button("샘플 12개 추가", action: lab.seedLayout)
                Button("가변 Sidebar 창 열기", action: lab.showPreview)
            }
            Text("가변 창은 실제 SidebarView를 사용합니다. Settings에서 섹션·순서·World Clock·앱을 설정하세요. 테스트 데이터는 이 앱 전용으로 재실행 후에도 유지됩니다.")
                .font(.caption)
            HStack {
                Button("실제 데스크톱 패널 열기", action: lab.showDesktop)
                Button("패널 닫기", action: lab.hideDesktop)
            }
            Text("데스크톱 패널은 실제 창 배치 코드를 사용하며 날씨 네트워크 요청·시스템 측정을 시작합니다. 권한이 이미 허용되어 있으면 실제 일정도 읽습니다. 테스트 앱 전용 Settings에서 표시 화면·좌우 위치를 변경하세요.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            FocusTimerView(timer: lab.dashboard.focusTimer, now: lab.now).frame(width: 340, height: 54)
            Text("Focus를 시작하고 실제 잠자기/복귀를 확인하세요. 자동 검사는 가상 시각으로 55:01 문제와 시간 경과를 확인합니다.").font(.caption)
            Divider()
            Text("현재 화면: \(NSScreen.screens.map { $0.localizedName }.joined(separator: ", "))").font(.caption)
            Text("모든 UI/OS 검사가 자동으로 PASS가 되지는 않습니다. Checklist에서 결과를 직접 기록하세요.").font(.caption)
            Spacer()
        }.padding(20)
    }

    private var checklist: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextField("결과 메모 (기기, OS, 관찰 내용)", text: $note)
                ForEach(LabManualCase.all) { item in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title).font(.headline)
                            Text(item.steps).font(.callout)
                            Text("정상 기준: \(item.expected)").font(.caption).foregroundStyle(.secondary)
                            let latest = lab.results.last { $0.name == "MANUAL · \(item.title)" }
                            HStack {
                                Text(latest?.status ?? "NOT TESTED").font(.caption.bold())
                                Spacer()
                                Button("통과") { lab.record("MANUAL · \(item.title)", "MANUAL PASS", note) }
                                Button("실패") { lab.record("MANUAL · \(item.title)", "MANUAL FAIL", note) }
                                Button("보류") { lab.record("MANUAL · \(item.title)", "NOT TESTED", note) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
                Text("기록 (최근 150개 표시 / 내보내기는 전체)").font(.headline)
                ForEach(Array(lab.results.suffix(150).reversed())) { result in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(result.status) · \(result.name)").font(.caption.bold())
                        Text("\(result.date.formatted()) · \(result.detail)").font(.caption).foregroundStyle(.secondary)
                    }.textSelection(.enabled)
                }
            }.padding(20)
        }
    }
}

private struct LabStoragePanel: View {
    let session: LabStorageSession
    @ObservedObject private var storage: PersistenceController
    init(session: LabStorageSession) { self.session = session; storage = session.storage }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(session.scenario.rawValue).font(.headline)
            Text("아래는 실제 StorageStatusView. 안내가 없는 상태는 정상일 수 있습니다.").font(.caption)
            StorageStatusView(storage: storage).frame(height: 24)
            Divider()
            if let container = storage.container {
                LabEditor().modelContainer(container).id(ObjectIdentifier(container))
            }
            Text("Temporary: \(storage.isTemporary ? "yes" : "no") / Pending recovery: \(storage.hasPendingRecovery ? "yes" : "no") / Save attention: \(storage.needsSaveAttention ? "yes" : "no")")
                .font(.caption).foregroundStyle(.secondary)
            Text(session.root.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LabEditor: View {
    @State private var addTodo = false
    @State private var addImportant = false
    @State private var showMemo = true
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("Edit Memo") { showMemo = true }
                Button("Todo / Important") { showMemo = false }
            }
            if showMemo {
                MemoSectionView(availableWidth: 420, onPreferredHeightChange: { _ in }).padding(12)
            } else {
                VStack {
                    TodoSectionView(isAdding: $addTodo, availableHeight: 170).frame(height: 170)
                    Divider()
                    ImportantSectionView(isAdding: $addImportant).frame(height: 170)
                    Spacer(minLength: 0)
                }.padding(12)
            }
        }
    }
}
