# 21 · API 명세서

> Whenly 분석 백엔드의 HTTP 인터페이스 규격.
> 버전 v1 · 최종 갱신 2026-08-02

관련 — [09-SPEC.md](09-SPEC.md) 계약 요약 · [`server/README.md`](../../server/README.md) 운영 · [`server/src/`](../../server/src) 구현

---

## 1. 개요

| 항목 | 값 |
| --- | --- |
| 기본 URL (로컬) | `http://127.0.0.1:8787` |
| 기본 URL (운영) | Cloud Run · asia-northeast3 (서울) |
| 프로토콜 | HTTP/1.1 · JSON |
| 문자 인코딩 | UTF-8 |
| 인증 | 공유 비밀 헤더 (§3) |
| 런타임 | Node 22 · `node:http` · 외부 패키지 0 |

이 서버가 존재하는 유일한 이유는 **OpenAI API 키를 앱 바깥에 두기 위해서**다
(ADR-5). 앱 번들에 넣은 문자열은 누구나 꺼낼 수 있다.

원본 스크린샷은 이 서버로 오지 않는다. OCR 은 기기에서 끝내고, **인식된 텍스트만**
전송된다 (NFR-PRIV-02).

---

## 2. 엔드포인트 목록

| 메서드 | 경로 | 인증 | 설명 |
| --- | --- | --- | --- |
| `GET` | `/health` | 불필요 | 상태 확인 |
| `POST` | `/v1/analyze-capture` | 필요 | 인식 텍스트를 할 일 초안으로 변환 |

그 밖의 경로·메서드는 `404 not_found` 를 반환한다.

---

## 3. 인증

### 3.1 헤더

| 항목 | 값 |
| --- | --- |
| 헤더 이름 | `X-Whenly-Key` (옛 이름 `X-CaptureTask-Key` 도 받습니다) |

> **앱과 서버는 함께 배포되지 않습니다.** 그래서 이름을 바꿀 때는 옛 것을 함께 받는
> 기간을 반드시 둡니다 — 앱만 새 이름을 보내면 아직 옛 빌드가 도는 서버가 401 을 주고,
> 사용자는 방금 업데이트한 앱에서 "앱을 업데이트해 주세요" 를 봅니다.
> 실제로 CaptureTask → Whenly 로 바꾸면서 이 사고가 났습니다.
> 지우는 순서가 **양쪽이 다릅니다.**
>
> | 앱이 옛 이름을 보내는 것 | 새 이름을 받는 서버가 배포된 뒤 지운다 → **2026-08-03 지웠습니다** |
> | 서버가 옛 이름을 받는 것 | 옛 이름으로 오는 요청이 없어진 뒤 지운다 → **아직 남깁니다** |
>
> 서버는 우리가 언제든 배포하지만 **기기에 이미 깔린 앱은 바꿀 수 없기** 때문입니다.
> 검사기 규칙 13 이 앱이 보내는 이름과 서버가 받는 이름의 짝을 대조합니다.
| 값 | 사전 공유 비밀 문자열 |
| 최소 길이 | 24자 |
| 비교 방식 | `crypto.timingSafeEqual` (길이가 다르면 먼저 거부) |
| 실패 응답 | `401 unauthorized` |

인증은 **본문을 읽기 전에** 수행한다. 인증되지 않은 요청으로 서버 메모리를
쓰지 않기 위해서다.

### 3.2 로컬 예외

`HOST` 가 `127.0.0.1` · `::1` · `localhost` 인 경우에만 키 없이 기동할 수 있다.
그 외의 주소에 바인딩하면서 키가 없으면 **서버가 기동을 거부한다.**

> "로컬은 예외" 규칙이 배포 환경으로 그대로 따라가는 것을 막기 위한 장치다.

### 3.3 기동 시 거부 조건

| 조건 | 결과 |
| --- | --- |
| 비루프백 바인딩 + 키 없음 | 기동 거부 |
| 키 길이 24자 미만 | 기동 거부 |
| 키가 `sk-` 로 시작 | 기동 거부 |

마지막 조건은 OpenAI 키를 클라이언트 키 자리에 잘못 넣는 사고를 막는다.
그 경우 백엔드를 둔 이유(ADR-5)가 통째로 무효가 된다.

### 3.4 위협 모델

이 비밀은 앱 번들을 분석하면 노출된다. 그 전제 위에서 채택한 방식이다.

| 그럼에도 유효한 이유 |
| --- |
| 노출되는 것이 OpenAI 키가 아니라 이 값이므로, 교체로 복구된다 |
| 노출 전까지 무작위 스캐너와 크롤러를 차단한다 |
| 노출 이후에도 요청 한도(§4)가 금액 피해를 제한한다 |

정식으로 앱만 통과시키려면 App Attest 가 필요하며, MVP 범위 밖이다.

---

## 4. 요청 한도

