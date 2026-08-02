# CaptureTask 백엔드

**OpenAI API 키가 존재하는 유일한 곳입니다.**

iOS 앱과 Share Extension 에는 키가 들어가지 않습니다. 앱 번들의 문자열은 누구나 꺼낼 수
있기 때문입니다 (ADR-5). 앱은 이 서버만 부르고, 이 서버가 OpenAI 를 부릅니다.

---

## 1. API 키를 어디에 넣나

### 넣는 곳 — `backend/.env` 한 곳뿐입니다

```bash
cd backend
cp .env.example .env
```

`.env` 를 열어 **첫 줄만** 실제 값으로 바꿉니다.

```dotenv
OPENAI_API_KEY=sk-proj-여기에-실제-키   ← 여기만 채우면 됩니다

OPENAI_MODEL=gpt-4.1-mini              ← 그대로 두어도 됩니다
HOST=127.0.0.1
PORT=8787
```

### 실행

```bash
set -a; source .env; set +a
npm start
```

```
CaptureTask backend listening on http://127.0.0.1:8787
OpenAI model: gpt-4.1-mini
```

### 넣으면 안 되는 곳

| | 왜 |
| --- | --- |
| `project.yml` · `Info.plist` | 앱 번들에 그대로 들어갑니다 |
| Swift 소스 어디든 | 〃. 프로젝트 규칙 2 가 `sk-`·`OPENAI_API_KEY`·`api.openai.com` 을 막습니다 |
| `.env.example` | 커밋되는 파일입니다. 자리표시자만 둡니다 |
| 셸 히스토리 (`export OPENAI_API_KEY=...`) | `~/.zsh_history` 에 남습니다 |

`.env` 는 `.gitignore` 에 있습니다. 커밋되지 않습니다.

### 자리표시자 방어

`sk-proj-replace-me` 를 그대로 둔 채 켜면 **시작 즉시 멈춥니다.**

```
OPENAI_API_KEY가 아직 자리표시자입니다. backend/.env에 실제 키를 넣어 주세요.
```

이걸 막지 않으면 첫 호출에서 401 이 나고, 원인은 서버 로그에만 남습니다.

---

## 2. 구조

```
backend/
├─ Dockerfile                Cloud Run 용. 외부 패키지가 0개라 소스만 복사한다
├─ src/
│  ├─ server.mjs             켜는 자리 — 환경변수 읽기 · 조립 · listen
│  ├─ app.mjs                HTTP 계층 — 라우팅 · 인증 · 한도 · 검증 · 오류 매핑
│  ├─ auth.mjs               공유 비밀 검사 (timingSafeEqual)
│  ├─ rate-limit.mjs         IP 당 분당 · 인스턴스 당 하루
│  ├─ openai-client.mjs      OpenAI 호출 — 요청 조립 · 타임아웃 · 응답 파싱
│  └─ task-draft-schema.mjs  스키마 + 범위 검증/다듬기
└─ test/                     46건 — 실제 OpenAI 호출 없음
```

**외부 패키지가 0개입니다.** `node:http` 와 내장 `fetch` 만 씁니다.
그래서 `npm install` 도, lockfile 도 없습니다.

### 층이 나뉜 이유

| 층 | 아는 것 | 모르는 것 |
| --- | --- | --- |
| `server.mjs` | 환경변수, 포트 | HTTP 세부, OpenAI |
| `app.mjs` | HTTP, 상태 코드 | **OpenAI 를 모릅니다** — `analyzeCapture` 함수를 주입받습니다 |
| `openai-client.mjs` | OpenAI 와이어 포맷 | HTTP 서버, 라우팅 |
| `task-draft-schema.mjs` | 계약과 한계값 | 나머지 전부 |

`app.mjs` 가 OpenAI 를 모르기 때문에 **HTTP 테스트가 실제 호출 없이 돕니다.**
대역 함수를 넣으면 끝입니다.

---

## 3. 요청이 흐르는 길

