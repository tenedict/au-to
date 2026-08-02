# 기능 요구사항 정의서 (SRS)

> BMAD Phase 2 · `bmad-prd` 의 요구사항 상세.
> [01-PRD.md](01-PRD.md) 가 **무엇을 왜** 만드는지 정한다면, 이 문서는 **무엇이 되어야 하는지**를 센다.

| 항목 | 값 |
| --- | --- |
| 문서 버전 | 1.0 |
| 최종 수정 | 2026-08-01 |
| 상태 표기 | ✅ 구현·검증 · 🟡 구현·미검증 · ⬜ 미구현 |

---

## 0. 읽는 법

- **FR** — 기능 요구사항. 사용자가 할 수 있어야 하는 것
- **INV** — 불변 조건. 어떤 경로로도 깨지면 안 되는 것
- 각 항목의 "검증" 칸은 이것을 지키는 **실제 테스트나 검사**를 가리킨다.
  빈칸이면 그 요구사항은 아직 아무도 지키지 않고 있다는 뜻이다.

---

## 1. 캡처 수집 (FR-CAP)

| ID | 요구사항 | 상태 | 검증 |
| --- | --- | --- | --- |
| FR-CAP-01 | 사진 앱 공유 시트에서 이미지 1장을 Whenly로 보낼 수 있다 | 🟡 | 실기기 |
| FR-CAP-02 | 담은 이미지와 메타데이터는 App Group 상자에 원자적으로 저장된다 | ✅ | `SharedInbox.enqueue` |
| FR-CAP-03 | 담기가 끝나면 Extension은 즉시 닫히고 결과를 문구로 알린다 | ✅ | 코드 리뷰 |
| FR-CAP-04 | 앱이 앞으로 나올 때마다 상자를 다시 훑는다 | ✅ | `RootView` scenePhase |
| FR-CAP-05 | 상자를 쓸 수 없으면 그 이유를 화면에 적는다 | ✅ | `SharedInbox.Availability` |
| FR-CAP-06 | OCR 결과를 캡처에 붙여 두어 재시도 시 다시 인식하지 않는다 | ✅ | `cacheRecognizedText` |

**INV-CAP-1 · 캡처는 사용자 확인 전에 지워지지 않는다.**
지우는 지점은 `TaskStore` 하나뿐이다. 프로젝트 규칙 5가 저장소 밖의 삭제를 막는다.

**INV-CAP-2 · App Group 식별자는 코드·project.yml·entitlements 두 파일에서 모두 같다.**
어긋나면 담기는 성공하고 도착만 실패한다. 프로젝트 규칙 1이 네 곳을 대조한다.

---

## 2. 텍스트와 문맥 분석 (FR-AI)

| ID | 요구사항 | 상태 | 검증 |
| --- | --- | --- | --- |
| FR-AI-01 | 한국어·영어 스크린샷에서 텍스트를 온디바이스로 추출한다 | ✅ | `VisionOCRService` |
| FR-AI-02 | 인식은 메인 스레드를 막지 않는다 | ✅ | 코드 리뷰 |
| FR-AI-03 | 글자를 찾지 못하면 그 사실을 말한다 | ✅ | `OCRServiceError.noTextRecognized` |
| FR-AI-04 | 추출 텍스트로 제목·메모·마감·신뢰도·근거·모호점을 제안한다 | ✅ | `BackendContextUnderstandingServiceTests` |
| FR-AI-05 | 분석기는 프로토콜 뒤에서 교체 가능하다 (백엔드 / 규칙 기반 / 온디바이스) | ✅ | `ContextUnderstanding.makeDefault` |
| FR-AI-06 | 백엔드가 없어도 규칙 기반으로 전체 흐름을 눌러 볼 수 있다 | ✅ | `WHENLY_OFFLINE=1` |
| FR-AI-07 | 텍스트만 붙여 넣어 분석을 시험할 수 있다 | ✅ | `ManualCaptureSheet` |
| FR-AI-08 | 분석 실패 시 원인을 구분해 알린다 (요청 거절 / 한도 / 서버 / 형식) | ✅ | `BackendAnalysisError` |

