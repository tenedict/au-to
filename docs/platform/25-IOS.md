# iOS 앱

> 공유하거나 찍으면 **뒤에서 읽고 등록하고 알린다.** 앱을 열 필요가 없다.
> 2026-08-03

관련 — [18장 macOS](18-MACOS.md) · [22장 위젯](22-WIDGETS.md) ·
[20장 저장소 배치](../engineering/20-REPO-LAYOUT.md) · [21장 API](../engineering/21-API.md)

---

## 1. 기술 스택

| 항목 | 값 | 왜 |
| --- | --- | --- |
| 최소 버전 | iOS 17.0 | `@Observable` 없이도 되는 최소선. 아래로 내리면 `ContentUnavailableView`·`photosPicker` 를 직접 만들어야 한다 |
| 언어·UI | Swift 5, SwiftUI | 화면 넷과 시트 셋이 전부라 UIKit 을 깔 이유가 없다 |
| UIKit 을 쓰는 곳 | 앱 델리게이트 · 공유 확장 · 카메라 | 셋 다 SwiftUI 로는 **할 수 없는 일**이다 (§5·§6) |
| 상태 | `@MainActor` + `ObservableObject` | 저장소가 하나뿐이라 더 큰 장치가 필요 없다 |
| 저장 | App Group 안의 JSON | 확장·위젯이 같은 파일을 본다 (§7) |
| 텍스트 인식 | Vision (온디바이스) | 원본 이미지는 기기를 떠나지 않는다 |
| 문맥 분석 | 우리 백엔드 → OpenAI | 키를 앱에 넣지 않는다 (ADR-5) |
| 캘린더 | EventKit | 선택적 **출력**이다. 원장이 아니다 (ADR-7) |
| 알림 | `UNUserNotificationCenter` (로컬) | 서버 푸시를 쓰면 서버가 사용자의 일정을 알아야 한다 |
| 위젯 | WidgetKit | [22장](22-WIDGETS.md) |
| 외부 의존성 | **없음** | 패키지 하나가 최소 버전을 끌어올리는 일을 겪지 않는다 |
| 프로젝트 정의 | XcodeGen (`project.yml`) | `.xcodeproj` 는 생성물이고 커밋하지 않는다 |

### 타깃 넷

```
Whenly           앱          apps/ios/App · Views · Resources + core/swift
WhenlyShare      공유 확장    apps/ios/Share              + core/swift
WhenlyWidgets    위젯 확장    apps/ios/Widgets            + core/swift
WhenlyTests      테스트       tests/swift
```

셋 다 `core/swift` 를 통째로 쓴다. **계산·저장·서비스가 한 벌뿐**이라 확장이 만든
할 일과 앱이 만든 할 일이 다를 수가 없다.

> **확장에서 못 쓰는 API 가 있다.** `UIApplication.shared` 가 대표적이다.
> `project.yml` 이 확장 타깃에만 `APP_EXTENSION` 을 켜 주고, 공유 코드는
> `#if canImport(UIKit) && !APP_EXTENSION` 으로 가른다 (`BackgroundActivity.swift`).

---

## 2. 들어오는 길 다섯

| 길 | 어디서 시작하나 | 특징 |
| --- | --- | --- |
| **공유 시트** | 다른 앱 → 공유 → Whenly | 확장이 등록까지 끝낸다. 최대 10장 |
| **잠금화면 위젯** | 잠금화면 → 누르기 | 카메라가 곧바로 뜬다 (§6) |
| 사진에서 고르기 | 앱 → + → 사진에서 고르기 | PHPicker 라 사진 권한이 필요 없다 |
| 텍스트 붙여넣기 | 앱 → + → 텍스트 | 스크린샷 없이 분석만 눌러 볼 때 |
| **직접 적기** | 앱 → + → 직접 적기 | 분석을 거치지 않는다. 확인 표식도 없다 |

다섯 중 넷이 **같은 줄**(`CaptureQueue`)로 들어간다. 직접 적기만 편집기로 바로 간다 —
사람이 적은 것을 사람에게 다시 확인시킬 이유가 없다.

---