| 범위 | 한도 | 근거 |
| --- | --- | --- |
| 클라이언트 IP 당 | 10 회 / 분 | 사람이 스크린샷을 담는 속도를 크게 상회한다 |
| 인스턴스 전체 | 500 회 / 일 | **금액 상한** |

클라이언트 식별은 `X-Forwarded-For` 의 첫 번째 주소를 사용한다 (Cloud Run 프록시 뒤).

초과 시 `429 rate_limited` 와 함께 `Retry-After` 헤더(초)를 반환한다.

---

## 5. `GET /health`

### 요청

```http
GET /health HTTP/1.1
```

### 응답 `200`

```json
{ "status": "ok" }
```

인증 밖에 둔다. Cloud Run 의 상태 확인이 키를 알지 못하며, 이 응답은 어떤 정보도
노출하지 않는다.

---

## 6. `POST /v1/analyze-capture`

인식된 텍스트를 분석해 **할 일 초안 배열**을 반환한다.

### 6.1 요청

```http
POST /v1/analyze-capture HTTP/1.1
Content-Type: application/json
X-Whenly-Key: <공유 비밀>
```

```json
{
  "recognized_text": "8월 12일 오후 3시 정기검진 예약이 확정되었습니다.",
  "locale": "ko-KR",
  "timezone": "Asia/Seoul",
  "now": "2026-08-02T12:00:00+09:00"
}
```

| 필드 | 타입 | 필수 | 기본값 | 제약 |
| --- | --- | --- | --- | --- |
| `recognized_text` | string | **예** | — | 공백만이면 거부 · 50,000자 이하 |
| `locale` | string | 아니오 | `ko-KR` | 40자 이하 |
| `timezone` | string | 아니오 | `Asia/Seoul` | 80자 이하 |
| `now` | string | 아니오 | 서버 현재 시각 | ISO 8601 · 80자 이하 |

본문 전체 크기는 **128 KB** 를 초과할 수 없다.

> `now` 를 클라이언트가 보내는 이유 — "다음 주 화요일" 같은 상대 날짜는 기준
> 시점이 있어야 해석된다. 서버 시각을 쓰면 기기와 어긋날 수 있다.

### 6.2 응답 `200`

```json
{
  "tasks": [
    {
      "title": "정기검진 방문",
      "notes": "8월 12일 오후 3시 정기검진 예약이 확정되었습니다.",
      "due_at": "2026-08-12T15:00:00+09:00",
      "has_explicit_time": true,
      "confidence": 1.0,
      "evidence": ["8월 12일 오후 3시", "정기검진 예약이 확정"],
      "ambiguities": []
    }
  ]
}
```

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `title` | string | 실행 가능한 한국어 제목. 120자 이하 |
| `notes` | string | 해당 할 일의 원문 맥락. 4,000자 이하 |
| `due_at` | string \| null | 오프셋을 포함한 ISO 8601. 날짜가 없으면 `null` |
| `has_explicit_time` | boolean | 원문에 구체적 시각이 있을 때만 `true` |
| `confidence` | number | 0 이상 1 이하 |
| `evidence` | string[] | 근거가 된 원문 구절. 최대 8개 · 각 300자 이하 |
| `ambiguities` | string[] | 사용자가 직접 확인해야 하는 모호점. 최대 8개 |

**한 장에서 최대 8건**까지 반환한다.

> 한 장에 일정이 여럿일 수 있다. 예약 확정 문자에 검진과 재방문이 함께 오거나,
> 공지 하나에 접수 마감과 발표일이 같이 적힌다. 하나만 반환하면 나머지를 사용자가
> 다시 입력해야 하고, 그러면 이 제품을 쓸 이유가 없다.

### 6.3 `ambiguities` 의 의미

이 필드는 단순 참고 정보가 아니라 **동작을 결정한다.**

macOS 앱은 `ambiguities` 가 비어 있으면 사용자 확인 없이 캘린더에 등록한다
(`AutoFilePolicy`). 따라서

- 모호한데 비어 있으면 → 잘못된 일정이 조용히 등록된다
- 분명한데 채워져 있으면 → 사용자는 "날짜가 분명한데 왜 또 묻는가"를 겪는다

두 방향 모두 평가셋에서 측정한다 ([19-EVAL.md](19-EVAL.md)).

### 6.4 서버 측 검증

OpenAI Structured Outputs 는 **모양(type)만** 강제한다. `strict: true` 는 지원
키워드가 제한적이어서 `maxLength` · `minimum` 같은 범위 제약을 넣으면 모델·버전에
따라 400 으로 거절당하고, 그러면 분석이 통째로 실패한다.

그래서 **범위는 서버가 직접 확인하고 다듬는다.**