```
iOS 앱
  │ POST /v1/analyze-capture
  │ { recognized_text, locale, timezone, now }
  ▼
app.mjs
  │ ① 본문 128KB 이하인가          → 아니면 413
  │ ② recognized_text 가 있는가     → 없으면 400
  │ ③ 50,000자 이하인가            → 넘으면 400
  ▼
openai-client.mjs
  │ ④ 요청 조립 (store:false, strict json_schema)
  │    추론 계열이면 reasoning·verbosity 추가
  │ ⑤ POST https://api.openai.com/v1/responses  (타임아웃 15초)
  ▼
task-draft-schema.mjs
  │ ⑥ output_text 를 JSON 으로
  │ ⑦ 모양 검증 → 틀리면 거절
  │ ⑧ 길이 클램프 → 넘치면 자름
  ▼
iOS 앱  { title, notes, due_at, has_explicit_time, confidence, evidence, ambiguities }
  │
  └─ ⑨ 앱이 **다시 한 번** 검증합니다. 스키마 준수는 날짜가 사실이라는 뜻이 아닙니다
```

### ⑦과 ⑧이 다른 이유

- **모양이 틀린 것은 거절합니다** — 날짜 없이 시간만 있는 결과는 앱이 표현할 수 없습니다
- **길이만 넘친 것은 자릅니다** — 제목이 한 글자 길다고 분석 전체를 버리면 사용자만 손해입니다

---

## 4. 엔드포인트

### `POST /v1/analyze-capture`

```bash
curl -X POST http://127.0.0.1:8787/v1/analyze-capture \
  -H 'Content-Type: application/json' \
  -d '{
    "recognized_text": "8월 12일 오후 3시 강남점 방문 예약이 확정되었습니다",
    "locale": "ko-KR",
    "timezone": "Asia/Seoul",
    "now": "2026-08-01T19:00:00+09:00"
  }'
```

| 필드 | 필수 | 기본값 |
| --- | --- | --- |
| `recognized_text` | ✅ | — |
| `locale` | | `ko-KR` |
| `timezone` | | `Asia/Seoul` |
| `now` | | 서버 현재 시각 |

> `timezone` 과 `now` 가 틀리면 **하루가 통째로 밀립니다.** "내일 3시"의 해석은
> 기기 타임존에 달려 있고, 서버가 그걸 알 방법은 요청 본문뿐입니다.

**응답 (200)**

```json
{
  "title": "강남점 방문 예약 확인",
  "notes": "8월 12일 오후 3시 강남점 방문 예약이 확정되었습니다",
  "due_at": "2026-08-12T15:00:00+09:00",
  "has_explicit_time": true,
  "confidence": 0.94,
  "evidence": ["8월 12일 오후 3시", "강남점"],
  "ambiguities": []
}
```

### `GET /health`

```bash
curl http://127.0.0.1:8787/health   # {"status":"ok"}
```

---

## 5. 오류

```json
{ "error": { "code": "analysis_failed", "message": "..." } }
```

| 상태 | `code` | 언제 | 앱이 보여주는 말 |
| --- | --- | --- | --- |
| 400 | `invalid_request` | 빈 원문, 해석 불가 JSON | "스크린샷 내용을 분석 요청으로 보낼 수 없어요." |
| 401 | `unauthorized` | 클라이언트 키 없음·틀림 | "이 앱이 분석 서버를 쓸 수 없어요. 앱을 업데이트해 주세요." |
| 404 | `not_found` | 없는 경로 | 〃 |
| 413 | `payload_too_large` | 본문 128KB 초과 | 〃 |
| 429 | `rate_limited` | OpenAI 한도 **또는** 우리 요청 한도 | "요청이 많아요. 잠시 후 다시 시도해 주세요." |
| 502 | `analysis_failed` | OpenAI 오류·연결 실패·응답 검증 실패 | "OpenAI 분석 서버에 연결하지 못했어요. 캡처는 보관했어요." |
| 504 | `upstream_timeout` | OpenAI 응답 15초 초과 | 〃 |