## 3. 한 장이 일정이 되기까지

```
① 담는다      SharedInbox.enqueue        App Group 안에 원본을 먼저 쓴다
② 줄에 선다   CaptureQueue.enqueue       1분에 10건 · 앞의 열 개는 기다리지 않는다
③ 읽는다      VisionOCRService           온디바이스
④ 이해한다    BackendContext…Service     우리 백엔드 → OpenAI
⑤ 등록한다    TaskStore.file             언제나 등록. 애매하면 reviewReason 을 붙인다
⑥ 알린다      CaptureNotice.postFiled    "언제 무슨 일정이 등록되었습니다" + taskID
```

**①이 ④보다 먼저인 것이 이 흐름의 유일한 안전망이다.** 시스템은 확장을 언제든
죽일 수 있고, 앱은 언제든 잠든다. 원본이 상자에 남아 있으면 다음 실행이 이어서
처리한다 (ADR-2).

**⑤에서 막지 않는다.** 예전에는 애매하면 등록하지 않고 확인을 기다렸는데,
사용자에게는 스크린샷을 놓고도 **아무 일도 일어나지 않는 것**으로 보였다.
지금은 등록하고 표식만 붙인다 (ADR-4 개정).

**⑥에 `taskID` 가 반드시 들어간다.** 없으면 알림을 눌러도 목록만 뜨고, 사용자는
그것을 다시 찾아야 한다 — 실제로 "눌러도 안 들어가진다" 는 말을 들었다 (§5).

---

## 4. 뒤에서 도는 읽기 — 가장 자주 깨진 자리

### 왜 화면이 들고 있으면 안 되나

읽기를 화면이 들고 있으면 **화면이 사라질 때 처리도 사라진다.** 그런데 이 제품의
정상 동선이 정확히 그것이다 — 찍고 나가기, 공유하고 앱 들어가기, 물방울에 놓고
창 열기. 그래서 `CaptureQueue` 는 앱 델리게이트가 들고 있다.

### 앱이 잠들면 요청이 끊긴다

`CaptureQueue` 가 화면 밖에 있어도, **iOS 는 앱을 몇 초 안에 재운다.**
잠금화면 위젯 → 카메라 → 찍기 는 찍자마자 앱을 나가는 동선이라 이걸 정면으로 맞는다.

```
사진 찍기 → 앱 나감 → 몇 초 뒤 잠듦 → 요청 끊김 → 알림 없음
   → 다시 열면 "읽는 중" + "요청 시간이 다 되었어요"
```

그래서 줄 전체를 **백그라운드 작업 하나로 감싼다** (`BackgroundActivity`).
`beginBackgroundTask` 가 대략 30초를 주고, 한 장에는 넉넉하다.

| 왜 장마다 잡지 않나 | 장 사이에 시간이 끊기면 그 틈에 앱이 잠든다. "세 장 놓았는데 하나만 등록" 이 된다 |
| 시간이 모자라면 | **잃지는 않는다.** 캡처가 상자에 남아 다음 실행이 이어서 처리한다 |
| 만료 처리를 왜 주나 | 안 주면 시스템이 앱을 **강제 종료**한다 |

### 제한시간

| 값 | 왜 |
| --- | --- |
| 요청 25초 | 20초로는 부족했다. 백엔드가 `min-instances 0` 이라 첫 요청이 콜드 스타트를 기다린다 |
| 전체 50초 | `URLSession.shared` 는 전체 소요에 제한이 없어, 뒤로 갔다 온 요청이 끝나지 않는다 |
| 30초(시스템) 보다 짧게 | 시간이 끝나 앱이 멈추는 것보다 **우리가 먼저 포기하고 알리는 편**이 낫다 |

---

## 5. 알림

### 종류 둘

```
마감 알림   ReminderSchedule 이 계산 · LocalNotificationService 가 예약
  시간 지정   1시간 전 · 하루 전 20:00
  종일        당일 09:00 · 하루 전 20:00
  지난 시각   걸지 않는다 (iOS 가 버리거나 즉시 울린다 — 둘 다 고장으로 읽힌다)

등록 알림   CaptureNotice · 식별자 앞에 "capture#"
  postFiled         "일정을 등록했어요" + 무엇이 언제 + (필요하면) 확인 요청
  postNothingFound  아무것도 못 찾았을 때
```

