# Architecture Spine

> BMAD Phase 3 · `bmad-architecture` → `ARCHITECTURE-SPINE.md`.
> ADR 10건 · 모듈 구조 · 다음 과제.

---

## 1. 시스템 개요

```
사진 앱 / 메신저
      │ 공유
      ▼
┌──────────────────────┐
│ Share Extension      │  담기만 한다
└──────────┬───────────┘
           ▼
   App Group 상자 (파일)
           ▼
┌──────────────────────────────────────────────────┐
│ 메인 앱                                            │
│                                                  │
│  RootView ──── DueStackView · MonthCalendarView   │
│     │              TaskReviewView                 │
│     ▼                                            │
│  TaskStore  (@MainActor · 유스케이스 조율)          │
│     │                                            │
│     ├─→ OCRService ──────── VisionOCRService      │
│     ├─→ ContextUnderstandingService               │
│     │      ├─ BackendContextUnderstanding (기본)   │
│     │      ├─ RuleBased (오프라인 확인용)           │
│     │      └─ (예정) 온디바이스                     │
│     ├─→ TaskReminderScheduling ── LocalNotification│
│     ├─→ CalendarService ───────── EventKit         │
│     └─→ TaskStorage ───────────── JSON 파일        │
│                                                  │
│  Models (순수)                                    │
│    AssistantTask · TaskDraft                      │
│    DueGrouping · ReminderSchedule                 │
│    MonthGrid · WalletStackLayout                  │
└──────────────────────────────────────────────────┘
           │ HTTPS/HTTP
           ▼
┌──────────────────────┐
│ backend (Node 22)    │  OpenAI 키가 있는 유일한 곳
│  app.mjs             │
│  openai-client.mjs   │──→ OpenAI Responses API
│  task-draft-schema   │
└──────────────────────┘
```

의존은 위에서 아래 한 방향이다. Models 는 Store·View·플랫폼 프레임워크를 **모른다**
(프로젝트 규칙 6이 `Models/` 의 `import SwiftUI|UIKit|EventKit|Vision|UserNotifications` 를 막는다).

---

## 2. ADR

### ADR-1 · 계산은 모델의 순수 함수로 유지한다

**결정** — 마감 분류·정렬, 알림 시각, 월 격자, 지갑 카드 배치를 전부 `Models/` 의
순수 함수로 두고, 화면과 서비스는 부르기만 한다.

**왜** — 계산이 뷰 안에 있으면 검증하려고 화면을 띄워야 한다. 그러면 아무도 검증하지 않게 된다.
지갑 배치처럼 눈으로 보면 "대충 맞아 보이는" 것일수록 숫자로 잡아야 한다.

**대가** — 뷰 코드가 조금 길어진다. 대신 39건의 계산 테스트가 밀리초 안에 돈다.

### ADR-2 · Share Extension 은 수집 전용

**결정** — Extension 은 이미지를 App Group 상자에 담고 즉시 닫는다.
OCR·LLM·EventKit·알림은 전부 메인 앱이 한다.

**왜** — Extension 은 메모리·시간·수명 제약이 크고 시스템이 언제든 죽인다.
긴 작업을 넣으면 중간에 죽고, 사용자는 담기가 실패한 줄도 모른다.

**강제** — 프로젝트 규칙 3이 `CaptureTaskShare/` 와 `CaptureTask/Shared/` 에서
`EventKit`·`Vision`·`URLSession` 을 막는다.

**예외 하나 — 로컬 알림.** 막는 기준은 "무엇을 import 했는가"가 아니라 **"얼마나 오래 걸리는가"** 다.
네트워크·EventKit·Vision 은 수백 밀리초에서 수 초가 걸리지만 로컬 알림 예약은 파일 쓰기 한 번
수준이다. 그리고 그 알림이 없으면 **담기만 하고 앱을 안 연 사용자에게 아무 일도 일어나지 않는다** —
분석이 메인 앱에서만 돌기 때문이다. 그래서 `CaptureNotice` 하나만 허용하고 나머지는 그대로 막는다.

### ADR-3 · 문맥 분석기는 프로토콜 뒤에서 교체한다

**결정** — `ContextUnderstandingService` 프로토콜 하나에 구현 셋. 고르는 지점은
`ContextUnderstanding.makeDefault()` **한 곳**이다.

| 구현 | 언제 |
| --- | --- |
| `BackendContextUnderstandingService` | 기본 |
| `RuleBasedContextUnderstandingService` | `CAPTURETASK_OFFLINE=1` (DEBUG 전용) |
| 온디바이스 | 예정 — ADR-10 |

