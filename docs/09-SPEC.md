# SPEC — 계약

> BMAD Phase 2 · `bmad-spec` → `SPEC.md`.
> 요구사항이 **무엇을**이라면, 계약은 **정확히 어떤 값이 어떤 조건에서 허용되는가**다.
> 각 계약에는 그것을 지키는 테스트가 붙어 있다. 없으면 그 계약은 지켜지지 않고 있다.

---

## 1. 도메인 계약

### C-1 · AssistantTask

| 필드 | 계약 |
| --- | --- |
| `title` | 비어 있을 수 없다 (확인 화면이 빈 제목 저장을 막는다) |
| `dueDate` | 없을 수 있다 |
| `hasExplicitTime` | `dueDate == nil` 이면 **반드시** false. 생성자가 강제한다 |
| `confidence` | 0...1 |
| `state` | `pending` \| `completed` |
| `origin` | `sourceCaptureID` 유무와 일치한다 |
| `sourceCaptureID` | 재시도 중복 방지를 위해 원본 캡처 식별자를 유지한다 |
| `calendarEventIdentifier` | EventKit 저장이 **성공한 뒤에만** 기록한다 |
| `remindersEnabled` | **옵셔널.** 없으면 켠 것으로 본다 (`wantsReminders`) |
| `createdAt` | 밀리초까지 보존된다 |

> **검증** — `TaskDraftTests.testTaskCannotHaveExplicitTimeWithoutDate`,
> `TaskStorageTests.testDecodesTaskSavedBeforeRemindersFieldExisted`

**C-1.1 · 새 필드는 반드시 옵셔널이다.**
기본값이 있어도 그 필드가 없던 예전 파일은 `keyNotFound` 로 열리지 않고, 사용자는
할 일을 **통째로** 잃는다. 새 필드마다 구버전 JSON 디코딩 테스트를 함께 쓴다.

### C-2 · TaskDraft

| | 계약 |
| --- | --- |
| `needsDateConfirmation` | `dueDate == nil` **또는** `confidence < Confidence.autoCalendarThreshold` **또는** 모호점이 있음 |
| `mayPrefillCalendar` | `dueDate != nil` **그리고** `!needsDateConfirmation` |
| 영속성 | 확인하지 않은 초안은 앱을 껐다 켜도 남는다 |

**C-2.1 · 임계값은 `Confidence.autoCalendarThreshold` 한 곳에만 존재한다.**
프로젝트 규칙 4와 SwiftLint 전용 규칙이 `0.80` 리터럴을 막는다. 흩어 놓으면 한 곳만
고쳐지고 "확인 없이 캘린더에 쓰지 않는다"는 약속이 경로마다 달라진다.

### C-3 · PendingCapture

| | 계약 |
| --- | --- |
| 쌍 | 메타데이터(`.json`)와 이미지(`.capture`)가 한 쌍이다 |
| 삭제 시점 | **사용자 확인(저장 또는 버리기) 뒤에만** |
| 삭제 지점 | `TaskStore` 하나뿐 (프로젝트 규칙 5) |
| 재시도 | 같은 `captureID` 로 중복 초안을 만들지 않는다 |
| OCR 캐시 | 인식 결과를 캡처에 붙여 재인식을 막는다 |

### C-4 · App Group 식별자

```
group.com.example.capturetask
```

이 문자열이 **네 곳**에서 같아야 한다.

| 어디 | 왜 |
| --- | --- |
| `CaptureTask/Shared/PendingCapture.swift` | 두 프로세스가 컨테이너를 찾는 키 |
| `project.yml` → `CaptureTask` 의 `entitlements.properties` | 생성물의 원본 |
| `project.yml` → `CaptureTaskShare` 의 `entitlements.properties` | 〃 |
| `Config/*.entitlements` (생성물) | 실제 서명에 들어가는 값 |

**C-4.1 · `project.yml` 에 `entitlements.properties` 로 적는다.**
`path` 만 적으면 `xcodegen generate` 가 파일을 빈 `<dict/>` 로 덮어쓴다.
그러면 담기는 성공하고 **도착만 실패한다** — 사용자에게는 "담았어요" 뒤에 아무 일도
일어나지 않는 것으로 보인다. 실제로 R0 이 이 상태로 통과했다.