**INV-AI-1 · 백엔드가 죽었을 때 조용히 규칙 기반으로 떨어지지 않는다.**
품질이 낮은 결과를 말없이 내주면 사용자는 AI가 나빠졌다고 생각하고, 우리는 백엔드가
죽은 줄 모른다. 규칙 기반은 **명시적으로 골랐을 때만** 쓰인다.

**INV-AI-2 · OpenAI 키는 앱과 Extension에 존재하지 않는다.**
프로젝트 규칙 2가 소스에서 키·직접 호출 흔적을 막는다.

---

## 3. 확인 (FR-REV)

| ID | 요구사항 | 상태 | 검증 |
| --- | --- | --- | --- |
| FR-REV-01 | 저장 전에 반드시 확인 화면을 거친다 | ✅ | `RootView` 단일 경로 |
| FR-REV-02 | 제목·메모·날짜·시간을 고칠 수 있다 | ✅ | `TaskReviewView` |
| FR-REV-03 | 분석이 찾은 근거와 모호점을 보여준다 | ✅ | `TaskReviewView` |
| FR-REV-04 | 날짜 확인이 필요한 초안은 그 사실을 먼저 알린다 | ✅ | `TaskDraftTests` |
| FR-REV-05 | 캘린더 추가 토글은 확인이 필요한 초안에서 꺼진 채로 뜬다 | ✅ | `TaskDraft.mayPrefillCalendar` |
| FR-REV-06 | 알림을 언제 받게 되는지 실제 시각으로 보여준다 | ✅ | `reminderScheduleDescription` |
| FR-REV-07 | 초안을 나중으로 미루거나 버릴 수 있다 | ✅ | `TaskStoreTests` |
| FR-REV-08 | 확인하지 않은 초안은 앱을 껐다 켜도 남는다 | ✅ | `TaskStorageTests` |
| FR-REV-09 | 한 건을 처리하면 다음 초안을 이어서 보여준다 | ✅ | `RootView.presentNextDraftIfAny` |

**INV-REV-1 · 확인 화면을 지나지 않는 저장 경로는 없다.**

**INV-REV-2 · 신뢰도가 `Confidence.autoCalendarThreshold` 미만이면 캘린더 자동 추가를 제안하지 않는다.**
프로젝트 규칙 4가 이 임계값의 복사본을 막는다.

---

## 4. 할 일 목록 (FR-TASK)

| ID | 요구사항 | 상태 | 검증 |
| --- | --- | --- | --- |
| FR-TASK-01 | 마감이 급한 것부터 묶어 보여준다 | ✅ | `DueGroupingTests` |
| FR-TASK-02 | 묶음은 지난 마감 → 오늘 → 앞으로 7일 → 그 뒤 → 날짜 없음 → 완료 순이다 | ✅ | `testGroupsAppearInUrgencyOrder` |
| FR-TASK-03 | 묶음 안에서는 마감이 이른 것이 위다 | ✅ | `testDatedBucketIsSortedByNearestDeadline` |
| FR-TASK-04 | 카드는 지갑처럼 겹쳐 쌓이고, 누르면 펼쳐진다 | ✅ | `WalletStackLayoutTests` |
| FR-TASK-05 | 다른 카드를 누르면 앞의 것이 접힌다 (동시에 하나만 펼쳐진다) | ✅ | `DueStackView.toggleExpansion` |
| FR-TASK-06 | 급하지 않은 묶음은 접힌 채로 시작한다 | ✅ | `DueBucket.startsCollapsed` |
| FR-TASK-07 | 완료 표시·해제·삭제를 할 수 있다 | ✅ | `TaskStoreTests` |
| FR-TASK-08 | 목록은 앱을 껐다 켜도 남는다 | ✅ | `testStoreReloadsPersistedStateOnLaunch` |
| FR-TASK-09 | 중복 감지 | ⬜ | — |
| FR-TASK-10 | 검색·필터 | ⬜ | — |

