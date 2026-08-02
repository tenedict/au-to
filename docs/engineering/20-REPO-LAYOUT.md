# 20 · 저장소 구조

무엇이 어디에 있고, **플랫폼이 하나 더 붙을 때 어디에 무엇을 더하는지**.

관련 — [10-ARCHITECTURE-SPINE.md](10-ARCHITECTURE-SPINE.md) 의 ADR · [`../../CLAUDE.md`](../../CLAUDE.md)

---

## 1. 한 장

```
apps/                 플랫폼별 앱 — 화면은 여기서만 갈린다
  ios/
    App/              진입점 · Info.plist
    Views/            SwiftUI
    Resources/        Assets.xcassets
    Share/            공유 확장 (별도 타깃)
  macos/
    App/ Views/ Windows/ Resources/ Share/

core/                 플랫폼이 공유하는 것
  swift/              iOS·macOS 앱과 두 확장이 **전부** 쓴다
    Models/           순수 값 · 순수 함수 ← Foundation 말고는 아무것도 import 하지 않는다
    Services/         플랫폼 · 네트워크 어댑터
    Store/            상태 · 영속화 · 유스케이스 조율
    Shared/           앱 ↔ 확장 다리 (App Group inbox · 확인 요청 알림)

server/               모든 플랫폼이 부르는 단 하나의 백엔드 (Node 22 · 외부 패키지 0)
tests/swift/          core/swift 의 계산·저장 테스트
config/apple/         entitlements 4개 · Secrets.xcconfig (커밋 안 됨)
docs/                 product/ · engineering/ · platform/ · plans/
scripts/              verify · 규칙 검사 · 문서 링크 검사 · 배포 · 시뮬레이터 선택
project.yml           XcodeGen 정의 — .xcodeproj 는 생성물이다
```

---

## 2. 왜 이렇게 나눴나

**화면만 플랫폼별로 갈린다.** 마감 묶음 분류, 알림 시각 계산, 월 격자, 저장 형식,
백엔드 호출은 iOS 와 macOS 가 글자 하나까지 같은 코드를 쓴다. 그것들을 앱 폴더 안에
두면 "이 파일이 iOS 전용인가 macOS 도 쓰는가"를 파일 이름으로는 알 수 없다.
실제로 그런 상태였고, 그래서 `core/` 를 갈라냈다.

**`core/swift` 의 `swift` 는 우연이 아니다.** 나중에 Kotlin 이나 C# 으로 같은 계산을
다시 써야 하면 `core/kotlin/` 이 형제로 들어온다. 그때 `core/` 를 통째로 옮기지 않아도 된다.

**`server/` 는 `apps/` 밖에 있다.** 서버는 어느 한 앱의 것이 아니다. `apps/ios/backend`
같은 자리에 두면 안드로이드가 붙는 날 "왜 iOS 폴더 안의 서버를 부르지" 가 된다.

**`config/apple/`** — entitlements 와 xcconfig 는 애플 빌드에만 쓰인다.
Android 가 붙으면 `config/android/` 가 형제로 온다.

---

## 3. 의존 방향

```
apps/ios/Views          apps/macos/Views
       ↘                       ↙
          core/swift/Store
                ↓
          core/swift/Services  (프로토콜) → 플랫폼·API 어댑터
                ↓
          core/swift/Models    ← 아무것도 모른다
```

`core/swift/Models` 는 SwiftUI·UIKit·AppKit·EventKit·Vision·UserNotifications 를
모른다. 모르게 하는 것은 [규칙 6](../../scripts/check-project-rules.sh) 이 매번 확인한다.
모델이 화면을 알면 계산을 테스트하려고 화면을 띄워야 하고, 그러면 아무도 테스트하지 않게 된다.

---

## 4. 플랫폼을 하나 더 붙일 때

### 4-1. 같은 언어 (예: visionOS · watchOS)