**둘의 식별자가 겹치면 안 된다.** 겹치면 한쪽을 지울 때 다른 쪽까지 지워진다.
`CaptureNoticeTests` 가 이걸 지킨다.

### 눌렀을 때 — 두 번 깨졌던 자리

**하나 · 종류를 접두사로 단정했다.** 라우터가 `capture#` 로 시작하면 `taskID` 를
읽지도 않고 끝냈는데, 등록 알림도 같은 접두사다. 앱은 열리는데 목록 맨 위에
그대로 서 있었다. 지금은 **`taskID` 를 먼저 본다.**

**둘 · 시트를 셋 겹쳐 달았다.** `.sheet` 를 같은 뷰에 셋 붙였는데(설정 · 텍스트 ·
편집기), SwiftUI 는 **뷰 하나에 표시 하나**만 지원한다. 먼저 붙은 것이 이기고
나머지는 조용히 무시된다 — 그래서 알림이 편집기를 열라고 해도 아무것도 뜨지 않았다.
앱은 열리는데 화면이 없으니 사용자에게는 여전히 "안 들어가진다" 다.
지금은 `Sheet` 열거형 하나에 `.sheet(item:)` 하나다.

**셋 · 델리게이트를 너무 늦게 붙였다.** `.onAppear` 는 첫 화면이 그려진 뒤라,
알림을 눌러 들어온 **첫 실행**은 시스템이 그 응답을 이미 버린 뒤였다.
그래서 `UIApplicationDelegateAdaptor` 를 두고 `didFinishLaunchingWithOptions`
에서 붙인다. **이 앱이 UIKit 델리게이트를 두는 유일한 이유다.**

---

## 6. 카메라

잠금화면 위젯 → `whenly://capture` → `CameraCaptureSheet`(`UIImagePickerController`).

`AVCaptureSession` 을 직접 다루면 회전·플래시·초점·권한 안내를 전부 만들어야 하는데,
그건 이 제품이 잘할 일이 아니다.

찍은 뒤 **확인 화면을 두지 않는다.** 잘못 찍었으면 다시 찍으면 되고, 등록된 것은
알림에서 눌러 고치거나 지울 수 있다.

> **시뮬레이터에는 카메라가 없다.** 확인하지 않고 열면 빈 검은 화면이 뜨고 취소도
> 되지 않는다. `CameraCaptureSheet.isAvailable` 을 보고 사진 고르기로 돌린다.

---

## 7. 저장

```
App Group(group.com.example.whenly)/
  Whenly/tasks.json      할 일 — 원장
  Inbox/<uuid>.capture   원본 이미지
  Inbox/<uuid>.json      캡처 메타 + OCR 결과 캐시
```

| 규칙 | 왜 |
| --- | --- |
| **App Group 안에 둔다** | 확장의 Application Support 는 앱의 것과 다른 상자다. 각자 저장하면 공유로 만든 할 일이 앱에 없다 |
| 원자적 쓰기 | 중간에 죽어도 반쪽 파일이 남지 않는다 |
| 못 읽은 파일은 **격리** | 지우지 않는다. 사용자의 데이터다 |
| 새 필드는 **반드시 옵셔널** | 기본값이 있어도 예전 파일이 `keyNotFound` 로 안 열린다 → 할 일을 통째로 잃는다 |
| 옛 위치·옛 이름을 가져온다 | `legacyDirectoryNames`. 이름을 바꾸면 파일은 그대로인데 아무도 그 자리를 보지 않는다 |

**파생 값을 저장하지 않는다.** 마감 묶음·정렬·월 격자·확인 필요 목록은 매번 계산한다.
저장하면 반드시 한쪽이 뒤처진다.

---

## 8. 화면

```
할 일 탭     DueStackView      요약 타일 + 지갑 스택
캘린더 탭    MonthCalendarView 월 격자 + 고른 날의 일정
시트         TaskEditorSheet   무엇을 누르든 여기로 온다
             SettingsSheet · ManualCaptureSheet · CameraCaptureSheet
```