**INV-TASK-1 · 완료한 할 일은 `지난 마감`에 올라오지 않는다.**
끝낸 일이 계속 급한 것으로 보이면 목록 전체를 믿지 않게 된다.

**INV-TASK-2 · 시간이 명시된 할 일은 그 시각이 지나면 같은 날이라도 지난 마감이다.**

**INV-TASK-3 · 마감 묶음과 정렬은 저장하지 않고 매번 계산한다.**

---

## 5. 마감 알림 (FR-NOTI)

| ID | 요구사항 | 상태 | 검증 |
| --- | --- | --- | --- |
| FR-NOTI-01 | 시간이 명시된 할 일은 1시간 전에 알린다 | ✅ | `ReminderScheduleTests` |
| FR-NOTI-02 | 종일 할 일은 마감 당일 09:00에 알린다 | ✅ | `ReminderScheduleTests` |
| FR-NOTI-03 | 마감 하루 전 20:00에도 알린다 | ✅ | `ReminderScheduleTests` |
| FR-NOTI-04 | 이미 지난 시각은 예약하지 않는다 | ✅ | `testPastFireTimesAreDropped` |
| FR-NOTI-05 | 할 일마다 알림을 끌 수 있다 | ✅ | `testRemindersCanBeTurnedOff` |
| FR-NOTI-06 | 완료하면 알림이 사라지고, 되돌리면 되살아난다 | ✅ | `TaskStoreTests` |
| FR-NOTI-07 | 삭제하면 알림도 취소된다 | ✅ | `testDeletingTaskCancelsItsReminders` |
| FR-NOTI-08 | 권한이 거절돼 있으면 그 사실과 켜는 법을 보여준다 | ✅ | `ReminderAuthorizationState.explanation` |
| FR-NOTI-09 | 앱이 앞으로 나올 때 전체 알림을 다시 맞춘다 | ✅ | `TaskStore.refresh` |
| FR-NOTI-10 | 스크린샷을 담으면 곧바로 확인을 요청한다 | ✅ | `CaptureNotice.postCaptureTaken` |
| FR-NOTI-11 | 확인 안 한 초안을 남기고 나가면 1시간 뒤 다시 알린다 | ✅ | `RootView` scenePhase |
| FR-NOTI-12 | 앱이 앞에 있으면 확인 요청 배너를 띄우지 않는다 | ✅ | `ReminderTapRouter.willPresent` |
| FR-NOTI-13 | 처리한 캡처의 알림은 알림 센터에서도 사라진다 | ✅ | `CaptureNotice.clear` |
| FR-NOTI-14 | 저장 전에도 사용자가 알림을 직접 켤 수 있다 | ✅ | `TaskStore.enableReminders` |

**INV-NOTI-1 · 알림은 로컬 알림이다.** 서버가 사용자의 할 일을 알지 못한다.

**INV-NOTI-2 · 알림 예약 지점은 두 곳뿐이다** — 마감은 `LocalNotificationService`,
확인 요청은 `CaptureNotice`. 시각 계산은 `ReminderSchedule` 순수 함수 하나다.
프로젝트 규칙 7이 그 밖에서의 직접 예약을 막는다.

**INV-NOTI-3 · 두 알림의 식별자가 겹치면 안 된다.**
앱은 식별자 문자열만 보고 둘을 가른다. 겹치면 "앞에 있을 때 확인 요청은 안 띄운다"는
규칙이 마감 알림에도 적용돼 **앱을 켜 둔 사용자가 마감을 그대로 놓친다.**

**INV-NOTI-4 · 담은 직후 알림은 하지 않은 일을 했다고 말하지 않는다.**
그 시점에는 아직 아무것도 읽지 않았다. "할 일을 만들었어요" 가 아니라 "담았어요" 다.

---

## 6. Apple 캘린더 (FR-CAL)

