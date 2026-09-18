import AppKit
import SwiftData

@MainActor extension LabController {
    func runAutomatic() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        record("RUN", "START", "\(ProcessInfo.processInfo.operatingSystemVersionString); bundle \(Bundle.main.bundleIdentifier ?? "unknown"); signed sandbox lab; manual tests remain independent")
        for scenario in LabStorageCase.allCases {
            do {
                let sample = try LabStorageSession(root: root.appendingPathComponent("Automatic/\(UUID().uuidString)"), scenario: scenario)
                let storage = sample.storage
                let before = try sample.memo()
                var passed = false
                switch scenario {
                case .healthy:
                    let reopened = try ModelContainer(for: TodoItem.self, ImportantItem.self, MemoDocument.self,
                        configurations: ModelConfiguration(url: sample.root.appendingPathComponent("test.store")))
                    let reopenedMemo = try reopened.mainContext.fetch(FetchDescriptor<MemoDocument>()).first?.text
                    passed = sample.checkpoint() && !storage.needsSaveAttention && reopenedMemo == before
                case .primary:
                    passed = sample.checkpoint() && !storage.needsSaveAttention
                        && FileManager.default.fileExists(atPath: sample.directory.appendingPathComponent("pending.json").path)
                case .brief:
                    sample.offset = 299
                    passed = !sample.checkpoint() && !storage.needsSaveAttention
                case .prolonged:
                    passed = !sample.checkpoint() && storage.needsSaveAttention
                    try sample.heal()
                    passed = passed && sample.checkpoint() && !storage.needsSaveAttention
                case .startup:
                    passed = storage.isTemporary && before.contains("RECOVERY COPY")
                    try sample.heal()
                    storage.retry()
                    let restored = try sample.memo()
                    passed = passed && !storage.isTemporary && restored == before
                case .noBackup:
                    passed = storage.isTemporary && storage.container != nil && storage.recoveryMessage != nil
                case .pending:
                    passed = storage.hasPendingRecovery && before.contains("Current database")
                    storage.retry()
                    let archives = try FileManager.default.contentsOfDirectory(atPath: sample.directory.path)
                    let restored = try sample.memo()
                    passed = passed && !storage.hasPendingRecovery && restored.contains("RECOVERY COPY")
                        && archives.contains { $0.hasPrefix("before-restore-") }
                case .archive:
                    storage.retry()
                    let unchanged = try sample.memo()
                    passed = storage.hasPendingRecovery && !storage.isTemporary && unchanged == before
                        && storage.recoveryMessage?.contains("Recovery was not restored") == true
                case .malformed:
                    let files = try FileManager.default.contentsOfDirectory(atPath: sample.directory.path)
                    passed = files.contains { $0.hasPrefix("unreadable-recovery-") } && !storage.needsSaveAttention
                }
                record("AUTO · \(scenario.rawValue)", passed ? "PASS" : "FAIL", "실제 PersistenceController에 격리된 실패 주입; 버튼 조작 검증과 별개")
                // Export uses production serialization; verify a writable destination and blocked destination.
                let bytes = try storage.exportData()
                _ = try JSONDecoder().decode(RecoverySnapshot.self, from: bytes)
                try bytes.write(to: sample.root.appendingPathComponent("export.json"), options: .atomic)
                let blocker = sample.root.appendingPathComponent("export-blocker")
                try Data("blocker".utf8).write(to: blocker)
                do {
                    try bytes.write(to: blocker.appendingPathComponent("copy.json"))
                    record("AUTO · export failure", "FAIL", "차단된 경로에 쓰기가 예상과 달리 성공함")
                } catch { record("AUTO · export · \(scenario.rawValue)", "PASS", "JSON 내보내기/재해석 성공; 잘못된 대상 쓰기는 실패. NSSavePanel 조작은 수동 검사") }
            } catch { record("AUTO · \(scenario.rawValue)", "FAIL", error.localizedDescription) }
        }
        for mode in LabWeatherMode.allCases {
            for age: TimeInterval? in [nil, 60, 7201] {
                weatherMode = mode
                await configureWeather(age: age)
                let retained = mode == .success || age != nil
                let passed = (weather.snapshot != nil) == retained
                    && weather.isUnavailable == !retained
                    && weather.isDelayed() == (mode != .success && (age ?? 0) > 7200)
                record("AUTO · Weather \(mode.rawValue) / cache \(age.map { String(Int($0)) } ?? "none")", passed ? "PASS" : "FAIL", "provider 오류 경로 주입; 실제 HTTP 전송/JSON 파서 검증은 기존 회귀 테스트 범위")
            }
        }
        let searchProvider = LabWeatherProvider()
        searchProvider.mode = .offline
        let search = WeatherLocationSearchModel(provider: searchProvider)
        await search.search("Seoul")
        record("AUTO · 도시 검색 실패", search.errorMessage != nil && search.results.isEmpty ? "PASS" : "FAIL", "검색 오류 상태와 빈 결과 확인; 기존 선택 도시는 변경하지 않음")
        let missing = missingApps.applications.first!
        record("AUTO · 앱 경로 유실", missingApps.urlForOpening(missing) == nil ? "PASS" : "FAIL", "실제 앱 삭제 없이 존재하지 않는 bundle/path 사용; 팝오버 클릭은 수동")
        let timerDefaults = UserDefaults(suiteName: "com.local.DeskBoard.ErrorLab.auto-timer")!
        let timer = FocusTimerStore(defaults: timerDefaults)
        timer.reset()
        let t = Date()
        timer.toggle(focusMinutes: 55, breakMinutes: 5, now: t)
        let initial = timer.remainingSeconds(at: t.addingTimeInterval(-0.2), focusMinutes: 55, breakMinutes: 5)
        let afterSleep = timer.remainingSeconds(at: t.addingTimeInterval(121), focusMinutes: 55, breakMinutes: 5)
        record("AUTO · 타이머 stale tick / 절전 경과시간", initial == 3300 && afterSleep == 3179 ? "PASS" : "FAIL", "가상 시각으로 검증; 실제 Mac sleep/wake는 수동 검사")
        timer.reset()
        weatherMode = .success
        await configureWeather(age: nil)
        notice = "자동 검사 완료. Results에서 FAIL을 확인하고 수동 검사 항목도 진행하세요."
    }
}