| 항목 | 처리 |
| --- | --- |
| `title` 120자 초과 | 잘라낸다 |
| `notes` 4,000자 초과 | 잘라낸다 |
| `confidence` 범위 밖 | 0~1 로 클램프 |
| `evidence` · `ambiguities` 8개 초과 | 잘라낸다 |
| `due_at` 파싱 불가 | `null` 로 낮추고 모호점에 기록 |

> 구조화 출력은 **경계일 뿐 진실이 아니다** (ADR-6). 받은 뒤에도 검증한다.

---

## 7. 오류 응답

모든 오류는 동일한 형식이다.

```json
{ "error": { "code": "invalid_request", "message": "recognized_text가 필요합니다." } }
```

| 상태 | `code` | 발생 조건 |
| --- | --- | --- |
| `400` | `invalid_request` | 빈 `recognized_text` · 해석 불가 JSON · 길이 초과 |
| `401` | `unauthorized` | 키 없음 · 키 불일치 |
| `404` | `not_found` | 정의되지 않은 경로·메서드 |
| `413` | `payload_too_large` | 본문 128 KB 초과 |
| `429` | `rate_limited` | 요청 한도 초과 **또는** OpenAI 한도 초과 |
| `502` | `analysis_failed` | OpenAI 오류 · 연결 실패 · 응답 검증 실패 |
| `504` | `upstream_timeout` | OpenAI 응답 15초 초과 |

### 7.1 업스트림 상태를 그대로 전달하지 않는다

OpenAI 의 `401` 을 그대로 내보내면 앱이 **사용자 잘못으로 오해**하게 만든다.
앱이 알아야 하는 것은 "다시 시도해도 되는가" 하나뿐이므로, 업스트림 오류는
`502` · `429` · `504` 중 하나로 매핑한다.

### 7.2 타임아웃 예산

시간이 흐르는 방향으로 짧아진다. 안쪽이 더 길면 바깥쪽이 먼저 끊기고, 안쪽 작업은
아무도 결과를 기다리지 않는 채 계속 돈다.

```
iOS URLRequest.timeoutInterval   20초
  └ backend → OpenAI              15초   (REQUEST_TIMEOUT_MS)
```

---

## 8. 환경 변수

| 이름 | 필수 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `OPENAI_API_KEY` | **예** | — | 이 서버에만 존재한다 |
| `OPENAI_MODEL` | 아니오 | `gpt-4.1-mini` | 프로젝트 규칙 10 이 실재 여부를 검사 |
| `WHENLY_CLIENT_KEY` | 조건부 | — | 비루프백 바인딩 시 필수 (§3.2). Cloud Run 에서는 `CAPTURETASK_CLIENT_KEY` 시크릿이 이 이름으로 주입됩니다 |
| `HOST` | 아니오 | `127.0.0.1` | |
| `PORT` | 아니오 | `8787` | |
| `REQUEST_TIMEOUT_MS` | 아니오 | `15000` | |

추론 계열 모델(`gpt-5*` · `o*`)을 지정하면 `reasoning` · `verbosity` 파라미터가
자동으로 함께 전송된다.

---

## 9. 프라이버시

| 항목 | 처리 |
| --- | --- |
| 원본 스크린샷 | **전송되지 않는다.** OCR 은 기기에서 끝난다 |
| OpenAI 호출 | `store: false` — 원문이 OpenAI 에 보존되지 않는다 |
| 서버 로그 | 인식 원문을 기본적으로 기록하지 않는다 |
| 영속 저장소 | **없다.** 이 서버는 상태를 갖지 않는다 |

---

## 10. 호출 예시

```bash
curl -X POST http://127.0.0.1:8787/v1/analyze-capture \
  -H 'Content-Type: application/json' \
  -H "X-Whenly-Key: $WHENLY_CLIENT_KEY" \
  -d '{
    "recognized_text": "다음 주 화요일까지 서류 제출해 주세요",
    "locale": "ko-KR",
    "timezone": "Asia/Seoul",
    "now": "2026-08-02T12:00:00+09:00"
  }'
```

---

## 11. 검증

| 대상 | 위치 |
| --- | --- |
| HTTP 계약 · 오류 매핑 | [`server/test/app.test.mjs`](../../server/test) |
| 인증 | [`server/test/auth.test.mjs`](../../server/test) |
| 요청 한도 | [`server/test/rate-limit.test.mjs`](../../server/test) |
| 스키마 · 클램프 · 모델 분기 | [`server/test/openai-client.test.mjs`](../../server/test) |
| 앱 쪽 파싱·오류 매핑 | [`tests/swift/BackendContextUnderstandingServiceTests.swift`](../../tests/swift) |

```bash
cd server && npm test        # 46건 · 실제 OpenAI 호출 없음
```

분석 **품질** 측정은 별도다 — [19-EVAL.md](19-EVAL.md). 실제 OpenAI 를 호출하므로
요금이 발생하며 `verify.sh` 에 포함하지 않는다.