**업스트림 상태를 그대로 흘리지 않습니다.** OpenAI 의 401 을 그대로 내보내면
앱이 사용자 잘못으로 오해하게 만듭니다. 앱은 "다시 시도해도 되는가"만 알면 됩니다.

### 타임아웃 예산

시간이 흐르는 방향으로 짧아집니다. 안쪽이 더 길면 바깥쪽이 먼저 끊기고,
안쪽 작업은 아무도 결과를 기다리지 않는 채 계속 돕니다.

```
iOS URLRequest.timeoutInterval   20초
  └ backend → OpenAI              15초   (REQUEST_TIMEOUT_MS)
```

---

## 6. 모델

`OPENAI_MODEL` 로 바꿉니다. 기본은 `gpt-4.1-mini` 입니다.

```js
// openai-client.mjs
export function isReasoningModel(model) {
  return /^(gpt-5|o[1-9])/.test(model ?? "");
}
```

| 모델군 | 붙는 파라미터 |
| --- | --- |
| `gpt-4.1*` · `gpt-4o*` | 없음 |
| `gpt-5*` · `o*` | `reasoning: { effort: "minimal" }` · `text.verbosity: "low"` |

**분기가 필요한 이유** — 추론 파라미터를 gpt-4.1 계열에 보내면 400 입니다.
반대로 추론 모델에서 빼면 기본 추론량이 붙어 느려지고 비싸집니다.

> **모델 이름을 바꿀 때는 `scripts/check-project-rules.sh` 의 `KNOWN_MODELS` 에도 더해야 합니다.**
> 검사기는 OpenAI 의 모델 목록을 알 수 없어서 **정확 일치**로 봅니다.
> 접두사로 두면 `gpt-5.6-luna` 같은 존재하지 않는 이름이 `gpt-5` 로 시작한다는
> 이유로 통과합니다 — 실제로 이 프로젝트의 기본값이 한동안 그런 이름이었습니다.

### 스키마에 넣지 않는 것

`strict: true` 는 지원 키워드가 제한적입니다. `maxLength`·`minimum`·`maxItems` 를
스키마에 넣으면 모델/버전에 따라 400 으로 거절당하고, 분석이 통째로 실패합니다.
**범위는 `validateTaskDraft` 가 서버에서 확인합니다.**

---

## 7. 테스트

```bash
cd backend && npm test
```

46건 전부 **실제 OpenAI 호출 없이** 돕니다. `fetchImpl` 을 대역으로 바꿔 넣습니다.

| 무엇을 잡나 |
| --- |
| 요청에 `store: false` 와 strict 스키마가 있는가 |
| 기본 모델이 추론 계열이 아닌가 (파라미터 분기가 맞는가) |
| 스키마에 지원되지 않는 제약 키워드가 없는가 |
| 길이 초과를 버리지 않고 자르는가 |
| 날짜 없이 시간만 있는 결과를 거절하는가 |
| 429·타임아웃·연결 실패를 구분해 감싸는가 |
| 키 없는 요청을 401 로 막고, **분석 함수를 부르지 않는가** |
| 외부에 바인딩했는데 키가 없으면 **시작을 거부하는가** |
| 클라이언트 키에 OpenAI 키를 넣으려 하면 막는가 |
| 한도를 넘으면 429 와 `Retry-After` 를 주는가 |
| 하루 총량을 IP 를 바꿔 가며 넘을 수 없는가 |

> ⚠️ **실제 OpenAI 응답의 모양은 아직 확인하지 못했습니다** (`B-2`).
> `parseTaskDraftResponse` 가 `output[].content[].type === "output_text"` 를 가정하는데,
> 그 가정이 맞는지는 진짜 키로 한 번 불러 봐야 압니다.

---

## 8. 앱이 이 서버를 찾는 법

| 우선순위 | 어디 |
| --- | --- |
| 1 | 환경변수 `CAPTURETASK_API_BASE_URL` |
| 2 | `Info.plist` 의 `CAPTURETASK_API_BASE_URL` (`project.yml` 에서 주입) |
| 3 | `http://127.0.0.1:8787` |