> **검증** — 프로젝트 규칙 1 (네 곳 대조 + `properties` 존재 확인)

---

## 2. 마감 묶음 계약 (D)

### D-1 · 분류

```
완료함                                  → done
마감 없음                               → someday
시간 명시 + 그 시각이 지남                → overdue   ← 날짜가 오늘이어도
마감일 < 오늘                            → overdue
마감일 == 오늘                           → today
마감일이 오늘로부터 1~7일                 → within7Days
그 밖                                    → later
```

**D-1.1 · 시간이 명시된 할 일은 그 시각이 지나면 같은 날이라도 지난 마감이다.**
날짜만 비교하면 "오후 2시 예약"이 오후 6시에도 오늘 할 일로 남는다.

**D-1.2 · 종일 할 일은 하루가 끝날 때까지 오늘이다.** 시각이 없으므로 지날 시각도 없다.

### D-2 · 순서

| 묶음 | 순서 |
| --- | --- |
| overdue · today · within7Days · later | 마감이 이른 것부터 |
| someday · done | 최근에 만든 것부터 |

**D-2.1 · `지난 마감`도 이른 것이 위다.** 가장 오래 밀린 것이 제일 급하다.

**D-2.2 · 묶음 순서의 유일한 근거는 `DueBucket` 의 선언 순서다.**
화면이 다시 정렬하지 않는다. 정렬 지점이 둘로 갈라지면 "왜 이게 위에 있지"를 아무도 설명하지 못한다.

**D-3 · 파생 값을 저장하지 않는다.** `now` 가 흐르면 저장된 값이 아무것도 안 바뀌어도
묶음이 옮겨 간다. 저장하면 반드시 한쪽이 뒤처진다.

> **검증** — `DueGroupingTests` 13건

---

## 3. 알림 계약 (N)

### N-1 · 예약 시각

| 할 일 | 알림 |
| --- | --- |
| 시간 명시 | 마감 1시간 전 · 마감 하루 전 20:00 |
| 종일 | 마감 당일 09:00 · 마감 하루 전 20:00 |

**N-1.1 · 이미 지난 시각은 예약하지 않는다.**
지난 알림은 iOS 가 조용히 버리거나 즉시 울린다. 둘 다 사용자에게는 고장으로 읽힌다.

**N-1.2 · 다음 경우에는 아무것도 걸지 않는다** — 마감 없음 · 완료함 · `wantsReminders == false`.

### N-2 · 식별자

```
"<taskID.uuidString>#<ReminderKind.rawValue>"
```

한 할 일이 알림 여러 건을 갖기 때문에 `taskID` 만으로는 취소 대상을 고르지 못한다.
`rawValue` 를 바꾸면 **이미 예약된 알림을 취소하지 못한다.**

### N-3 · 재예약

| 언제 | 무엇 |
| --- | --- |
| 저장 | 전부 취소 후 다시 건다 |
| 완료·해제 | 전부 취소 후 다시 건다 |
| 삭제 | 전부 취소 |
| 앱이 앞으로 나옴 | 전체를 다시 맞춘다 |

**N-3.1 · 항상 먼저 전부 지운다.** 마감을 앞당겼는데 예전 알림이 남으면 이미 끝낸 일로 한 번 더 울린다.

**N-3.2 · 예약은 `LocalNotificationService` 하나, 시각 계산은 `ReminderSchedule` 하나다.**
프로젝트 규칙 7이 화면에서의 직접 예약을 막는다.

### N-4 · 확인 요청 알림

분석은 메인 앱에서만 돈다. 담고 앱을 열지 않으면 스크린샷은 상자에 남고
사용자에게는 아무 일도 일어나지 않는다. 그 구멍을 메우는 알림이다.

| 언제 | 누가 | 식별자 |
| --- | --- | --- |
| 스크린샷을 담은 직후 | Share Extension | `capture#<captureID>` |
| 확인 안 한 초안을 남기고 앱을 나간 뒤 1시간 | 메인 앱 | `capture#unconfirmed-drafts` |

