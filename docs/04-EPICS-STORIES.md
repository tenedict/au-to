# Epics & Stories

## E1 · 캡처 수집

- [x] S-1.1 Share Extension에서 단일 이미지 수집
- [x] S-1.2 App Group inbox에 원자적 저장
- [ ] S-1.3 실제 기기에서 공유 시트 노출/재시도 확인

## E2 · 텍스트와 문맥

- [x] S-2.1 Vision 한국어/영어 OCR
- [x] S-2.2 규칙 기반 Draft 생성
- [ ] S-2.3 익명화 평가셋 50건과 기대 JSON 작성
- [x] S-2.4 OpenAI backend adapter
- [ ] S-2.5 모호성/evidence 표시

## E3 · 할 일

- [x] S-3.1 확인 화면
- [x] S-3.2 로컬 목록/완료/삭제
- [ ] S-3.3 중복 감지
- [ ] S-3.4 검색/필터

## E4 · 캘린더

- [x] S-4.1 EventKit 쓰기 권한
- [x] S-4.2 일정 생성과 식별자 저장
- [ ] S-4.3 앱 수정 시 기존 일정 업데이트 정책
- [ ] S-4.4 일정 삭제 정책

## 다음 스토리: S-1.3

수용 기준:

1. 실제 iPhone 사진 앱 공유 시트에 “CaptureTask에 담기”가 보인다.
2. 공유 후 이미지/메타데이터가 App Group에 남는다.
3. 앱을 열면 OCR 후 확인 화면이 한 번만 보인다.
4. 앱 강제 종료/오프라인에서도 캡처가 사라지지 않는다.

## S-2.4 · OpenAI backend adapter

수용 기준:

1. iOS 앱이나 Share Extension에 OpenAI API 키가 포함되지 않는다.
2. `POST /v1/analyze-capture`는 OCR 원문, locale, timezone, 현재 시각을 받는다.
3. 서버는 Responses API와 strict JSON Schema로 TaskDraft를 반환한다.
4. `store: false`, 명시적인 모델·reasoning 설정을 사용한다.
5. 빈 원문, 과대 요청, OpenAI 오류, 잘못된 모델 응답을 구분해 반환한다.
6. API 키가 없는 서버는 시작 즉시 실패하고 원인을 설명한다.
7. 단위 테스트는 실제 OpenAI 호출 없이 요청 계약과 응답 파서를 검증한다.
