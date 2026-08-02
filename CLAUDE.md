# CaptureTask — 작업 규칙

스크린샷을 공유하면 온디바이스 OCR과 문맥 분석으로 할 일을 만들고,
사용자 확인 뒤 Apple 캘린더와 마감 알림까지 이어 주는 iOS 개인 비서 앱.

> 자세한 맥락은 [`docs/project-context.md`](docs/project-context.md), 개발 규율은 [`docs/16-ENGINEERING-PLAYBOOK.md`](docs/engineering/16-ENGINEERING-PLAYBOOK.md).

---

## 검증 — 완료 전에 반드시

```bash
./scripts/verify.sh
```

**실패하면 완료했다고 보고하지 않는다.** 사람·Claude·Git Hook·CI가 모두 이 명령 하나를 쓴다.
빠른 확인만: `./scripts/verify.sh --quick` (iOS 테스트 제외)

검사 항목 — 프로젝트 규칙 · `swift format` · SwiftLint(설치 시) · 백엔드 테스트 · iOS 전체 테스트

```bash
# 개별 실행
./scripts/check-project-rules.sh          # 이 프로젝트만의 규칙
./scripts/check-project-rules.sh --list   # 어떤 규칙이 있는지
cd server && npm test                    # 백엔드만
xcodegen generate && xcodebuild test -project CaptureTask.xcodeproj -scheme CaptureTask \
  -sdk iphonesimulator -destination "id=$(./scripts/select-simulator.sh)" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO
```

DEBUG 라우팅 — `CAPTURETASK_OFFLINE=1` · `CAPTURETASK_TAB=0|1` (탭) · `CAPTURETASK_SHEET=settings|text` (시트)
macOS 는 `CAPTURETASK_OPEN_LIST=1` (대시보드 열기) · `CAPTURETASK_FILE=<경로>` (그 이미지 처리).
시뮬레이터에서는 `SIMCTL_CHILD_` 접두사를 붙이고, macOS 는 `open -n --env KEY=VAL` 로 준다.

**시뮬레이터에서 공유 상자를 쓰려면 서명해서 빌드한다.** `CODE_SIGNING_ALLOWED=NO` 로 빌드하면
entitlements 가 안 박혀 App Group 이 언제나 nil 이고, 앱이 "공유 시트로 담기를 쓸 수 없어요" 를 띄운다.
테스트는 서명이 필요 없어 `verify.sh` 는 그대로 두고, 눌러 볼 때만 서명 빌드를 쓴다.

```bash
xcodebuild build -project CaptureTask.xcodeproj -scheme CaptureTask -sdk iphonesimulator \
  -destination "id=$(./scripts/select-simulator.sh)" -derivedDataPath /tmp/ct-signed
```

`.xcodeproj` 는 생성물이다. 프로젝트 설정은 **`project.yml` 에서만** 고친다.
`config/apple/Secrets.xcconfig` 는 커밋되지 않는다. 없으면 `verify.sh` 가 예제에서 만든다.

**빌드 설정 우선순위** — 타깃 설정 > 타깃 xcconfig > **프로젝트 설정** > 프로젝트 xcconfig.
그래서 xcconfig 로 덮어써야 하는 값의 기본값은 `project.yml` 의 **프로젝트 수준**에 둔다.
타깃 `settings.base` 에 두면 xcconfig 가 조용히 무시되고, 빌드는 성공하는데
앱만 엉뚱한 주소를 바라본다.

---

## 구조

```
apps/ios      App/ Views/ Resources/ Share/      화면은 여기서만 갈린다
apps/macos    App/ Views/ Windows/ Resources/ Share/
core/swift    Models/ Services/ Store/ Shared/   두 앱과 두 확장이 전부 쓴다
tests/swift   core/swift 의 계산·저장 테스트
server        모든 플랫폼이 부르는 단 하나의 백엔드
config/apple  entitlements · Secrets.xcconfig
```