| ID | 요구사항 | 상태 | 검증 |
| --- | --- | --- | --- |
| FR-CAL-01 | 확인한 할 일을 Apple 캘린더에 추가할 수 있다 | 🟡 | 실기기·시뮬레이터 수동 |
| FR-CAL-02 | 시간이 있으면 1시간짜리, 없으면 종일 일정으로 만든다 | ✅ | 코드 리뷰 |
| FR-CAL-03 | 저장 성공 뒤에만 이벤트 식별자를 기록한다 | ✅ | 코드 리뷰 |
| FR-CAL-04 | 할 일을 지우면 캘린더 일정도 거둔다 | ✅ | `CalendarService.removeFromCalendar` |
| FR-CAL-05 | 권한 거절·기본 캘린더 없음을 구분해 알린다 | ✅ | `CalendarServiceError` |
| FR-CAL-06 | 앱에서 마감을 고치면 기존 일정도 고친다 | ⬜ | 미결정 D-3 |

**INV-CAL-1 · 캘린더 저장 실패가 할 일 저장을 되돌리지 않는다.**
캘린더는 출력이지 원장이 아니다.

---

## 7. 캘린더 뷰 (FR-MONTH)

| ID | 요구사항 | 상태 | 검증 |
| --- | --- | --- | --- |
| FR-MONTH-01 | 이번 달 격자에 마감이 있는 날을 표시한다 | ✅ | `MonthGridTests` |
| FR-MONTH-02 | 앞뒤 달로 이동할 수 있다 | ✅ | `testMonthOffsetCrossesYearBoundary` |
| FR-MONTH-03 | 날짜를 누르면 그날 마감인 할 일을 보여준다 | ✅ | `MonthCalendarView` |
| FR-MONTH-04 | 주 시작 요일은 로캘을 따른다 | ✅ | `testLeadingBlanksFollowFirstWeekday` |
| FR-MONTH-05 | 격자는 **읽기 전용**이다 | ✅ | 코드 리뷰 |

**INV-MONTH-1 · 캘린더 탭에서는 할 일을 만들거나 고칠 수 없다.**
두 곳에서 고칠 수 있으면 "어느 쪽이 진짜인가"를 사용자도 코드도 답하지 못한다.

---

## 8. 저장과 복구 (FR-STORE)

| ID | 요구사항 | 상태 | 검증 |
| --- | --- | --- | --- |
| FR-STORE-01 | 할 일과 초안을 원자적으로 저장한다 | ✅ | `TaskStorage.write` |
| FR-STORE-02 | 저장·복원 실패를 화면까지 올린다 | ✅ | `testCorruptStoreFileIsReportedOnLaunch` |
| FR-STORE-03 | 읽지 못한 파일은 지우지 않고 격리한다 | ✅ | `testCorruptFileIsQuarantinedAndReported` |
| FR-STORE-04 | 예전 버전이 쓴 파일을 계속 연다 | ✅ | `testDecodesTaskSavedBeforeRemindersFieldExisted` |
| FR-STORE-05 | 날짜는 밀리초까지 보존한다 | ✅ | `testDatesKeepMillisecondPrecision` |

**INV-STORE-1 · 저장 모델에 더하는 새 필드는 반드시 옵셔널이다.**
기본값이 있어도 그 필드가 없던 파일은 `keyNotFound`로 열리지 않고, 사용자는 할 일을 통째로 잃는다.

**INV-STORE-2 · 저장소 호출의 실패를 `try?`로 삼키지 않는다.**
프로젝트 규칙 8과 SwiftLint 전용 규칙이 함께 막는다.

---

## 9. 요구사항 수

| 영역 | 개수 | 완료 | 미구현 |
| --- | --- | --- | --- |
| 캡처 수집 | 6 | 5 | 0 (1건 실기기 대기) |
| 텍스트·문맥 | 8 | 8 | 0 |
| 확인 | 9 | 9 | 0 |
| 할 일 목록 | 10 | 8 | 2 |
| 마감 알림 | 15 | 15 | 0 |
| 캘린더 | 6 | 4 | 1 (1건 실기기 대기) |
| 캘린더 뷰 | 5 | 5 | 0 |
| 저장·복구 | 5 | 5 | 0 |
| **합계** | **64** | **59** | **3** |

불변 조건 14건.
