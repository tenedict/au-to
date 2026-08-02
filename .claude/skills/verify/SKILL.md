---
name: verify
description: CaptureTask 작업을 완료했다고 보고하기 전에 실행하는 검증. 프로젝트 규칙·포맷·린트·백엔드 테스트·iOS 전체 테스트를 한 번에 돌리고, 실패하면 무엇이 왜 실패했는지 정리한다. 코드를 고친 뒤, 커밋 전, "다 됐다"고 말하기 전에 쓴다.
---

# 검증

**구현했다 ≠ 완료했다.** 이 스킬은 완료를 판정한다.

## 1. 실행

```bash
./scripts/verify.sh
```

빠른 확인만 필요하면 (iOS 테스트 제외, 몇 초):

```bash
./scripts/verify.sh --quick
```

사람·Claude·Git Hook·CI가 **모두 이 명령 하나**를 쓴다. 각자 다른 명령을 쓰면 "내 쪽에서는 됐는데"가 생긴다.

## 2. 검사하는 것

| 단계 | 내용 | 실패하면 |
| --- | --- | --- |
| 프로젝트 규칙 | 목록은 `./scripts/check-project-rules.sh --list` | **차단** |
| 코드 포맷 | `swift format lint` | 경고만 |
| SwiftLint | 복잡도·강제 언래핑·전용 규칙 (설치 시) | 차단 |
| 백엔드 테스트 | `cd server && npm test` | **차단** |
| iOS 빌드·테스트 | `xcodebuild test` 전체 | **차단** |

프로젝트 규칙은 전부 **실제로 한 번씩 사고를 낸 것**들이다. 근거는 각 지적 옆에 규칙/ADR 번호로 표시된다.
개수를 이 문서에 적지 않는 이유는, 적어 두면 반드시 어긋나기 때문이다. 셈은 검사기만 한다.

### 규칙이 확인하지 **못하는** 것

규칙은 grep이다. **"어떤 글자가 어디 있는가"까지만 답할 수 있다.**

예를 들어 규칙 1은 App Group 식별자가 세 파일에서 같은지 본다. 하지만 그 그룹이 실제 기기에서
프로비저닝되었는지는 모른다 — 그건 실기기에서 공유 시트를 눌러 봐야 안다.
마찬가지로 "알림이 실제로 울리는가"는 규칙이 아니라 `ReminderScheduleTests`와 실기기 확인의 몫이다.

> **규칙 통과 ≠ 올바름.** 규칙은 문법과 구조를 본다. 올바름은 테스트만 본다.

그래서 `--quick`(iOS 테스트 제외)으로 초록을 봤다면 **iOS 계약은 아직 검증되지 않았다.**
완료 판정에는 전체 실행이 필요하다.

## 3. 실패했을 때

1. **무엇이 실패했는지 그대로 읽는다.** 추측하지 않는다
2. 30분 넘게 막히면 찍어보기를 멈추고 → 재현 → 범위 좁히기 → 근본 원인 → 증명
3. 계산·규칙 문제면 **재현 테스트를 먼저 쓰고** 실패를 눈으로 본 뒤 고친다

## 4. 시뮬레이터에서 직접 눌러 볼 것

자동 검사가 못 보는 경로다. DEBUG 전용 환경 변수는 `SIMCTL_CHILD_` 접두사를 붙인다.

```bash
# 서명해서 빌드한다 — CODE_SIGNING_ALLOWED=NO 로 빌드하면 entitlements 가 안 박혀
# App Group 이 언제나 nil 이고, 앱이 "공유 시트로 담기를 쓸 수 없어요" 를 띄운다.
xcodebuild build -project CaptureTask.xcodeproj -scheme CaptureTask -sdk iphonesimulator \
  -destination "id=$(./scripts/select-simulator.sh)" -derivedDataPath /tmp/ct-signed

xcrun simctl install booted /tmp/ct-signed/Build/Products/Debug-iphonesimulator/CaptureTask.app

# 백엔드 없이 전체 흐름 (규칙 기반 분석기) · 캘린더 탭으로 시작
SIMCTL_CHILD_CAPTURETASK_OFFLINE=1 SIMCTL_CHILD_CAPTURETASK_TAB=1 \
  xcrun simctl launch --terminate-running-process booted com.example.capturetask
```

| DEBUG 환경 변수 | 값 |
| --- | --- |
| `CAPTURETASK_OFFLINE` | `1` — 백엔드 없이 규칙 기반 분석기 |
| `CAPTURETASK_TAB` | `0` 할 일 · `1` 캘린더 |
| `CAPTURETASK_SHEET` | `settings` 설정 · `text` 텍스트 분석 |
| `CAPTURETASK_API_BASE_URL` | 백엔드 주소 |

| 확인할 것 | 어떻게 |
| --- | --- |
| 지갑 스택 펼침 | 카드 하나를 누르고, 다른 것을 눌러 앞의 것이 접히는지 |
| 마감 순서 | 지난 마감이 맨 위, 그 안에서 가장 오래 밀린 것이 위인지 |
| 확인 화면 | 신뢰도가 낮은 초안에서 캘린더 토글이 꺼진 채로 뜨는지 |
| 알림 문구 | 확인 화면의 "언제 알려드려요" 가 실제 예약 시각과 같은지 |
| 캘린더 탭 | 마감 있는 날에 점이 찍히고, 날짜를 누르면 그날 할 일이 나오는지 |
| 설정 | 엔진 선택이 되고, 온디바이스가 **왜** 비활성인지 함께 보이는지 |
| 사진 고르기 | 여러 장을 골라도 하나씩 이어서 확인 화면이 뜨는지 |
| 공유 시트 | **실기기에서만** 확인 가능 (App Group 프로비저닝 필요) |

## 5. 보고

통과했을 때만 완료라고 말한다. 보고에는 숫자를 넣는다.

```
✓ 프로젝트 규칙 통과 · iOS 115/115 · 백엔드 46/46 · 빌드 경고 0
```

**금지**
- "아마 될 거예요"
- 실행하지 않고 "고쳤습니다"
- 새 테스트만 돌리고 "통과"

실패한 게 있으면 **그대로 말한다.** 통과한 것처럼 말하는 게 가장 큰 손해다.

## 6. 확인하지 못한 것은 확인하지 못했다고 쓴다

시뮬레이터에서 App Group을 못 써 공유 시트 경로를 못 본 경우처럼, 눈으로 확인 못 한 항목이
있으면 수용 기준별로 ✅/⚠️를 나눠 적는다. 다 됐다고 뭉뚱그리지 않는다.