**N-4.1 · 식별자가 마감 알림과 겹치면 안 된다.**
앱은 식별자 문자열만 보고 둘을 가른다. 겹치면 "앞에 있을 때 확인 요청은 안 띄운다"는
규칙이 마감 알림에도 적용돼, **앱을 켜 둔 사용자가 마감을 그대로 놓친다.**
`CaptureNoticeTests` 가 양방향으로 확인한다.

**N-4.2 · 앱이 이 캡처를 손에 쥐면 예약과 전달된 것을 **둘 다** 지운다.**
예약만 지우면 알림 센터에 남아, 이미 처리한 스크린샷을 확인하러 앱을 다시 연다.

**N-4.3 · 앱이 앞에 있으면 배너를 띄우지 않는다.** 확인 화면이 이미 떠 있다.

**N-4.4 · 문구는 하지 않은 일을 했다고 말하지 않는다.**
담은 직후에는 아직 아무것도 읽지 않았으므로 "할 일을 만들었어요" 가 아니라
"스크린샷을 담았어요 / 눌러서 할 일로 만들지 확인해 주세요" 다.

> **검증** — `ReminderScheduleTests` 10건 · `TaskStoreTests` 알림 4건

---

## 4. 쓰기 계약 (W)

- **W-1** 앱 할 일 저장과 캘린더 저장은 별도 결과다
- **W-2** 캘린더 실패 시 앱 할 일을 롤백하지 않는다
- **W-3** EventKit 중복 저장 방지를 위해 식별자를 영속화한다
- **W-4** 원본 캡처 삭제는 확인이 끝난 뒤에만 한다
- **W-5** 할 일 삭제 시 캘린더 일정도 거둔다. 실패해도 삭제를 막지 않는다
- **W-6** 완료 표시는 캘린더 일정을 건드리지 않는다 (지난 일정도 기록이다)

---

## 5. 저장 계약 (S)

| | 계약 |
| --- | --- |
| 위치 | `Application Support/CaptureTask/` |
| 파일 | `tasks.json` · `drafts.json` |
| 쓰기 | 원자적 (`.atomic`) |
| 날짜 쓰기 | ISO 8601 + **소수점(밀리초)** |
| 날짜 읽기 | 소수점 있음/없음 문자열, 그리고 숫자(R0 초기 형식) |
| 실패 | 던진다. `try?` 로 삼키지 않는다 |
| 손상 | 지우지 않고 `<이름>.corrupt-<시각>.json` 으로 격리 |

**S-1 · 날짜에 소수점을 반드시 적는다.** 초 단위로 잘리면 같은 초에 만든 두 할 일의
순서가 재실행 뒤에 뒤집히고, 그 원인을 아무도 추적하지 못한다.

**S-2 · 격리 뒤에는 빈 상태로 시작할 수 있어야 한다.** 계속 던지면 앱을 못 쓴다.

> **검증** — `TaskStorageTests` 8건

---

## 6. 문맥 분석 출력 계약 (A)

백엔드와 온디바이스 모델은 **같은 의미**를 반환해야 한다.

```json
{
  "title": "병원 예약 확인",
  "notes": "원문 또는 요약",
  "due_at": "2026-08-05T14:00:00+09:00",
  "has_explicit_time": true,
  "confidence": 0.91,
  "evidence": ["8월 5일 오후 2시"],
  "ambiguities": []
}
```

| 필드 | 계약 |
| --- | --- |
| `tasks` | **배열.** 한 장에 일정이 여러 개일 수 있다. 최대 8개 |
| `title` | 비어 있지 않음. 120자 초과분은 **자른다** |
| `notes` | 4000자 초과분은 자른다 |
| `due_at` | ISO 8601 또는 `null`. 파싱 불가면 거절 |
| `has_explicit_time` | `due_at == null` 이면 반드시 false. 아니면 **거절** |
| `confidence` | 0...1 밖이면 거절 |
| `evidence` · `ambiguities` | 8개 · 각 300자 초과분은 자른다 |

**A-0 · 응답은 언제나 `{ "tasks": [...] }` 다.** 하나여도 배열이다.
할 일 하나가 틀렸다고 나머지를 버리지 않는다 — 셋 중 하나가 이상하면 나머지 둘은 살린다.
전부 틀렸을 때만 응답 자체를 거절한다.

**A-1 · 모양이 틀린 것은 거절하고, 길이만 넘친 것은 자른다.**
제목이 한 글자 길다고 분석 전체를 버리면 사용자만 손해다.

