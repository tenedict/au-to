# SPEC

## 도메인 계약

### AssistantTask

- `title`: 비어 있을 수 없다.
- `dueDate`: 없을 수 있다.
- `hasExplicitTime`: `dueDate == nil`이면 반드시 false다.
- `confidence`: 0...1.
- `sourceCaptureID`: 재시도 중복 방지를 위해 원본 캡처 식별자를 유지한다.
- `calendarEventIdentifier`: EventKit 저장이 성공한 뒤에만 기록한다.

### TaskDraft

- 날짜 없음 또는 `confidence < 0.80`이면 `needsDateConfirmation == true`.
- 확인되지 않은 Draft는 캘린더에 저장할 수 없다.

### PendingCapture

- 메타데이터와 이미지가 한 쌍이다.
- 할 일 저장 성공 전에는 삭제하지 않는다.
- 재시도는 같은 `captureID`로 중복 Draft를 만들지 않는다.

## 문맥 분석 출력 계약

백엔드/온디바이스 모델은 동일한 의미를 반환해야 한다.

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

서버 JSON Schema가 맞더라도 앱은 `confidence`, 날짜 범위, 빈 제목을 다시 검증한다.

### HTTP

- `POST /v1/analyze-capture`
- 요청: `recognized_text`, `locale`, `timezone`, `now`
- 응답: 위 문맥 분석 출력 계약
- 400: 잘못된 요청
- 429: OpenAI rate limit
- 502: OpenAI 또는 응답 검증 실패
- iOS 기본 개발 주소: `http://127.0.0.1:8787`
- 배포 주소는 `CAPTURETASK_API_BASE_URL` 빌드 설정/환경변수로 주입한다.

## 쓰기 규칙

- 앱 할 일 저장과 캘린더 저장은 별도 결과다.
- 캘린더 실패 시 앱 할 일을 롤백하지 않는다.
- EventKit 중복 저장 방지를 위해 식별자를 영속화한다.
- 원본 캡처 삭제는 앱 할 일 저장 성공 뒤에만 한다.
