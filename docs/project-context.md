# CaptureTask — Project Context

> BMAD 보조 도구 `bmad-generate-project-context` 대응 산출물.
> **AI 에이전트가 이 프로젝트에서 일관된 판단을 하기 위해 읽는 문서.** 사람에게는 요약본으로도 쓰인다.
> 새 세션·새 에이전트에게 일을 맡길 때 이 파일을 먼저 준다.

---

## 무엇을 만드는가

**CaptureTask** — iPhone 스크린샷을 공유 시트로 보내면 할 일이 되고, 마감이 다가오면 알려 주는 개인 비서 앱.

```
1. Share Extension 이 원본을 App Group 상자에 담는다
2. 메인 앱이 Apple Vision 으로 텍스트를 온디바이스 추출한다
3. 백엔드가 OpenAI 로 제목·마감·시간·신뢰도·근거를 제안한다
4. 사용자가 확인한다                        ← 이 단계를 건너뛰는 경로는 없다
5. 앱 할 일에 저장하고, 마감 알림을 예약하고, 선택 시 Apple 캘린더에도 넣는다
```

> **AI 는 제안만 한다.** 일정 오인식은 실제 약속을 망가뜨린다.

---

## 제품 결정

| 결정 | 이유 |
| --- | --- |
| 앱 할 일이 **원장**이다 | 캘린더도, 앱 안의 캘린더 탭도 원장이 아니다. 두 곳에서 고치면 "어느 쪽이 진짜인가"를 답할 수 없다 |
| 캘린더는 **선택적 출력** | 저장 실패가 할 일 저장을 되돌리지 않는다 |
| 캘린더 탭은 **읽기 전용** | 같은 원장을 다른 각도에서 볼 뿐이다 |
| 알림은 **로컬 알림** | 서버 푸시를 쓰려면 서버가 사용자의 할 일을 알아야 한다 |
| OCR 은 **온디바이스** | 원본 이미지는 기기를 떠나지 않는다. 텍스트만 나간다 |
| OpenAI 호출은 **백엔드만** | 앱 번들의 문자열은 누구나 꺼낸다 |
| 문맥 분석기는 **교체 가능** | 온디바이스 전환 시 한 줄만 바꾼다 |
| 백엔드가 죽어도 **조용히 대체하지 않는다** | 사용자는 AI 가 나빠졌다고 생각하고, 우리는 백엔드가 죽은 줄 모른다 |

---

## 기술 스택

| 항목 | 값 |
| --- | --- |
| 플랫폼 | iOS 17.0+ / iPhone |
| 언어·UI | Swift 5, SwiftUI |
| 상태 관리 | `@MainActor` + `ObservableObject` |
| 프레임워크 | SwiftUI · Vision · EventKit · UserNotifications · UIKit(Extension) |
| 외부 의존성 | **없음** (iOS·백엔드 모두) |
| 저장 | Application Support / JSON (원자적 쓰기) + App Group 파일 상자 |
| 백엔드 | Node 22 · `node:http` · 외부 패키지 0 |
| 프로젝트 정의 | XcodeGen (`project.yml`) — `.xcodeproj` 는 **생성물, 미추적** |
| 테스트 | XCTest 93건 · `node:test` 40건 |
| 번들 ID | `com.example.capturetask` (D-1 미확정) |
| App Group | `group.com.example.capturetask` |
| 기본 언어 | 한국어 |

---

## 빌드 · 테스트 · 실행

```bash
# 검증 (사람·AI·훅·CI 가 모두 이것 하나)
./scripts/verify.sh
./scripts/verify.sh --quick      # iOS 테스트 제외, 몇 초

# 개별
./scripts/check-project-rules.sh --list
cd backend && npm test
xcodegen generate

# 백엔드 실행 (사용자가 넣을 것은 OPENAI_API_KEY 한 줄뿐)
cd backend && cp .env.example .env
#   .env 를 열어 키를 넣고
set -a; source .env; set +a; npm start
```

| 환경 변수 (DEBUG 전용) | 뜻 |
| --- | --- |
| `CAPTURETASK_OFFLINE=1` | 백엔드 없이 규칙 기반 분석기 사용 |
| `CAPTURETASK_TAB=0\|1` | 시작 탭 (할 일 / 캘린더) |
| `CAPTURETASK_SHEET=settings\|text` | 시작하자마자 열 시트 |
| `CAPTURETASK_API_BASE_URL` | 백엔드 주소 (기본 `http://127.0.0.1:8787`) |
| `CAPTURETASK_SIMULATOR_ID` | 시뮬레이터 고정 |

시뮬레이터에서는 `SIMCTL_CHILD_` 접두사를 붙인다.

> **눌러 볼 때는 서명해서 빌드한다.** `CODE_SIGNING_ALLOWED=NO` 로 빌드하면 entitlements 가
> 안 박혀 App Group 이 언제나 nil 이고, 앱이 "공유 시트로 담기를 쓸 수 없어요" 를 띄운다.
> 테스트는 서명이 필요 없으므로 `verify.sh` 는 그대로 둔다.

