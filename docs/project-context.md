# CaptureTask — Project Context

## 무엇을 만드는가

iPhone 스크린샷을 공유 시트에서 CaptureTask로 보내면:

1. Share Extension이 원본을 App Group inbox에 안전하게 넣는다.
2. 메인 앱이 Apple Vision OCR로 텍스트를 로컬 추출한다.
3. 문맥 분석기가 할 일 제목·메모·날짜·시간·신뢰도를 제안한다.
4. 사용자가 확인한다.
5. 앱 내부 할 일에는 항상 저장하고, 선택 시 Apple 캘린더에도 저장한다.

## 현재 제품 결정

- 앱 안에 독립적인 할 일 목록이 있다.
- 캘린더는 동기화 원장이 아니라 선택적 외부 출력이다.
- OCR은 온디바이스 Apple Vision이 기본이다.
- 문맥 해석은 초기 OpenAI API, 이후 온디바이스 모델을 대체 가능하게 둔다.
- OpenAI 호출은 앱이 아닌 작은 백엔드가 담당한다.
- 첫 버전은 AI가 직접 쓰지 않고 반드시 확인 화면을 거친다.
- Share Extension은 수집만 담당한다. OCR/LLM/EventKit의 주 실행 위치는 메인 앱이다.

## 기술 스택

- Swift 5 mode / SwiftUI / iOS 17+
- ObservableObject 기반 Store
- EventKit
- Vision
- App Group 파일 inbox
- XcodeGen
- 외부 패키지 0

## 코드 지도

```text
CaptureTask/
  Models/       순수 도메인 값
  Services/     OCR·문맥 분석·캘린더 어댑터
  Shared/       앱/Extension 공유 inbox
  Store/        상태·영속화·유스케이스 조율
  Views/        목록·확인 UI
CaptureTaskShare/
CaptureTaskTests/
```

## 지금 되는 것

- 텍스트를 붙여 넣어 규칙 기반 분석
- 날짜 후보/신뢰도 확인
- 앱 할 일 저장/완료/삭제
- 선택한 할 일의 EventKit 저장
- 스크린샷 공유 Extension 수집
- 메인 앱 재진입 시 Vision OCR 및 확인 초안 생성

## 다음 할 일

1. 실제 기기 서명과 App Group 식별자 확정
2. Share Extension 실제 기기 E2E 검증
3. OCR/문맥 평가용 익명화 스크린샷 50장 확보
4. 백엔드 `/v1/analyze-capture`와 OpenAI Structured Outputs 어댑터
5. 중복 감지와 캘린더 수정/삭제 정책
