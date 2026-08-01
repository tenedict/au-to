# CaptureTask

스크린샷을 iOS 공유 시트로 보내면 텍스트와 문맥을 분석해 할 일을 만들고,
마감이 다가오면 알려 주는 개인 비서 앱입니다.

```
스크린샷 → 공유 → 담기 → 앱 열기 → OCR → 분석 → 확인
  → 앱 할 일 · 마감 알림 · (선택) Apple 캘린더
```

| 항목 | 값 |
| --- | --- |
| 단계 | R0 PASS · **백엔드 배포됨** (Cloud Run 서울) · 실기기 확인 대기 |
| iOS 테스트 | 93 / 93 |
| 백엔드 테스트 | 15 / 15 |
| 프로젝트 규칙 | 11건 |
| 빌드 경고 | 0 |
| 외부 의존성 | 없음 (iOS · 백엔드 모두) |

---

## 무엇이 있나

- **지갑 스타일 마감 스택** — 지난 마감부터 급한 순으로 카드가 겹쳐 쌓이고, 누르면 펼쳐집니다
- **로컬 마감 알림** — 시간 지정은 1시간 전, 종일은 당일 09:00, 공통으로 하루 전 20:00
- **이번 달 캘린더** — 마감이 있는 날을 표시하는 읽기 전용 월 뷰
- **Share Extension** — 다른 앱에서 공유하면 뜹니다. 이미지 최대 10장을 한 번에 담습니다
- **앱 안에서 사진 고르기** — 사진 라이브러리에서 직접 골라도 됩니다 (권한 불필요)
- **분석 엔진 선택** — 설정에서 백엔드 / 규칙 기반 중 고릅니다. 온디바이스는 자리만 있습니다
- **온디바이스 Vision OCR** — 원본 이미지는 기기를 떠나지 않습니다
- **OpenAI 문맥 분석** — 키는 백엔드에만 있습니다
- **확인 화면** — AI 결과는 제안입니다. 여기를 지나지 않는 저장 경로는 없습니다
- **접근성** — 큰 글자에서는 겹침 대신 목록으로, 모션 줄이기·대비 높이기를 존중합니다
- **Apple 캘린더 연동** — 선택적 출력. 실패해도 할 일은 남습니다

---

## 시작하기

### 1. 백엔드 — **여기서 넣을 것은 API 키 한 줄뿐입니다**

```bash
cd backend
cp .env.example .env
# .env 를 열어 OPENAI_API_KEY 를 실제 값으로 바꿉니다. 나머지는 그대로 두어도 됩니다.

set -a; source .env; set +a
npm start
```

> 구조와 키를 넣는 곳은 [`backend/README.md`](backend/README.md)에 자세히 있습니다.

### 배포 (Cloud Run · 서울)

```bash
./scripts/deploy-backend.sh
```

배포 뒤 **키 없는 요청이 401 인지 직접 확인**합니다. 비밀이 주입되지 않은 채 배포되면
서버는 정상으로 보이지만 누구나 쓸 수 있는 상태라, 그 경우 스크립트가 실패로 끝냅니다.

기본 주소는 `http://127.0.0.1:8787`, 기본 모델은 `gpt-4.1-mini` 입니다.
추론 계열(`gpt-5*`, `o*`)을 넣으면 `reasoning`·`verbosity` 파라미터가 자동으로 함께 붙습니다.

```bash
cd backend && npm test        # 15건 · 실제 OpenAI 호출 없음
curl http://127.0.0.1:8787/health
```

### 2. iOS 앱

```bash
brew install xcodegen                                        # 최초 1회
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # 최초 1회
xcodegen generate                                            # .xcodeproj 는 생성물입니다
open CaptureTask.xcodeproj
```

`Secrets.xcconfig` 는 백엔드 주소와 공유 비밀이 들어가는 파일이라 커밋되지 않습니다.
기본값은 로컬 백엔드(`http://127.0.0.1:8787`)라 그대로 두고 시작해도 됩니다.
`./scripts/verify.sh` 는 없으면 자동으로 만들어 줍니다.

또는 명령줄에서:

```bash
xcodebuild -project CaptureTask.xcodeproj -scheme CaptureTask \
  -sdk iphonesimulator -destination "id=$(./scripts/select-simulator.sh)" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

### 3. 백엔드 없이 눌러 보기

```bash
SIMCTL_CHILD_CAPTURETASK_OFFLINE=1 \
  xcrun simctl launch --terminate-running-process booted com.example.capturetask
```

규칙 기반 분석기를 씁니다. **백엔드가 죽었다고 자동으로 여기로 떨어지지는 않습니다** —
조용한 품질 저하는 아무도 알아채지 못하기 때문입니다.

---

## 검증

```bash
./scripts/verify.sh          # 규칙 + 포맷 + 린트 + 백엔드 + iOS 테스트
./scripts/verify.sh --quick  # iOS 테스트 제외 (몇 초)
```

사람 · AI · Git Hook · CI 가 **모두 이 명령 하나**를 씁니다.

```bash
./scripts/check-project-rules.sh --list   # 이 프로젝트만의 규칙 목록
```

프로젝트 규칙은 전부 **실제로 한 번씩 사고를 낸 것**들입니다. 예를 들어 규칙 1은
App Group 식별자가 코드·`project.yml`·entitlements 두 파일에서 같은지 매번 대조합니다 —
이 값이 비어 있어 공유 시트 경로 전체가 죽은 채로 R0 을 통과한 적이 있기 때문입니다.

### Git Hook (선택)

```bash
brew install lefthook && lefthook install
```

커밋 전에 규칙·포맷·린트, 푸시 전에 전체 검증이 붙습니다.

---

## 실기기에서 쓰려면

공유 시트 경로는 **실기기에서만** 확인할 수 있습니다. App Group 프로비저닝이 필요합니다.

1. `project.yml` 의 `PRODUCT_BUNDLE_IDENTIFIER` 와 `DEVELOPMENT_TEAM` 을 본인 것으로 바꿉니다
2. 같은 파일의 `com.apple.security.application-groups` 값을 개발자 계정에 등록합니다
3. `CaptureTask/Shared/PendingCapture.swift` 의 `appGroupIdentifier` 도 같은 값으로 맞춥니다
4. `./scripts/check-project-rules.sh` 로 네 곳이 일치하는지 확인합니다
5. `CAPTURETASK_API_BASE_URL` 을 맥의 LAN 주소로 바꿉니다 (`http://192.168.x.x:8787`)

> 3번을 빠뜨리면 담기는 성공하고 **도착만 실패합니다.** 규칙 1이 그것을 막습니다.

---

## 문서

| | |
| --- | --- |
| [`docs/README.md`](docs/README.md) | 문서 인덱스 · BMAD 워크플로 대응 |
| [`backend/README.md`](backend/README.md) | **백엔드 구조 · API 키를 어디에 넣는지** |
| [`docs/17-ONDEVICE-LLM-RESEARCH.md`](docs/17-ONDEVICE-LLM-RESEARCH.md) | 온디바이스 LLM 비교 분석 |
| [`docs/project-context.md`](docs/project-context.md) | 5분 요약 — 새 세션은 여기부터 |
| [`CLAUDE.md`](CLAUDE.md) | 작업 규칙 (사람·AI 공용) |
| [통합 HTML 기획서](docs/CaptureTask-Development-Plan.html) | 제품·UX·아키텍처·비용·배포를 한 문서로 |
| [PDF](output/pdf/CaptureTask-Development-Plan.pdf) | 공유·인쇄용 A4 |

```bash
python3 -m pip install -r requirements-docs.txt
python3 scripts/build_development_plan.py    # HTML · PDF 재생성
```

---

## 아직 안 되는 것

| | 막고 있는 것 |
| --- | --- |
| 실기기 공유 시트 확인 | Bundle ID · App Group 프로비저닝 |
| `confidence` 가 눈금 역할 못 함 | 실제 호출에서 전부 0.9~1.0. 평가셋(S-2.3)이 먼저 |
| 중복 감지 · 검색 | 정책 미결정 |
| 온디바이스 LLM | 평가셋 없음 |

자세한 판정은 [`docs/12-IMPLEMENTATION-READINESS.md`](docs/12-IMPLEMENTATION-READINESS.md).