```
View (SwiftUI) → Store (@MainActor ObservableObject) → Service 프로토콜 → 플랫폼/API 어댑터
                              ↘ Model (순수 값 · 순수 함수)

Share Extension → App Group inbox → 메인 앱이 꺼내서 처리
사진 고르기(PhotosPicker) ↗
```

**플랫폼이 늘어도 `apps/` 아래 폴더 하나만 늘어난다.** 언어가 다른 공용 코드가
생기면 `core/` 아래 형제(`core/kotlin/` …)로 들어온다.
무엇을 어디에 더하는지는 [`docs/engineering/20-REPO-LAYOUT.md`](docs/engineering/20-REPO-LAYOUT.md).

**경로를 아는 곳은 정해져 있다** — `project.yml` · `check-project-rules.sh` 맨 위 여섯 줄 ·
`verify.sh` · `.swiftlint.yml` · `lefthook.yml` · `.gitignore` · CI.
구조를 바꾸면 여기가 전부 따라 바뀌어야 한다. 하나라도 남으면 그 검사는
빈손으로 훑고도 조용히 초록을 낸다.

**분석 엔진을 고르는 지점은 `AnalysisEngine` + `ContextUnderstanding.make(_:)` 한 곳뿐이다.**
나중에 온디바이스를 붙일 때 건드릴 파일은 둘이고, 화면·저장소·테스트는 그대로다.
비교 분석은 [`docs/17-ONDEVICE-LLM-RESEARCH.md`](docs/platform/17-ONDEVICE-LLM-RESEARCH.md).

의존은 이 한 방향뿐이다. Model은 Store·View·EventKit·Vision·UserNotifications를 모른다.
마감 분류·알림 시각·월 격자·지갑 스택 배치가 전부 `core/swift/Models/` 의 순수 함수다.

---

## 반드시 지킬 것

1. **AI 결과는 제안이다.** 앱 할 일 또는 캘린더에 쓰기 전 사용자가 확인한다. 확인 화면을 지나지 않는 저장 경로를 만들지 않는다
2. **신뢰도 임계값은 `Confidence.autoCalendarThreshold` 한 곳에서만.** `0.80` 리터럴을 흩어 놓으면
   한 곳만 고쳐지고, "확인 없이 캘린더에 쓰지 않는다"는 약속이 경로마다 달라진다
3. **OpenAI 키를 앱이나 Share Extension에 넣지 않는다.** 반드시 백엔드를 거친다. 키가 번들에 들어가면 누구나 꺼낸다
4. **App Group 식별자는 `project.yml` 의 `entitlements.properties` 에 적는다.**
   `path` 만 적으면 `xcodegen generate` 가 파일을 빈 `<dict/>` 로 덮어쓴다.
   그러면 담기는 성공하고 **도착만 실패한다** — 사용자에게는 "담았어요" 뒤에 아무 일도 안 일어난 것으로 보인다 (실제로 R0을 이 상태로 통과했다)
5. **Share Extension은 분석보다 담기가 먼저다.** 확장이 OCR·분석·캘린더까지 끝내지만,
   `SharedInbox.enqueue` 를 **반드시 먼저** 부른다. 시스템은 언제든 확장을 죽일 수 있고,
   담기가 먼저여야 죽어도 캡처가 남아 앱이 이어서 처리한다.
   ADR-2 의 알맹이는 "무거운 것 금지"가 아니라 **"죽어도 잃지 마라"** 다
6. **캘린더 실패가 할 일 저장을 막지 않는다.** 캘린더는 출력이지 원장이 아니다. 소유권은 언제나 앱에 있다
7. **캡처는 사용자 확인 뒤에만 지운다.** 지우는 지점은 `TaskStore` 하나뿐이다. 여러 곳이면 그중 하나는 반드시 확인보다 먼저 지운다
8. **저장·복원 실패를 `try?`로 삼키지 않는다.** 사용자는 잃은 뒤에 안다. 못 읽은 파일은 지우지 말고 격리한다
9. **저장 모델에 더하는 새 필드는 반드시 옵셔널.** 기본값이 있어도 예전 파일이 `keyNotFound`로 안 열리고, 그러면 할 일을 통째로 잃는다. 새 필드마다 구버전 JSON 디코딩 테스트를 함께 쓴다
10. **날짜·시각 계산에 `now`를 인자로 받는다.** 안에서 `.now`를 읽으면 테스트가 오늘 날짜에 따라 흔들린다
11. **알림 예약은 정해진 두 파일에서만.** 마감은 `LocalNotificationService`, 확인 요청은 `CaptureNotice`.
    화면이 직접 걸면 취소 지점이 갈라지고 끝낸 일이 계속 울린다.
    두 알림의 **식별자가 겹치면 안 된다** — 겹치면 앱이 앞에 있을 때 마감 알림까지 조용히 사라진다