**왜** — 온디바이스로 옮길 때 화면·저장소·테스트를 건드리지 않기 위해서다.
고르는 지점이 여럿이면 옮길 때 한 곳이 반드시 남는다.

**하지 않는 것** — 백엔드가 죽었을 때 **자동으로** 규칙 기반으로 떨어지지 않는다.
조용히 품질이 낮은 결과를 내주면 사용자는 AI 가 나빠졌다고 생각하고, 우리는
백엔드가 죽은 줄 모른다.

### ADR-4 · AI 는 제안만 한다

**결정** — MVP 는 확인 화면을 **항상** 거친다. `confidence < 0.80` 이거나 모호점이 있으면
캘린더 자동 추가 토글을 미리 켜 주지 않는다.

**왜** — 일정 오인식은 실제 약속을 망가뜨린다. 잘못 저장된 일정 하나가 앱 전체의 신뢰를 없앤다.

**강제** — 임계값은 `Confidence.autoCalendarThreshold` 한 곳에만 존재한다
(프로젝트 규칙 4 + SwiftLint 전용 규칙).

### ADR-5 · API 키는 백엔드에만 둔다

**결정** — iOS 바이너리와 Extension 에 비밀 키를 포함하지 않는다.
앱은 우리 백엔드만 호출하고, 백엔드가 OpenAI 를 호출한다.

**왜** — 앱 번들의 문자열은 누구나 꺼낸다.

**강제** — 프로젝트 규칙 2 + SwiftLint `openai_key_in_app`.

**남은 것** — 백엔드 자체의 인증·rate limit 이 아직 없다 (NFR-SEC-05). 배포 전 필수.

### ADR-6 · 구조화 출력은 경계일 뿐 진실이 아니다

**결정** — OpenAI Structured Outputs 로 JSON Schema 를 강제하되, 서버가 범위를
다시 확인하고 앱이 또 한 번 검증한다.

**왜** — 스키마 준수는 날짜가 **사실**이라는 뜻이 아니다.

**추가 결정** — 스키마에는 `type` 만 넣고 `maxLength`·`minimum`·`maxItems` 는 넣지 않는다.
strict 모드가 지원하지 않는 키워드는 모델/버전에 따라 400 으로 거절당하고, 그러면
분석이 통째로 실패한다. 범위는 `validateTaskDraft` 가 서버에서 확인하고 **자른다** —
제목이 한 글자 길다고 분석 전체를 버리면 사용자만 손해다.

### ADR-7 · 앱 할 일이 원장이고 나머지는 시점이다

**결정**

| | 역할 | 고칠 수 있나 |
| --- | --- | --- |
| 앱 할 일 | 원장 | ✅ |
| Apple 캘린더 | 선택적 출력 | ❌ (앱에서 지우면 거둔다) |
| 캘린더 탭 | 읽기 전용 시점 | ❌ |
| 로컬 알림 | 원장에서 파생된 예약 | ❌ (자동 재계산) |

**왜** — 두 곳에서 고칠 수 있으면 "어느 쪽이 진짜인가"를 사용자도 코드도 답하지 못한다.
캘린더 저장 실패가 할 일 저장을 되돌리지 않는 것도 같은 이유다.

**대가** — 캘린더 앱에서 일정을 고쳐도 앱에 반영되지 않는다. MVP 에서 역동기화는 하지 않는다.

### ADR-8 · 알림은 로컬 알림이다

**결정** — `UNUserNotificationCenter` 로 기기에서 예약한다. 서버 푸시를 쓰지 않는다.

**왜** — 할 일은 기기에만 있다. 서버 푸시를 쓰려면 사용자의 할 일과 마감을 서버가 알아야 하고,
그 순간 이 앱의 프라이버시 성질이 통째로 바뀐다.

**대가** — 기기 여러 대에서 각각 울린다(현재는 기기 간 동기화가 없으니 문제되지 않는다).
알림 예약 한도(64건)를 넘으면 먼 미래 알림이 잘린다 — 할 일이 22건을 넘으면 검토가 필요하다.

**알림은 두 종류이고 소유자도 둘이다.**

| | 목적 | 소유자 | 식별자 |
| --- | --- | --- | --- |
| 마감 알림 | 마감을 놓치지 않게 | `LocalNotificationService` | `<taskID>#<kind>` |
| 확인 요청 | 담아 둔 것을 잊지 않게 | `CaptureNotice` | `capture#…` |

`CaptureNotice` 가 `Shared/` 에 있는 이유는 Share Extension 도 써야 하기 때문이다.
두 식별자가 겹치면 앱이 앞에 있을 때 마감 알림까지 조용히 사라진다 (계약 N-4.1).