struct LabManualCase: Identifiable {
    let id: String
    let title: String
    let steps: String
    let expected: String
    static let all: [Self] = [
        .init(id: "save-ui", title: "저장 안내 · 편집 · 복원 · 내보내기", steps: "Storage에서 모든 저장 실패(5분 초과) → Memo 편집 → Save issue 클릭 → Export copy. ‘미저장 복구 사본 발견’에서는 복원 취소와 승인을 각각 검사.", expected: "입력 유지, JSON 파일 내용 일치, 취소 시 원본 유지, 승인 전 안전 사본 보존. 오류 해제 후 안내가 사라짐."),
        .init(id: "quit-cancel", title: "실제 종료 취소", steps: "모든 저장 실패 선택 → 내용을 바꾼 뒤 ⌘Q → Keep Open. ‘확인창 연습’은 실제 종료 검사가 아님.", expected: "앱이 계속 열려 있고 방금 입력한 내용이 남음."),
        .init(id: "quit-discard", title: "저장 없이 실제 종료", steps: "테스트 데이터만 있는지 확인 → 저장 실패 → ⌘Q → Quit Without Saving → 같은 테스트 앱 재실행.", expected: "선택 후에만 종료. 저장되지 않은 메모는 사라질 수 있음. 재실행 후 이 항목 결과를 기록."),
        .init(id: "weather-ui", title: "날씨·도시 검색 오류 UI", steps: "Weather에서 오프라인/시간 초과/서버/파싱 오류와 캐시 나이를 조합. 도시 검색 창에서 재시도·취소.", expected: "캐시는 유지되고 2시간 초과만 작은 점. 캐시 없으면 unavailable. 검색 오류가 기존 도시 선택을 바꾸지 않음."),
        .init(id: "calendar", title: "실제 Calendar 권한", steps: "Calendar의 실제 권한 요청 클릭. 이 테스트 앱만 거절→허용→해제하고 ‘실제 상태 새로고침’. 실제 캘린더 읽기에 동의할 때만 수행.", expected: "권한 상태에 맞게 안내/일정 전환, 충돌 없음. 실제 DeskBoard 권한은 바뀌지 않음."),
        .init(id: "quick-open", title: "앱 실행·활성화·권한 유지", steps: "Quick Open에서 로컬 앱 추가 → 아이콘 클릭 → 앱을 켠 상태에서 다시 클릭 → Error Lab 종료/재실행 후 다시 클릭.", expected: "앱이 열리거나 전면 활성화. 선택 앱·순서·접근 권한 유지."),
        .init(id: "missing-app", title: "앱 누락·이동", steps: "Missing Test App 아이콘 클릭. 이동 검사는 직접 만든 테스트용 .app만 선택하고 이동한 후 재시도. 기존 설치 앱은 삭제하지 말 것.", expected: "누락 앱만 흐리게 표시하고 클릭 시 안내. 가능한 경우 bundle/bookmark로 이동 경로 복구."),
        .init(id: "layout", title: "짧은 화면 · 긴 내용 · 추가 입력", steps: "Layout 샘플 추가 → 가변 Sidebar 창 열기 → 폭 320~400, 높이 560~900 조절. Todo/Important +, Enter, 수정, 마지막 행 스크롤. Settings에서 섹션 숨김·순서 변경.", expected: "제목·입력칸 접근 가능, 마지막 내용까지 스크롤, Memo placeholder가 포커스 해제 시 복귀."),
        .init(id: "displays", title: "듀얼 모니터 · 클램셸", steps: "실제 데스크톱 패널 열기(외부 날씨 요청 시작). Settings에서 테스트 앱의 표시 위치 변경 → 모니터 분리/재연결 → 클램셸 전환.", expected: "실제 DesktopWindowController 창이 보이는 화면 안으로 배치되고 잘림 없음. 앱 창이 아니라 테스트 패널로 검사."),
        .init(id: "sleep", title: "실제 잠자기 · 날짜 변경", steps: "Focus 시작 → 2분 이상 잠자기 → 복귀. 자정/시간대 변경은 시스템 시계를 강제로 바꾸지 말고 실제 환경 또는 별도 테스트 Mac에서 확인.", expected: "실제 경과시간과 카운트다운 일치, 복귀·날짜 전환 후 시계·일정 갱신. 재부팅 후 타이머도 확인."),
        .init(id: "update", title: "재실행 · 업데이트 데이터 유지", steps: "Layout Sidebar에 고유한 메모·항목을 입력하고 앱·도시·섹션 설정 변경 → 정상 종료 → 같은 앱 재실행. 업데이트는 같은 Lab Bundle ID/서명으로 빌드한 다음 버전으로 재검사.", expected: "데이터·선택·순서 유지. 이 테스트는 실제 배포판의 이전 버전 migration 검증을 대신하지 않음."),
        .init(id: "release", title: "최종 배포 서명 검사", steps: "별도 테스트 Mac/계정에서 실제 배포용 서명·샌드박스 빌드로 Calendar/Quick Open/업데이트 검사.", expected: "Error Lab 통과와 별개로 배포 서명 상태에서도 정상. App Store 승인/공증 여부는 이 앱으로 판정하지 않음.")
    ]
}
