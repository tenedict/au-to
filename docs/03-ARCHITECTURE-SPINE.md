# Architecture Spine

## 시스템 개요

```text
iOS Share Extension
  → App Group Inbox
  → Main App Importer
  → Vision OCR
  → ContextUnderstandingService
       ├─ RuleBased (R0)
       ├─ OpenAIBackend (MVP)
       └─ OnDeviceLLM (후속)
  → Review UI
  → TaskStore ──→ local persistence
              └─→ EventKit
```

## ADR

### ADR-1 · 하이브리드 AI

OCR은 Vision, 문맥 해석은 LLM으로 분리한다. 전체 이미지를 매번 서버에 보내지 않아도 되고,
OCR 평가와 의미 평가를 독립적으로 할 수 있다. Vision 원문과 필요한 경우 축소 이미지만 서버로 보낸다.

### ADR-2 · Share Extension은 수집 전용

Extension은 메모리·시간·수명 제약이 크다. 이미지 보관과 완료 안내만 맡기고
OCR, 긴 네트워크 요청, EventKit 권한 UI는 메인 앱에서 수행한다.

### ADR-3 · AI는 제안만 한다

일정 오인식은 실제 약속을 망가뜨린다. MVP는 확인 화면을 항상 거친다.
품질 데이터가 쌓인 뒤에도 낮은 신뢰도는 자동화를 금지한다.

### ADR-4 · API 키는 백엔드에만 둔다

iOS 바이너리와 Extension에 비밀 키를 포함하지 않는다. 앱은 사용자 인증이 적용된
우리 백엔드만 호출하고, 백엔드가 OpenAI Responses API를 호출한다.

### ADR-5 · 구조화 출력은 경계일 뿐 진실이 아니다

OpenAI Structured Outputs로 JSON Schema를 강제하되, 도메인 검증을 다시 수행한다.
스키마 준수는 날짜가 사실이라는 뜻이 아니다.

### ADR-6 · 앱 할 일과 캘린더 사본을 분리한다

앱 할 일이 원본이다. 캘린더 저장 실패는 앱 저장을 취소하지 않는다.
MVP에서는 캘린더 변경을 앱으로 역동기화하지 않는다.

## API 권장안

- 입력: OCR 텍스트, 로케일, 타임존, 현재 시각, 선택적 저해상도 이미지
- 출력: `docs/02-SPEC.md` JSON Schema
- `store: false`
- 요청별 익명 사용자 식별자와 rate limit
- 로그에는 원문/이미지를 기본 저장하지 않음
- 모델 ID는 서버 설정으로 교체

OpenAI Responses API는 이미지 입력과 구조화 출력을 지원한다. OCR처럼 세부 문자가 중요한
이미지 직접 분석은 지원 모델에서 원본 디테일을 사용한다. 다만 MVP 기본은 Vision OCR 텍스트다.

## 온디바이스 LLM 판단

첫 버전의 기본 엔진으로는 권하지 않는다.

- 장점: 오프라인, 개인정보, 호출비 0
- 단점: 앱 크기/메모리/발열, 구형 기기 편차, 한국어 날짜 추론 품질, 업데이트 난이도

먼저 OpenAI 기반으로 정확도 기준과 평가셋을 만든 뒤, 같은 프로토콜 아래 소형 모델을
shadow mode로 비교한다. 기준을 통과하면 로컬 기본 + 서버 fallback으로 전환한다.