**A-2 · 스키마 준수는 날짜가 사실이라는 뜻이 아니다.**
서버 JSON Schema 가 맞아도 앱이 `confidence`·날짜·빈 제목을 다시 검증한다.

**A-3 · strict 스키마에 지원되지 않는 제약 키워드를 넣지 않는다.**
`maxLength`·`minimum`·`maxItems` 등은 모델/버전에 따라 400으로 거절당한다.
범위 강제는 서버의 `validateTaskDraft` 가 한다.

**A-4 · 추론 파라미터는 모델군에 따라 붙인다.**
`reasoning`·`text.verbosity` 는 추론 계열(`gpt-5*`, `o*`)에만 있다. gpt-4.1 계열에
그대로 보내면 400 이 난다. 반대로 추론 모델에 빼면 기본 추론량이 붙어 느려지고 비싸진다.

**A-5 · 기본 모델은 실재하는 이름이어야 한다.**
실재하지 않는 이름을 기본값에 두면 키를 넣은 첫 호출이 404 로 죽는다. 그때 사용자에게는
"분석 서버에 연결하지 못했어요"만 보이고 원인은 키가 아니라 모델 이름이다.
프로젝트 규칙 10이 **정확 일치**로 검사한다 — 접두사로 두면 `gpt-5.6-luna` 가
`gpt-5` 로 시작한다는 이유로 통과한다.

> **검증** — 백엔드 테스트 15건

---

## 7. HTTP 계약

### `POST /v1/analyze-capture`

**요청**

```json
{ "recognized_text": "…", "locale": "ko-KR", "timezone": "Asia/Seoul", "now": "2026-08-01T12:00:00+09:00" }
```

**응답** — 6장의 출력 계약

| 상태 | 코드 | 언제 |
| --- | --- | --- |
| 200 | — | 성공 |
| 400 | `invalid_request` | 빈 원문, 해석 불가 JSON |
| 413 | `payload_too_large` | 본문 128KB 초과 |
| 401 | `unauthorized` | 클라이언트 키 없음·틀림 |
| 429 | `rate_limited` | OpenAI 한도 **또는** 우리 요청 한도 |
| 502 | `analysis_failed` | OpenAI 오류·연결 실패·응답 검증 실패 |
| 504 | `upstream_timeout` | OpenAI 응답 15초 초과 |

### H-3 · 클라이언트 인증

앱이 `X-CaptureTask-Key` 헤더에 공유 비밀을 실어 보낸다.

| | |
| --- | --- |
| 헤더 | `X-CaptureTask-Key` |
| 최소 길이 | 24자 |
| 비교 | `timingSafeEqual` — 길이가 다르면 먼저 거른다 |
| 없거나 틀림 | **401** `unauthorized` |
| `/health` | 인증 밖. Cloud Run 상태 확인이 키를 모른다 |

**H-3.1 · 루프백에 바인딩했을 때만 키 없이 돌 수 있다.**
`HOST` 가 `127.0.0.1`·`::1`·`localhost` 가 아니면 키를 **반드시** 요구하고,
없으면 서버가 시작을 거부한다. "로컬은 예외"라는 규칙이 그대로 배포로 따라가서 사고를 낸다.

**H-3.2 · 이 비밀은 앱 번들을 뜯으면 나온다.** 그걸 알고 쓰는 방식이다.

| 그래도 의미가 있는 이유 |
| --- |
| 새는 것이 OpenAI 키가 **아니라** 이 값이다 — 교체하면 끝난다 |
| 새기 전까지 무작위 스캐너와 크롤러를 전부 막는다 |
| 새더라도 요청 한도가 금액 피해를 제한한다 |

진짜로 앱만 통과시키려면 App Attest 가 필요하다. MVP 범위 밖이다.

**H-3.3 · 클라이언트 키에 `sk-` 로 시작하는 값을 넣을 수 없다.**
OpenAI 키를 여기에 잘못 넣으면 백엔드를 둔 이유(ADR-5)가 통째로 무너진다.
서버가 시작 시 거부한다.

