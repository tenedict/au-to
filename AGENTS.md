# CaptureTask 작업 규칙

스크린샷을 공유하면 온디바이스 OCR과 문맥 분석으로 앱 할 일을 만들고,
사용자 확인 후 Apple 캘린더에도 저장하는 iOS 개인 비서 앱이다.

자세한 제품 맥락은 `docs/project-context.md`, 개발 규율은
`docs/07-ENGINEERING-PLAYBOOK.md`를 먼저 읽는다.

## 빌드 · 테스트

```bash
xcodegen generate
xcodebuild -project CaptureTask.xcodeproj -scheme CaptureTask \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcodebuild test -project CaptureTask.xcodeproj -scheme CaptureTask \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO
```

## 구조

```text
View → Store → Service protocol → Platform/API adapter
             ↘ pure domain model
Share Extension → App Group inbox → Main app import
```

의존 방향을 거꾸로 만들지 않는다. 모델은 Store·View·EventKit·Vision을 모른다.

## 반드시 지킬 것

1. AI 결과는 제안이다. 앱 할 일 또는 캘린더에 쓰기 전 사용자가 확인한다.
2. `confidence < 0.80` 또는 날짜가 모호하면 자동 캘린더 저장을 금지한다.
3. OpenAI API 키를 앱이나 Share Extension에 넣지 않는다. 반드시 백엔드를 거친다.
4. 원본 스크린샷은 기본적으로 로컬에만 두고, 분석이 끝나면 보존 여부를 사용자가 결정한다.
5. Share Extension은 수집에 집중한다. 긴 네트워크 요청과 EventKit 쓰기를 넣지 않는다.
6. 캘린더 권한 거절은 앱 할 일 저장을 막지 않는다.
7. AI/캘린더 실패로 캡처를 잃지 않는다. App Group inbox는 성공 확인 전 삭제하지 않는다.
8. 날짜 파싱·중복 방지·상태 전이는 순수 함수와 테스트로 먼저 고정한다.
9. 비활성 컨트롤에는 이유를 함께 보여준다.
10. 색만으로 상태를 전달하지 않고, 인터랙티브 요소에 접근성 레이블을 붙인다.
11. 화면 파일은 500줄 이내로 유지한다.
12. 완료 보고 전에 전체 빌드와 테스트를 직접 실행한다.

## 작업 방식

- 코드 전: 스토리와 수용 기준을 먼저 고정한다.
- 계획: 파일·함수·검증 방법이 있는 2~5분 태스크로 쪼갠다.
- 규칙 변경: RED → GREEN → REFACTOR.
- 완료: 수용 기준 확인 + 전체 테스트 + 시뮬레이터 수동 확인.
- 문서와 코드가 어긋나면 둘 중 하나를 즉시 고친다.

## Git · 커밋

- 기본 브랜치는 `main`이다.
- 커밋 메시지는 Conventional Commits를 따른다:
  `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`.
- 제목은 명령형 영문 소문자로 쓰고 72자 이내로 유지한다.
- 한 커밋에는 하나의 검토 가능한 관심사만 담는다.
- 생성물과 소스를 섞지 않는다. `build/`, 테스트 결과, 비밀 키는 커밋하지 않는다.
- 관련 테스트가 초록일 때만 커밋한다.
- 푸시 전 전체 테스트와 빌드를 다시 실행한다.