**설계** — 시각 계산(`ReminderSchedule`)과 예약(`LocalNotificationService`)을 나눈 이유는,
계산을 서비스 안에 두면 검증하려고 실제 알림을 예약해야 하기 때문이다.
그러면 아무도 검증하지 않게 되고, 사용자는 안 오는 알림을 기다린다.

### ADR-9 · 저장 실패를 삼키지 않고 손상 파일을 격리한다

**결정** — 저장·복원 실패는 던져서 화면까지 올린다. 읽지 못한 파일은 **지우지 않고**
`<이름>.corrupt-<시각>.json` 으로 옮긴 뒤 빈 상태로 시작한다.

**왜** — 조용히 빈 목록으로 바꾸면 사용자는 할 일이 사라진 줄 안다.
지우면 복구를 시도할 수조차 없다. 사용자의 데이터다.

**강제** — 프로젝트 규칙 8 + SwiftLint `swallowed_storage_error` (`try? storage.` 금지).

### ADR-10 · 온디바이스 LLM 은 기본 엔진으로 아직 권하지 않는다

**결정** — 첫 버전 기본은 백엔드다. 온디바이스는 같은 프로토콜 아래에서 shadow mode 로 비교한 뒤 전환한다.

| | 장점 | 단점 |
| --- | --- | --- |
| 온디바이스 | 오프라인 · 프라이버시 · 호출비 0 | 앱 크기/메모리/발열 · 구형 기기 편차 · 한국어 날짜 추론 품질 · 업데이트 난이도 |

**전환 조건**
1. 익명화 평가셋 50건과 기대 JSON 이 있다
2. 날짜 정확도가 백엔드 대비 95% 이상이다
3. p95 지연이 3초 이내다

**전환 방법** — `ContextUnderstanding.makeDefault()` 한 줄. 다른 곳은 건드리지 않는다.
그 다음 단계는 "로컬 기본 + 서버 fallback"이다.

---

## 3. 모듈 구조

```
CaptureTask/
  App/          진입점
  Models/       순수 값 · 순수 함수     ← 아무것도 import 하지 않는다 (Foundation 제외)
  Services/     플랫폼 · 네트워크 어댑터
  Shared/       앱 ↔ Extension 공유     ← Extension 타깃에도 들어간다
  Store/        상태 · 영속화 · 유스케이스 조율
  Views/        SwiftUI
CaptureTaskShare/  담기 전용
CaptureTaskTests/  90건
server/           Node 22 · 외부 패키지 0 · 15건
scripts/           verify · 규칙 검사 · 시뮬레이터 선택
```

**`Shared/` 가 Extension 타깃에도 들어가는 것이 중요하다.** 그래서 여기에 무거운 것을
넣으면 ADR-2 가 깨진다. 프로젝트 규칙 3이 `Shared/` 도 함께 본다.

---

## 4. 빌드 · 생성물

| | |
| --- | --- |
| 프로젝트 정의 | `project.yml` (XcodeGen) |
| `.xcodeproj` | **생성물.** 추적하지 않는다 |
| entitlements | `project.yml` 의 `entitlements.properties` 에서 생성 |

**`.xcodeproj` 를 추적하지 않는 이유** — 소스가 두 벌이 되고, 병합 충돌이 `pbxproj`
안에서 나서 아무도 못 읽는다.

**entitlements 를 `properties` 에 적는 이유** — `path` 만 적으면 XcodeGen 이 파일을
빈 `<dict/>` 로 덮어쓴다. 실제로 이 프로젝트가 그 상태로 R0 을 통과했고,
App Group 이 비어 있어 공유 시트 경로 전체가 죽어 있었다.

---

## 5. 다음 과제

| # | 과제 | 막고 있는 것 |
| --- | --- | --- |
| R1-1 | 실기기 서명·App Group 프로비저닝 | — |
| R1-2 | 백엔드 인증·rate limit | 배포 차단 (NFR-SEC-05) |
| R1-3 | 익명화 평가셋 50건 | ADR-10 전환 판단 |
| R1-4 | 중복 감지 정책 | 무엇을 중복으로 볼지 미결정 |
| R2-1 | Dynamic Type 대응 | 카드 높이가 고정값 (G-2) |
| R2-2 | 모션 줄이기 대응 | (G-3) |
| R2-3 | 알림 탭 → 해당 카드 라우팅 | (G-4) |
| R2-4 | 알림 64건 한도 대응 | 할 일 22건 초과 시 |
