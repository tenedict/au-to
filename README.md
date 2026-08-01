# CaptureTask

스크린샷을 iOS 공유 시트로 보내면 텍스트와 문맥을 분석해 앱 안의 할 일 후보를 만들고,
확인된 날짜/시간 항목은 Apple 캘린더에도 추가하는 개인 비서 앱입니다.

현재 단계는 R0 실행 뼈대 완료, 실기기 MVP 준비입니다.

- 메인 앱 할 일 목록
- Share Extension 이미지 수집
- App Group inbox
- Apple Vision OCR 서비스
- OpenAI Responses API 문맥 분석기
- 사용자 확인 화면
- EventKit 캘린더 저장
- OpenAI/온디바이스 LLM 교체를 위한 서비스 프로토콜

## OpenAI 백엔드

OpenAI API 키는 iOS 앱에 넣지 않습니다. 로컬 백엔드에서만 환경변수로 읽습니다.

```bash
cd backend
cp .env.example .env
# .env의 OPENAI_API_KEY 값을 설정한 뒤
set -a
source .env
set +a
npm start
```

서버 기본 주소는 `http://127.0.0.1:8787`이며 기본 모델은
구조화 추출 역할에 맞춘 `gpt-5.6-luna`입니다.

```bash
cd backend
npm test
```

```bash
xcodegen generate
xcodebuild -project CaptureTask.xcodeproj -scheme CaptureTask \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

## 개발 기획서

- [통합 HTML 기획서](docs/CaptureTask-Development-Plan.html): 제품, UX, 기능 요구사항,
  아키텍처, OpenAI/API, 개인정보, 비용, 테스트, 배포, 로드맵을 한 문서로 정리했습니다.
- [PDF 기획서](output/pdf/CaptureTask-Development-Plan.pdf): 공유와 인쇄용 A4 문서입니다.
- [통합 원문](docs/08-INTEGRATED-DEVELOPMENT-PLAN.md): HTML/PDF 생성의 기준 문서입니다.

제품 결정과 다음 순서는 [`docs/project-context.md`](docs/project-context.md)에서 시작합니다.