12. **비활성 컨트롤에는 언제나 이유를 함께 보여준다.** 이유 없는 비활성은 고장으로 읽힌다
13. **색만으로 정보를 전달하지 않는다.** 새 인터랙티브 요소엔 접근성 레이블을 붙인다
14. **파생 값(마감 묶음·정렬·격자)을 저장하지 않는다.** 매번 계산한다
15. 화면 파일은 500줄 이내
16. `#if DEBUG` 코드는 릴리스 빌드에 새지 않는다

---

## 도메인에서 헷갈리면 안 되는 것

**할 일의 원장은 앱 하나뿐이다.** Apple 캘린더도, 앱 안의 캘린더 탭도 원장이 아니다.

```
앱 할 일        원장. 만들기·고치기·지우기가 전부 여기서만 일어난다
Apple 캘린더    선택적 출력. 실패해도 할 일은 남는다
캘린더 탭       읽기 전용 시점. 같은 원장을 다른 각도에서 볼 뿐이다
로컬 알림       원장에서 파생된 예약. 할 일이 바뀌면 통째로 다시 건다
```

두 곳에서 고칠 수 있게 만들면 "어느 쪽이 진짜인가"를 사용자도 코드도 답하지 못한다.

**마감 묶음** — 위에 있을수록 급하다. 순서는 `DueBucket` 선언 순서가 유일한 근거다.

```
지난 마감 → 오늘 → 앞으로 7일 → 그 뒤 → 날짜 없음 → 완료
```

시간이 명시된 할 일은 그 시각이 지나면 **같은 날이라도 지난 마감**이다.
날짜만 비교하면 "오후 2시 예약"이 오후 6시에도 오늘 할 일로 남는다.

**흐름은 셋이다** — 공유 → 등록 → 알림. 예전의 "앱 열기 → 확인" 두 단계를 없앴다.
확인을 버린 것은 아니다. 날짜가 모호하면 등록하지 않고 확인을 요청한다 (`AutoFilePolicy`).

**한 장에 일정이 여럿일 수 있다.** 예약 문자에 검진과 재방문이 같이 오거나, 공지에
접수 마감과 발표일이 함께 적힌다. 하나만 뽑으면 나머지를 사용자가 다시 입력해야 하고,
그러면 이 앱을 쓸 이유가 없다. 분석기는 언제나 `[TaskDraft]` 를 돌려준다.

**알림 세 종류** — 목적이 다르고 소유자도 다르다.

```
마감 알림  ReminderSchedule 이 계산 · LocalNotificationService 가 예약
  시간 지정 할 일   1시간 전 · 하루 전 20:00
  종일 할 일        당일 09:00 · 하루 전 20:00
  이미 지난 시각    걸지 않는다 (iOS가 버리거나 즉시 울린다 — 둘 다 고장으로 읽힌다)

등록 알림  CaptureNotice.postFiled · 새 흐름의 마지막 단계
  공유 직후        "언제 무슨 일정이 등록되었습니다"
  문구에 언제와 무엇이 다 들어간다 — 없으면 앱을 열어 확인해야 하고 단계를 줄인 의미가 없다

확인 요청  CaptureNotice 가 소유 · 식별자 앞에 "capture#"
  분석 실패·모호   확인이 필요한 것이 남았을 때만
  미확인 초안      앱을 나간 뒤 1시간
  앱이 앞에 있을 때  띄우지 않는다 (확인 화면이 이미 떠 있다)
```