**H-3.4 · 실제 값은 커밋되지 않는다.**
`Config/Secrets.xcconfig` 는 `.gitignore` 에 있고, 프로젝트 규칙 11 이
추적 여부와 예제 파일의 값을 함께 검사한다.

### H-4 · 요청 한도

| | 기본값 | 뜻 |
| --- | --- | --- |
| IP 당 분당 | 10회 | 사람이 스크린샷을 담는 속도를 훨씬 넘는다 |
| 인스턴스 당 하루 | 500회 | **금액 상한** |

**H-4.1 · 클라이언트 식별은 `X-Forwarded-For` 의 맨 앞이다.**
프록시 뒤에서는 socket 주소가 언제나 프록시다. 뒤쪽 항목을 쓰면 모든 사용자가
한 사람으로 묶여, 한 명이 한도를 채우는 순간 전부 막힌다.

**H-4.2 · 이 헤더는 위조할 수 있다.** 그래서 분당 한도는 방어의 한 겹일 뿐이고,
하루 총량이 위조와 무관하게 마지막 선을 지킨다.

**H-4.3 · 한도는 인스턴스마다 따로 센다 (메모리 기반).**
실제 금액 상한은 `하루 한도 × 최대 인스턴스 수` 다. 배포 스크립트가
`--max-instances` 를 고정하는 이유가 이것이다.

**H-4.4 · 429 에는 `Retry-After` 를 함께 준다.**

> **검증** — 백엔드 테스트 40건 (`auth.test.mjs` 10 · `rate-limit.test.mjs` 11 포함)

**H-1 · 업스트림 상태를 그대로 흘리지 않는다.**
앱은 "다시 시도해도 되는가"만 알면 된다. OpenAI 의 401 을 그대로 내보내면 앱이
사용자 잘못으로 오해하게 만든다.

**H-2 · 타임아웃 예산은 안쪽이 더 짧다.**

```
iOS URLRequest.timeoutInterval   20초
  └ backend → OpenAI              15초
```

바깥이 먼저 끊기면 안쪽 작업은 아무도 결과를 기다리지 않는 채 계속 돈다.

### `GET /health` → `{ "status": "ok" }`

### 주소

| | |
| --- | --- |
| iOS 개발 기본 | `http://127.0.0.1:8787` |
| 주입 | `CAPTURETASK_API_BASE_URL` (빌드 설정 → Info.plist, 또는 환경변수) |
| 우선순위 | 환경변수 → Info.plist → 기본값 |

---

## 8. 추적 매트릭스

| 계약 | 지키는 것 |
| --- | --- |
| C-1 · C-1.1 | `TaskDraftTests` · `TaskStorageTests` |
| C-2 · C-2.1 | `TaskDraftTests` · 프로젝트 규칙 4 · SwiftLint `confidence_threshold_literal` |
| C-3 | `TaskStoreTests` · 프로젝트 규칙 5 |
| C-4 · C-4.1 | **프로젝트 규칙 1** |
| D-1 ~ D-3 | `DueGroupingTests` 13건 |
| N-1 ~ N-3 | `ReminderScheduleTests` 10건 · `TaskStoreTests` 4건 · 프로젝트 규칙 7 |
| N-4 | `CaptureNoticeTests` 6건 · 프로젝트 규칙 7 |
| W-1 ~ W-6 | `TaskStoreTests` · 코드 리뷰 |
| S-1 · S-2 | `TaskStorageTests` 8건 · 프로젝트 규칙 8 · SwiftLint `swallowed_storage_error` |
| A-1 ~ A-5 | 백엔드 테스트 15건 · 프로젝트 규칙 10 |
| H-1 · H-2 | `backend/test/app.test.mjs` · `openai-client.test.mjs` |
| H-3 | `auth.test.mjs` 10건 · `app.test.mjs` 인증 4건 · **프로젝트 규칙 11** |
| H-4 | `rate-limit.test.mjs` 11건 · `app.test.mjs` 한도 1건 |
| 키 격리 | 프로젝트 규칙 2 · SwiftLint `openai_key_in_app` |
| Extension 경량 | 프로젝트 규칙 3 |

**검사기가 아니라 테스트가 지키는 것에 주의한다.** grep 은 "어떤 글자가 어디 있는가"까지만
답할 수 있다. "실제로 막는가"는 동작이므로 테스트의 몫이다.
