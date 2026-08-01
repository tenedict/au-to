# CaptureTask

스크린샷을 iOS 공유 시트로 보내면 텍스트와 문맥을 분석해 앱 안의 할 일 후보를 만들고,
확인된 날짜/시간 항목은 Apple 캘린더에도 추가하는 개인 비서 앱입니다.

현재 단계는 R0 실행 뼈대입니다.

- 메인 앱 할 일 목록
- Share Extension 이미지 수집
- App Group inbox
- Apple Vision OCR 서비스
- 규칙 기반 문맥 분석기
- 사용자 확인 화면
- EventKit 캘린더 저장
- OpenAI/온디바이스 LLM 교체를 위한 서비스 프로토콜

```bash
xcodegen generate
xcodebuild -project CaptureTask.xcodeproj -scheme CaptureTask \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

제품 결정과 다음 순서는 [`docs/project-context.md`](docs/project-context.md)에서 시작합니다.