---

## 작업 방식

| 단계 | 규칙 |
| --- | --- |
| **시작 전** | 베이스라인이 초록인지 확인한다 (`./scripts/verify.sh`) |
| **설계** | 코드를 쓰기 전에 되묻는다. 한 덩어리씩 확인받는다 |
| **계획** | 2~5분짜리 태스크로 쪼갠다. 파일·함수·검증 방법을 적는다 |
| **구현** | 계산·규칙이면 🔴 RED → 🟢 GREEN → 🔵 REFACTOR. **실패를 눈으로 본 뒤** 고친다 |
| **막힘** | 30분 넘으면 찍어보기를 멈추고 재현 → 좁히기 → 근본 원인 → 증명 |
| **완료** | 구현했다 ≠ 완료했다. **AC를 하나씩 짚고, 전체 스위트를 돌리고, 시뮬레이터에서 직접 눌러본다** |
| **보고** | 실패한 게 있으면 그대로 말한다. "아마 될 거예요" 금지 |

---

## Git · 커밋

- 기본 브랜치는 `main`이다
- Conventional Commits: `feat:` `fix:` `test:` `docs:` `refactor:` `chore:`
- **제목은 영문, 본문은 한글.** 제목은 명령형 소문자 72자 이내, 본문은 왜 그렇게 했는지를 적는다
- 한 커밋에 하나의 검토 가능한 관심사
- 생성물과 소스를 섞지 않는다. `build/`, `.xcodeproj`, 테스트 결과, 비밀 키는 커밋하지 않는다
- **커밋 기록에는 사람만 남는다.** AI 협업자 트레일러는 `.githooks/commit-msg` 가 지우고 CI가 강제한다

```
<type>(<scope>): <명령형 영문 소문자 요약>       ← 72자 이내
                                                ← 빈 줄
왜 그렇게 했는지를 한글로 적는다.
```

**PR 은 squash 로 병합한다. 그러면 PR 제목이 그대로 커밋 제목이 된다** —
그래서 PR 제목부터 위 형식으로 쓴다. 브랜치 안의 커밋을 하나하나 남기고 싶으면
merge 로 병합하되, 그 커밋들도 전부 이 형식이어야 한다.

**PR 본문과 커밋 메시지를 한 파일에 담지 않는다.** 구분자(`PRBODY` 같은)로 갈라
두면 squash 가 그 파일을 통째로 커밋 메시지로 삼는다. PR 본문 첫 줄이 제목이 되고
진짜 제목은 본문 속에 묻힌다 — 실제로 PR #2·#10·#12 가 이렇게 들어왔다.

```bash
git config core.hooksPath .githooks       # 한 번만. 훅이 형식을 검사한다
./.githooks/check-commit-format.sh <base>..<head>   # 직접 돌려 볼 때
```

---

## 문구

해요체. 사용자를 주어로. 기능 이름이 아니라 결과를 말한다.

| 쓴다 | 안 쓴다 |
| --- | --- |
| 담기 / 확인 | 캡처, 승인 |
| 마감 | 데드라인, 기한 |
| 지난 마감 | 연체, 미처리 |
| 확인할 할 일 | 대기열, 큐 |
| 분석이 찾은 근거 | 프롬프트 결과 |
| 담아 둔 스크린샷 | 원본 이미지 |

전체 사전: [`docs/05-IA.md §9`](docs/product/05-IA.md)

---

## 현재 상태

R0 실행 뼈대 + MVP 기능 + 접근성 완성 · **iOS 테스트 130건 · 백엔드 테스트 46건 · 빌드 경고 0**
공유 시트 → OCR → 분석 → 확인 → 할 일·캘린더·알림까지 이어진다.
macOS 는 물방울로 받고 사이드바 대시보드(마감 묶음 + 캘린더)로 본다 — [18장](docs/platform/18-MACOS.md).
다음: 실기기 서명·App Group 프로비저닝 · 실제 OpenAI 키 E2E · 중복 감지 정책