| 규칙 | 어디 |
| --- | --- |
| 색은 둘뿐 (`water`·`past`) | `Palette` |
| 간격·치수·모서리 | `Space` · `CardMetrics` · `Radius` |
| 날짜 문구는 화면이 만들지 않는다 | `DueDateText` — 화면은 폭 등급만 고른다 |
| 요약 타일 생김새 | `SummarySurface` — **맥과 같은 것을 쓴다** |
| 편집 규칙 | `TaskEdit` — **맥과 같은 값을 쓴다** |

**접근성 글자 크기에서는 겹침을 포기한다.** 지갑 겹침은 접힌 카드의 윗부분만
보이는 것을 전제하는데, 그 크기에서는 제목 한 줄만으로 그 공간을 넘긴다.

---

## 9. 눌러 보기

```bash
# 서명해서 빌드한다. CODE_SIGNING_ALLOWED=NO 로 빌드하면 entitlements 가 안 박혀
# App Group 이 언제나 nil 이고, 앱이 "공유 시트로 담기를 쓸 수 없어요" 를 띄운다.
xcodebuild build -project Whenly.xcodeproj -scheme Whenly -sdk iphonesimulator \
  -destination "id=$(./scripts/select-simulator.sh)" -derivedDataPath /tmp/ct-signed
```

DEBUG 갈고리 — 시뮬레이터에서는 `SIMCTL_CHILD_` 접두사를 붙인다.

| 변수 | 무엇 |
| --- | --- |
| `WHENLY_OFFLINE=1` | 규칙 기반 분석기로 시작 (백엔드 없이) |
| `WHENLY_TAB=0\|1` | 시작 탭 |
| `WHENLY_SHEET=settings\|text` | 시작하자마자 그 시트 |
| `WHENLY_OPEN_TASK=first\|<uuid>` | **알림을 누른 것과 같은 길**을 탄다 |

알림 탭은 자동화할 수 없다. 마지막 갈고리가 없으면 라우팅이 살아 있는지 확인할
방법이 사람 손밖에 없고, 실제로 그래서 깨진 것을 한참 뒤에 알았다.

```bash
SIMCTL_CHILD_WHENLY_OPEN_TASK=first xcrun simctl launch <UDID> com.example.whenly
```

```bash
xcrun simctl openurl <UDID> "whenly://capture"    # 잠금화면 위젯과 같은 길
```

---

## 10. 겪은 함정

| 증상 | 진짜 원인 |
| --- | --- |
| 담기는 성공하는데 앱에 도착하지 않음 | entitlements 가 빈 `<dict/>`. `project.yml` 의 `properties` 에 적어야 살아남는다 |
| 알림을 눌러도 아무 데도 안 감 | 접두사로 종류를 단정 · **`.sheet` 를 셋 겹쳐 닮** · 델리게이트를 늦게 붙임 (§5) |
| 찍고 나가면 등록이 안 됨 | 백그라운드 작업을 안 잡음 (§4) |
| "요청 시간이 다 되었어요" | 제한시간 20초 + 백엔드 콜드 스타트 (§4) |
| 카드 마감이 잘림 | 화면이 날짜 문구를 직접 만듦 → `DueDateText` 로 |
| 단위 테스트가 583초 | 저장소가 `CalendarService()` 를 직접 만들어 EventKit 권한 요청에 걸림 |
| 알림 아이콘이 안 바뀜 | **옛 번들(`com.example.capturetask`)이 아직 깔려 있음.** 지워야 한다 |

---

## 11. 아직 못 한 것

| | 막고 있는 것 |
| --- | --- |
| 실기기 공유 시트 | Bundle ID · App Group 프로비저닝 |
| 위젯 실물 확인 | 시뮬레이터에서 위젯 배치를 자동화할 수 없다 |
| 카메라 → 등록 | 시뮬레이터에 카메라가 없다 |
| 기기 간 동기화 | 계정이 없다 ([24장 §5](../product/24-GROWTH-STRATEGY.md)) |
