# DeskBoard Error Lab

대화형 오류 검사 앱. 실제 DeskBoard와 **Bundle ID, sandbox container, DB, 설정, Calendar 권한**이 다릅니다.
실행 시 `com.local.DeskBoard.ErrorLab` 샌드박스인지 검사하고, 아니면 데이터에 접근하기 전에 중단합니다.
현재 알려진 장애 경로를 검사하는 도구이지 모든 미래 오류·App Store 승인·배포 적합성의 보증은 아닙니다.

## 빌드 및 실행

```sh
# 프로젝트 루트, macOS 14+ 및 full Xcode 필요
DESKBOARD_LAB_SIGN_IDENTITY='Apple Development: YOUR NAME (TEAM)' bash Tests/build-error-lab.sh
```

출력된 `DeskBoard Error Lab.app`을 Finder에서 열거나 안내된 `open` 명령으로 실행하세요.
인증서를 지정하지 않으면 ad-hoc 서명합니다. 실제 Calendar/TCC, 앱 bookmark와 업데이트 권한 검사는
**동일한 개발 인증서로 계속 서명**해서 진행하세요. 개발 서명 통과는 최종 배포 서명 검사를 대신하지 않습니다.

앱 빌드는 `build/ErrorLab.<고유값>/`에 생성되며 기존 DeskBoard를 교체하거나 `/Applications`에 설치하지 않습니다.
`Tests/ErrorLab`의 코드는 배포 target에 포함되지 않습니다. fixture hook은 `DESKBOARD_ERROR_LAB` 컴파일 조건에서만 존재합니다.

## 사용 순서

1. **자동 검사 실행**: 저장 9종, 내보내기 성공/실패, 날씨 응답 5종 × 캐시 3종, 도시 검색 실패,
   누락 앱, 타이머 경과시간을 검사합니다. 36개 결과가 기록됩니다. 기존 9개 회귀 suite는
   `bash Tests/run-regression-checks.sh`로 별도 실행하세요.
2. **Storage**: 실패 조건 선택 → 실제 Memo/Todo/Important 편집 → 실제 Save issue/Recovery copy 팝오버 클릭.
   Export copy 및 복원 취소/승인을 검사하세요. 오류 해제는 복원을 자동 승인하지 않습니다.
3. 종료는 **⌘Q**로 실제 검사합니다. Keep Open이면 계속 편집할 수 있어야 합니다.
   ‘확인창 연습’ 버튼은 동일한 NSAlert를 보여주지만 앱을 종료하지 않습니다.
4. **Weather / Calendar / Quick Open**에서 오류 UI와 실제 권한·앱 실행을 확인합니다.
   실제 Calendar 접근과 앱 실행은 해당 버튼을 직접 누를 때만 요청합니다.
5. **Layout / Clock**에서 샘플을 추가하고 실제 SidebarView 창을 조절합니다.
   ‘실제 데스크톱 패널’은 실제 창 배치 코드를 실행하므로 멀티 모니터·클램셸 테스트에 사용합니다.
6. **Checklist / Results**의 절차대로 검사하고 통과/실패/보류 및 메모를 기록한 후 JSON을 내보내세요.
   수동 항목은 자동 검사 성공만으로 통과 처리되지 않습니다.

## 격리와 보관

- 기본적으로 가짜 provider를 사용합니다. 타임아웃/서버/파싱 오류는 즉시 해당 오류를 던집니다.
  실제 HTTP 지연이나 원격 서버의 파서를 고장 내는 테스트는 아닙니다.
- ‘실제 데스크톱 패널 열기’는 명시적인 실사용 모드입니다. 실제 날씨 요청·시스템 측정을 시작하며,
  Error Lab에 권한이 있으면 캘린더를 읽습니다. 패널 닫기로 중지할 수 있습니다.
- Calendar fixture는 실제 이벤트를 쓰거나 삭제하지 않습니다. 실제 일정 내용은 결과 파일에 기록하지 않습니다.
- 저장 실패는 throw 또는 **테스트 폴더 위치의 작은 blocker 파일**로 재현합니다. 디스크를 채우거나 OS 권한을 변경하지 않습니다.
- 세션별 SQLite와 복구 사본은 앱 샌드박스의 `Application Support/DeskBoardErrorLab/Sessions` 아래에 보관됩니다.
  시나리오 변경 전 현재 편집 내용도 별도 JSON으로 보존합니다. 오류 해제/재실행은 blocker를 보관하고 테스트 디렉터리를 복구합니다.
- 마지막 Storage 세션은 재실행 시 실패 주입을 해제한 상태로 다시 엽니다. 미저장 복구 사본이 있으면 실제 복구 안내로 표시됩니다.
  명시적으로 ‘저장 없이 종료’를 고르면 메모리에만 있던 수정은 손실될 수 있습니다. 테스트 데이터만 입력하세요.
- Layout Sidebar는 같은 테스트 앱의 별도 기본 DB를 사용하며 Storage 오류 주입의 영향을 받지 않습니다.
- 결과는 `Application Support/DeskBoardErrorLab/results.json`에 누적되고, 자동 검사 fixture도 보관합니다.
  자동 검사를 반복하면 테스트 사본이 늘어납니다. 보관 자료는 앱 삭제만으로 자동 제거되지 않습니다.
  정리하려면 앱을 종료하고 **Error Lab 컨테이너만** Finder 휴지통으로 이동하세요. 실제 `com.local.DeskBoard`는 건드리지 마세요.

## 자동 실행 / 자체 렌더링

```sh
open '/absolute/path/DeskBoard Error Lab.app' --args --self-test --snapshots
```

자동 실행은 결과를 기록한 뒤 종료합니다. 다른 Error Lab 인스턴스가 실행 중이면 먼저 정상 종료하세요.
`--snapshots`는 앱 자신의 off-screen NSHostingView만 렌더링합니다. 다른 앱/바탕화면 캡처나 Accessibility 권한은 쓰지 않습니다.
이는 실제 팝오버 클릭·종료·모니터 변경 자동화가 아니므로 그 항목은 여전히 수동 검사해야 합니다.

검사 범위의 한계: DB/메모리 초기화가 동시에 불가능한 OS 자원 고갈, 기기별 GPU·디스플레이 드라이버 오류,
실제 디스크 고장, 공증/Gatekeeper/App Store 설치·업데이트와 구버전 schema migration은 별도 기기·배포 빌드가 필요합니다.
실사용 디스크나 사용자 DB를 손상시켜 재현하지 마세요.