---

## 코드 지도

```
CaptureTask/
  App/          진입점
  Models/       순수 값 · 순수 함수      ← 아무것도 import 하지 않는다
    AssistantTask · TaskDraft · Confidence
    DueGrouping      마감 묶음 분류·정렬
    ReminderSchedule 알림 시각·식별자
    MonthGrid        월 격자·날짜별 묶기
    WalletStackLayout 지갑 카드 배치
  Services/     플랫폼·네트워크 어댑터
  Shared/       앱 ↔ Extension 공유       ← Extension 타깃에도 들어간다
  Store/        상태·영속화·유스케이스 조율
  Views/        SwiftUI 7개
CaptureTaskShare/   담기 전용
CaptureTaskTests/   90건
backend/            src 4개 · test 2개
scripts/            verify · 규칙 검사 · 시뮬레이터 선택
docs/               BMAD 00~16 + sprint-status.yaml + plans/
```

**의존은 한 방향** — View → Store → Service 프로토콜 → 어댑터, 그리고 모두가 Model 을 안다.
Model 은 아무도 모른다.

---

## 이 프로젝트에서 판단이 갈릴 때

| 상황 | 이렇게 한다 |
| --- | --- |
| 계산을 어디 둘까 | **Models 의 순수 함수.** 뷰에 두면 검증하려고 화면을 띄워야 한다 |
| `now` 를 어디서 읽을까 | **인자로 받는다.** 안에서 읽으면 테스트가 오늘 날짜에 흔들린다 |
| 저장 모델에 필드를 더할까 | **반드시 옵셔널** + 구버전 디코딩 테스트를 함께 |
| 실패를 어떻게 다룰까 | **던져서 화면까지.** `try?` 로 삼키면 사용자는 잃은 뒤에 안다 |
| 파생 값을 저장할까 | **아니오.** 매번 계산한다 |
| 대체 경로를 자동으로 쓸까 | **아니오.** 조용한 품질 저하는 아무도 못 본다 |
| 생성 파일을 고쳐야 하는데 | **원본을 찾아 고치고 다시 생성해서 확인한다** |
| 새 규칙을 넣을 때 | **일부러 어겨 보고 빨간불을 본 뒤에** 커밋한다 |

---

## 지금 되는 것

- 공유 시트로 담기 → App Group 상자 (실기기 미확인)
- 앱 활성화 시 자동 재수집 · OCR 캐시 · 초안 영속화
- Vision OCR (배경 큐) → 백엔드 분석 → 확인 화면
- 지갑 스타일 마감 스택 (묶음 6개 · 겹침 · 하나만 펼침)
- 마감 알림 3종 (1시간 전 / 당일 09:00 / 하루 전 20:00)
- 이번 달 캘린더 (읽기 전용)
- Apple 캘린더 추가·삭제
- 저장 손상 격리 · 구버전 파일 호환
- 텍스트 붙여넣기로 분석 시험 · 오프라인 규칙 기반 모드
- 앱 안에서 사진 고르기 (최대 10장) · 공유 시트로 여러 장 받기
- **배포된 백엔드** (Cloud Run 서울) · 공유 비밀 인증 · IP/일일 요청 한도
- 설정에서 분석 엔진 고르기 (백엔드 / 규칙 기반 / 온디바이스는 준비 중)
- 접근성 — 큰 글자에서 목록으로 전환 · 모션 줄이기 · 대비 높이기 · 알림 탭 라우팅

## 지금 안 되는 것

| | 막고 있는 것 |
| --- | --- |
| 실기기 공유 시트 확인 | Bundle ID·App Group 프로비저닝 (D-1) |
| `confidence` 가 눈금 역할 못 함 | 실제 호출에서 전부 0.9~1.0. 평가셋(S-2.3)이 먼저 |
| 중복 감지 | 무엇을 중복으로 볼지 미결정 (D-5) |
| 백엔드 인증·rate limit | 배포 차단 (NFR-SEC-05) |
| 온디바이스 LLM | 평가셋 50건 없음 (S-2.3). 비교 분석은 [17장](17-ONDEVICE-LLM-RESEARCH.md) |

---

## 다음에 할 일 (순서대로)

1. **S-2.3** — 익명화 평가셋 50건 ← **다음**
2. **D-1 결정** — 제품명 · Bundle ID · App Group 확정
3. **S-1.3** — 실기기 공유 E2E

접근성 4건(S-9.1~9.4)은 2026-08-01 에 끝냈다.

---

## 상태 숫자

iOS 테스트 79 · 백엔드 테스트 15 · 프로젝트 규칙 11 · 빌드 경고 0 · 스토리 67/74

> 숫자의 원본은 [sprint-status.yaml](sprint-status.yaml) 이다.
