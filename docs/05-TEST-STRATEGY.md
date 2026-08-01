# Test Strategy

## 위험 우선순위

| 등급 | 위험 | 게이트 |
| --- | --- | --- |
| P0 | 캡처 유실 | 저장/재시도 테스트 + 실제 기기 |
| P0 | 잘못된 날짜의 자동 캘린더 저장 | 신뢰도 경계 테스트 + 확인 UI |
| P0 | 캘린더 중복 생성 | event identifier + 재시도 테스트 |
| P1 | OCR 누락/오독 | 고정 평가셋 |
| P1 | 권한 거절 시 할 일도 유실 | EventKit 거절 수동 테스트 |
| P1 | 개인정보 로그 노출 | 서버/클라이언트 로그 검사 |
| P2 | 한국어 상대 날짜 오해 | timezone 고정 평가 |

## 테스트 레벨

- 순수 단위: 신뢰도, 날짜 상태, 중복, 상태 전이
- 서비스 계약: OCR fixture, 분석 JSON fixture, backend mock
- 통합: App Group enqueue/import/complete
- UI: 확인 화면, 권한 거절, 오류 복구
- 실제 기기: Share Extension, EventKit, 메모리

## 릴리스 게이트

- 전체 테스트 초록
- 경고 0
- P0 수동 시나리오 전부 통과
- 평가셋 날짜 정확도 95% 이상
- 제목 무수정 저장률 80% 이상
- API 키/원문 로그 없음