1. `apps/visionos/` 에 `App/` `Views/` `Resources/` 를 만든다
2. `project.yml` 에 타깃을 더하고 `sources` 에 그 폴더들과 **`core/swift`** 를 적는다
3. `config/apple/CaptureTaskVision.entitlements` 를 더한다
4. `scripts/check-project-rules.sh` 맨 위 경로 묶음(`ALL_SWIFT`)에 새 폴더를 더한다
5. `verify.sh` 에 그 타깃 빌드를 더한다 — 공유 코드를 고쳤을 때
   **여기가 먼저 깨지는데 빌드하지 않으면 아무도 모른 채 초록이 난다**

`core/swift` 는 건드리지 않는다. 건드려야 한다면 그건 공유 코드가 아니었다는 뜻이다.

### 4-2. 다른 언어 (예: Android · Windows)

1. `apps/android/` — 그 플랫폼의 관례를 그대로 따른다 (Gradle 은 그 안에 둔다)
2. `core/kotlin/` — `core/swift/Models` 와 **같은 규칙**을 다시 구현한다.
   마감 묶음 순서, 알림 시각, 신뢰도 임계값이 플랫폼마다 다르면
   같은 스크린샷이 기기마다 다른 할 일이 된다
3. `tests/kotlin/` — `tests/swift` 와 **같은 경계값**을 검사한다.
   두 구현이 갈라지는 것은 테스트가 다를 때다
4. `config/android/`
5. `server/` 는 그대로 쓴다. 계약이 하나여야 결과가 하나다

> 두 번째 언어가 붙는 날, `server/src/task-draft-schema.mjs` 의 응답 계약을
> `contracts/` 로 꺼내는 것을 검토한다. 클라이언트가 하나일 때 미리 꺼내면
> 쓰지 않는 추상이 하나 늘 뿐이다.

### 4-3. 문서

`docs/platform/` 에 문서를 하나 더한다. 번호는 이어 붙인다 (21, 22 …).
폴더가 갈려도 읽는 순서는 하나여야 한다.

---

## 5. 경로를 아는 곳

구조를 바꾸면 **여기가 전부 따라 바뀌어야 한다.** 하나라도 남으면 그 검사는
빈손으로 훑고도 조용히 초록을 낸다.

| 파일 | 무엇을 안다 |
| --- | --- |
| `project.yml` | 타깃별 `sources` · `info.path` · `entitlements.path` · `configFiles` |
| `scripts/check-project-rules.sh` | 맨 위 경로 묶음 여섯 줄 — **다른 곳에는 경로를 적지 않는다** |
| `scripts/verify.sh` | swift-format 대상 · Secrets.xcconfig 위치 |
| `.swiftlint.yml` | `included` · `excluded` |
| `lefthook.yml` | swift-format 대상 · 서버 테스트 glob |
| `.gitignore` | `server/.env` · `config/apple/Secrets.xcconfig` |
| `.github/workflows/ci.yml` | `working-directory` |

규칙 검사기는 **자기 자신을 먼저 검사한다** (규칙 0) — 대상 디렉터리가 없거나
훑은 파일이 15개 미만이면 실패한다. 경로가 어긋난 채 통과하는 일을 막는 유일한 장치다.

---

## 6. 생성물은 커밋하지 않는다

| | 왜 |
| --- | --- |
| `CaptureTask.xcodeproj/` | `project.yml` 에서 만든다. 커밋하면 소스가 두 벌이 되고 pbxproj 안에서 충돌이 난다 |
| `build/` · `DerivedData/` | 사람마다 다르고 용량이 크다 |
| `config/apple/Secrets.xcconfig` | 배포 주소와 공유 비밀. 되돌려도 히스토리에 남는다 |
| `server/.env` | OpenAI 키 |

`.xcodeproj` 를 열기 전에 언제나 `xcodegen generate`. `verify.sh` 가 자동으로 부른다.