| 상황 | 해야 할 일 |
| --- | --- |
| **시뮬레이터** | 없음. 맥의 네트워크를 그대로 쓰므로 `127.0.0.1` 이 맥의 localhost 입니다 |
| **실기기** | `.env` 의 `HOST=0.0.0.0` + `project.yml` 의 주소를 맥의 LAN IP 로 (`http://192.168.x.x:8787`) |
| **배포** | `./scripts/deploy-backend.sh` — 9장 |

평문 HTTP 는 `NSAppTransportSecurity.NSAllowsLocalNetworking` 으로 허용돼 있습니다.
개발용입니다.

---

## 9. 배포 (Cloud Run · 서울)

```bash
./scripts/deploy-backend.sh
```

스크립트가 준비물·비밀·API 를 순서대로 확인하고, **무엇이 빠졌는지 알려 줍니다.**
조용히 넘어가지 않습니다 — 반쯤 설정된 채로 배포되면 401 과 500 을 구분하지 못합니다.

### 처음 한 번

```bash
gcloud auth login
gcloud config set project <PROJECT_ID>

# OpenAI 키
printf '%s' "sk-proj-실제키" | \
  gcloud secrets create OPENAI_API_KEY --data-file=-

# 앱과 서버가 나눠 갖는 공유 비밀
printf '%s' "$(openssl rand -base64 32)" | \
  gcloud secrets create CAPTURETASK_CLIENT_KEY --data-file=-
```

### 배포 뒤 앱 연결

```bash
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # 없으면
gcloud secrets versions access latest --secret CAPTURETASK_CLIENT_KEY
```

`Config/Secrets.xcconfig` 에 주소와 비밀을 넣고 `xcodegen generate` 를 다시 돌립니다.
이 파일은 **커밋되지 않습니다** (프로젝트 규칙 11 이 검사합니다).

### 스크립트가 배포 뒤에 확인하는 것

| | |
| --- | --- |
| `/health` 가 200 인가 | 컨테이너가 실제로 떴는가 |
| **키 없는 요청이 401 인가** | 인증이 실제로 켜져 있는가 |

두 번째가 중요합니다. 비밀이 주입되지 않은 채 배포되면 서버는 정상으로 보이지만
**누구나 쓸 수 있는 상태**입니다. 스크립트가 그 경우 실패로 끝냅니다.

### 왜 `--allow-unauthenticated` 인가

"구글 IAM 인증을 요구하지 않는다"는 뜻입니다. 우리 인증은 그 위에서
`X-CaptureTask-Key` 헤더로 합니다. IAM 을 켜면 앱이 구글 토큰을 들고 다녀야 해서
이 제품에는 맞지 않습니다.

### 아직 없는 것

| # | 없는 것 | 근거 |
| --- | --- | --- |
| 1 | App Attest (진짜 기기 검증) | 공유 비밀은 앱 번들을 뜯으면 나옵니다 (SPEC H-3.2) |
| 2 | 요청 로그·비용 관측 | — |
| 3 | 인스턴스 간 공유 한도 | 메모리 기반이라 `--max-instances` 가 실제 상한입니다 (SPEC H-4.3) |

> **OpenAI 계정 쪽에도 사용량 한도를 걸어 두세요.** 마지막 방어선입니다.

---

## 관련 문서

| | |
| --- | --- |
| [`docs/09-SPEC.md`](../docs/09-SPEC.md) | 계약 (A · H 절) |
| [`docs/10-ARCHITECTURE-SPINE.md`](../docs/10-ARCHITECTURE-SPINE.md) | ADR-5 키 격리 · ADR-6 구조화 출력 |
| [`docs/03-SRS-비기능요구사항.md`](../docs/03-SRS-비기능요구사항.md) | 성능·프라이버시·보안 |
| [`docs/17-ONDEVICE-LLM-RESEARCH.md`](../docs/17-ONDEVICE-LLM-RESEARCH.md) | 이 서버를 언젠가 대체할 후보들 |
