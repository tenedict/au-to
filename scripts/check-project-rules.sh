#!/usr/bin/env bash
# CaptureTask 전용 규칙 검사.
#
# 기성 린터가 모르는 것만 본다. 전부 문서에 근거가 있고, 전부 실제로
# 한 번씩 사고를 낸 적이 있는 규칙이다.
#   근거 → CLAUDE.md · docs/09-SPEC.md · docs/10-ARCHITECTURE-SPINE.md

set -uo pipefail
cd "$(dirname "$0")/.."

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'
fail=0

report() {  # report <심각도> <규칙> <근거> <설명>
  local sev=$1 rule=$2 why=$3 msg=$4
  if [ "$sev" = error ]; then
    printf '%s✕%s %s  %s%s%s\n    %s\n' "$RED" "$OFF" "$rule" "$DIM" "$why" "$OFF" "$msg"
    fail=1
  else
    printf '%s!%s %s  %s%s%s\n    %s\n' "$YEL" "$OFF" "$rule" "$DIM" "$why" "$OFF" "$msg"
  fi
}

SRC="CaptureTask"
SHARE="CaptureTaskShare"
TESTS="CaptureTaskTests"

# ── --list · 규칙 목록을 검사기가 직접 출력한다 ────────────────
# 개수를 문서에 손으로 적으면 반드시 어긋난다. 셈은 여기서만 한다.
if [ "${1:-}" = "--list" ]; then
  grep '^# ── 규칙' "$0" | sed 's/^# ── /  /' | sed 's/ ─.*$//'
  exit 0
fi

# 주석은 검사하지 않는다. 규칙을 설명하는 주석이 그 규칙에 걸리면
# 검사기가 자기 문서를 물어버린다.
strip_comments() { grep -vE '^[^:]+:[0-9]+:[[:space:]]*(///?|\*|/\*|#)' || true; }

# ── 규칙 0 · 검사기 자신을 검사한다 ───────────────────────────
# 경로가 어긋나면 모든 grep 이 빈손으로 돌아오고 검사기는 조용히 초록을 낸다.
# verify.sh 가 도구 부재에 대해 적어 둔 원칙을 검사기 자신에게도 적용한다 —
#   "없다고 조용히 통과시키면 검증이 거짓말을 시작한다."
for dir in "$SRC" "$SHARE" "$TESTS"; do
  [ -d "$dir" ] || report error "검사 대상 디렉터리 없음" "자기 검사" \
    "$dir/ 가 없습니다. 검사기가 아무것도 훑지 못했습니다 — 초록불은 거짓입니다."
done

scanned=$(find "$SRC" "$SHARE" "$TESTS" -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')
[ "$scanned" -ge 15 ] || report error "훑은 파일이 너무 적음 (${scanned}개)" "자기 검사" \
  "경로가 어긋났거나 체크아웃이 잘렸습니다. 이 상태의 통과는 근거가 없습니다."

# 계약을 실제로 지키는 것은 아래 규칙들이 아니라 이 테스트들이다.
# 파일이나 함수가 사라지면 방어선이 사라진 것이므로 여기서 막는다.
for t in \
  "$TESTS/TaskStorageTests.swift:testCorruptFileIsQuarantinedAndReported" \
  "$TESTS/TaskStorageTests.swift:testDecodesTaskSavedBeforeRemindersFieldExisted" \
  "$TESTS/TaskStorageTests.swift:testDecodesLegacyNumericDates" \
  "$TESTS/TaskStoreTests.swift:testCompletingTaskClearsItsReminders" \
  "$TESTS/TaskStoreTests.swift:testDeletingTaskCancelsItsReminders" \
  "$TESTS/TaskStoreTests.swift:testDiscardingDraftRemovesItEverywhere" \
  "$TESTS/ReminderScheduleTests.swift:testPastFireTimesAreDropped" \
  "$TESTS/DueGroupingTests.swift:testTodayWithPassedExplicitTimeIsOverdue" \
  "$TESTS/DueGroupingTests.swift:testGroupsAppearInUrgencyOrder" \
  "$TESTS/CaptureNoticeTests.swift:testDueReminderIsNotMistakenForACaptureNotice"
do
  f=${t%%:*}; fn=${t##*:}
  grep -q "func $fn" "$f" 2>/dev/null || \
    report error "핵심 테스트 사라짐" "자기 검사" "$f 의 $fn 이 없습니다."
done

# ── 규칙 1 · App Group 식별자가 세 곳에서 같은가 ──────────────
# 이 값이 비거나 어긋나면 공유 시트로 담은 스크린샷이 앱에 **영원히** 도착하지 않는다.
# 담기는 성공하므로 사용자에게는 "담았어요" 라고 말한 뒤 아무 일도 안 일어난 것으로 보인다.
#
# 실제로 이 프로젝트에서 두 entitlements 가 빈 <dict/> 인 채로 R0 을 통과했다.
# 게다가 XcodeGen 은 project.yml 의 entitlements.properties 가 없으면 파일을
# 빈 <dict/> 로 덮어쓴다 — 파일에만 적어 두면 다음 generate 에서 조용히 사라진다.
group_in_code=$(grep -oE 'appGroupIdentifier[[:space:]]*=[[:space:]]*"[^"]+"' \
  "$SRC/Shared/PendingCapture.swift" 2>/dev/null | sed -E 's/.*"([^"]+)"/\1/' | head -1)

if [ -z "$group_in_code" ]; then
  report error "App Group 식별자를 코드에서 찾지 못함" "SPEC C-1" \
    "$SRC/Shared/PendingCapture.swift 의 SharedInbox.appGroupIdentifier 를 확인하세요."
else
  for f in project.yml Config/CaptureTask.entitlements Config/CaptureTaskShare.entitlements; do
    if [ ! -f "$f" ]; then
      report error "App Group 설정 파일 없음" "SPEC C-1" "$f 가 없습니다."
    elif ! grep -q "$group_in_code" "$f"; then
      report error "App Group 식별자 불일치" "SPEC C-1" \
        "$f 에 '$group_in_code' 이 없습니다. 공유 시트로 담은 스크린샷이 앱에 도착하지 않습니다."
    fi
  done
  # project.yml 에 properties 로 적혀 있어야 generate 후에도 살아남는다.
  grep -q 'com.apple.security.application-groups' project.yml 2>/dev/null || \
    report error "project.yml 에 App Group 이 없음" "SPEC C-1" \
      "entitlements.properties 에 적으세요. path 만 적으면 xcodegen 이 빈 <dict/> 로 덮어씁니다."
fi

# ── 규칙 2 · OpenAI 키가 앱·Extension 에 들어오지 않았는가 ────
# 키가 앱 번들에 들어가면 누구나 꺼낼 수 있다. 호출은 반드시 백엔드를 거친다. (CLAUDE 규칙 3)
hits=$(grep -rnE '"sk-[A-Za-z0-9_-]|OPENAI_API_KEY|api\.openai\.com' \
        --include='*.swift' "$SRC" "$SHARE" 2>/dev/null | strip_comments)
if [ -n "$hits" ]; then
  report error "앱 코드에 OpenAI 키/직접 호출" "CLAUDE 규칙 3" \
    "OpenAI 호출은 backend/ 만 합니다. 앱은 CAPTURETASK_API_BASE_URL 로 백엔드를 부릅니다."
  echo "$hits" | sed 's/^/      /'
fi

# ── 규칙 3 · Share Extension 은 수집만 한다 ──────────────────
# Extension 은 메모리와 실행 시간이 빡빡하다. 긴 네트워크 요청이나 EventKit 쓰기를 넣으면
# 시스템이 중간에 죽인다 — 사용자는 담기가 실패한 줄도 모른다. (CLAUDE 규칙 5)
# CaptureTask/Shared 도 Extension 타깃에 함께 들어가므로 같이 본다.
#
# `UserNotifications` 는 **일부러 뺐다.** 막는 기준은 "import 했는가"가 아니라
# "얼마나 오래 걸리는가"다. 네트워크·EventKit·Vision 은 수백 밀리초에서 수 초가 걸리지만,
# 로컬 알림 예약은 파일 쓰기 한 번 수준이라 같은 위험이 없다.
# 그리고 그 알림이 없으면 담기만 하고 앱을 안 연 사용자에게 아무 일도 일어나지 않는다
# — 분석은 메인 앱에서만 돌기 때문이다. (CaptureNotice)
hits=$(grep -rnE '^import (EventKit|Vision)|URLSession|URLRequest' \
        --include='*.swift' "$SHARE" "$SRC/Shared" 2>/dev/null | strip_comments)
if [ -n "$hits" ]; then
  report error "Share Extension 에 무거운 작업" "CLAUDE 규칙 5" \
    "OCR·LLM·캘린더는 메인 앱이 합니다. Extension 은 담고 알림 한 번 거는 것까지입니다."
  echo "$hits" | sed 's/^/      /'
fi

# ── 규칙 4 · 신뢰도 임계값은 Confidence 한 곳에서만 ──────────
# 0.80 을 여러 곳에 흩어 놓으면 한 곳만 고쳐지고, "확인 없이 캘린더에 쓰지 않는다" 는
# 약속이 경로마다 달라진다. (CLAUDE 규칙 2)
hits=$(grep -rnE '(^|[^0-9.])0\.80?([^0-9]|$)' --include='*.swift' "$SRC" 2>/dev/null \
        | grep -v 'Models/AssistantTask.swift' | strip_comments)
if [ -n "$hits" ]; then
  report error "신뢰도 임계값 리터럴" "CLAUDE 규칙 2" \
    "Confidence.autoCalendarThreshold 를 쓰세요."
  echo "$hits" | sed 's/^/      /'
fi

# ── 규칙 5 · 캡처를 지우는 지점은 저장소 하나뿐 ──────────────
# 확인 전에 지우면 사용자가 공유한 스크린샷을 영영 잃는다. 지우는 자리가 여러 곳이면
# 그중 하나는 반드시 확인보다 먼저 지운다. (CLAUDE 규칙 7)
hits=$(grep -rn 'SharedInbox\.complete' --include='*.swift' "$SRC" "$SHARE" 2>/dev/null \
        | grep -v "^$SRC/Store/" | grep -v "^$SRC/Shared/" | strip_comments)
if [ -n "$hits" ]; then
  report error "저장소 밖에서 캡처 삭제" "CLAUDE 규칙 7" \
    "TaskStore 가 사용자 확인 뒤에만 지웁니다."
  echo "$hits" | sed 's/^/      /'
fi

# ── 규칙 6 · 모델은 화면·플랫폼을 모른다 ─────────────────────
# 모델이 SwiftUI 나 EventKit 을 알면 계산을 테스트하려고 화면을 띄워야 한다.
# 그러면 아무도 테스트하지 않게 된다. (ADR-1)
hits=$(grep -rnE '^import (SwiftUI|UIKit|EventKit|Vision|UserNotifications)' \
        --include='*.swift' "$SRC/Models" 2>/dev/null | strip_comments)
if [ -n "$hits" ]; then
  report error "모델이 화면·플랫폼을 앎" "ADR-1" \
    "순수 값과 순수 함수만 두세요. 어댑터는 Services/ 입니다."
  echo "$hits" | sed 's/^/      /'
fi

# ── 규칙 7 · 알림 예약은 정해진 두 파일에서만 ───────────────
# 화면이 직접 알림을 걸면 취소 지점이 갈라지고, 끝낸 일이 계속 울린다.
#
# 알림 종류가 둘이라 소유자도 둘이다. 그 이상으로 늘어나면 안 된다.
#   Services/NotificationService.swift  마감 알림 (앱 전용)
#   Shared/CaptureNotice.swift          확인 요청 (앱 + Extension 공용)
#
# CaptureNotice 가 Shared 에 있는 이유는 Share Extension 이 담은 직후 알려야 하기
# 때문이다. Services/ 에 두면 Extension 타깃에 들어가지 않는다.
# 다른 곳에서는 이 두 타입을 **불러 쓰기만** 한다 — 직접 예약하지 않는다.
hits=$(grep -rn 'UNUserNotificationCenter\|UNNotificationRequest' \
        --include='*.swift' "$SRC" "$SHARE" 2>/dev/null \
        | grep -v 'Services/NotificationService.swift' \
        | grep -v 'Shared/CaptureNotice.swift' | strip_comments)
if [ -n "$hits" ]; then
  report error "정해진 곳 밖에서 알림 예약" "SPEC N-1" \
    "마감은 LocalNotificationService, 확인 요청은 CaptureNotice 를 거치세요."
  echo "$hits" | sed 's/^/      /'
fi

# ── 규칙 8 · 저장·복원 실패를 try? 로 삼키지 않는다 ──────────
# 사용자는 잃은 뒤에 안다. 저장소 호출의 실패는 반드시 화면까지 올라와야 한다.
hits=$(grep -rn 'try?[[:space:]]*storage\.' --include='*.swift' "$SRC" 2>/dev/null \
        | strip_comments)
if [ -n "$hits" ]; then
  report error "저장 실패를 삼킴" "CLAUDE 규칙 8" \
    "do/catch 로 받아 lastErrorMessage 에 올리세요."
  echo "$hits" | sed 's/^/      /'
fi

# ── 규칙 9 · 화면 파일 500줄 ─────────────────────────────────
while IFS= read -r line; do
  n=${line%% *}; f=${line#* }
  [ "$f" = total ] && continue
  if [ "$n" -gt 500 ]; then
    report error "500줄 초과 ($n줄)" "NFR-MNT-05" "$f — 파일을 나누세요."
  elif [ "$n" -gt 450 ]; then
    report warn "450줄 근접 ($n줄)" "NFR-MNT-05" "$f"
  fi
done < <(find "$SRC/Views" -name '*.swift' -exec wc -l {} + 2>/dev/null | sed 's/^ *//' | grep -v ' total$')

# ── 규칙 10 · 백엔드 기본 모델이 확인된 이름인가 ─────────────
# 실재하지 않는 이름을 기본값에 두면 키를 넣은 첫 호출이 404 로 죽는다. 그때 사용자에게는
# "분석 서버에 연결하지 못했어요" 만 보이고 원인은 키가 아니라 모델 이름이다.
# 실제로 이 프로젝트의 기본값이 한동안 존재하지 않는 이름(gpt-5.6-luna)이었다.
#
# 검사기는 OpenAI 의 모델 목록을 알 수 없다. 그래서 **접두사가 아니라 정확 일치**로 본다 —
# 접두사로 두면 'gpt-5.6-luna' 가 'gpt-5' 로 시작한다는 이유로 그대로 통과한다.
# 새 모델을 쓰려면 사람이 이 목록에 한 줄 더하며 한 번 확인하게 된다.
KNOWN_MODELS="gpt-4.1 gpt-4.1-mini gpt-4.1-nano gpt-4o gpt-4o-mini gpt-5 gpt-5-mini gpt-5-nano o3 o4-mini"
model=$(grep -oE 'DEFAULT_MODEL = "[^"]+"' backend/src/openai-client.mjs 2>/dev/null \
        | sed -E 's/.*"([^"]+)"/\1/')
if [ -z "$model" ]; then
  report error "백엔드 기본 모델을 찾지 못함" "SPEC A-2" \
    "backend/src/openai-client.mjs 의 DEFAULT_MODEL 을 확인하세요."
elif ! printf '%s\n' $KNOWN_MODELS | grep -qxF "$model"; then
  report error "확인되지 않은 기본 모델 ($model)" "SPEC A-2" \
    "OpenAI 가 실제로 제공하는 이름인지 확인한 뒤 이 스크립트의 KNOWN_MODELS 에 더하세요. 오타는 첫 호출에서 404 로만 드러납니다."
fi
grep -q "$model" backend/.env.example 2>/dev/null || \
  report warn "예제 환경파일의 모델이 기본값과 다름" "SPEC A-2" \
    "backend/.env.example 의 OPENAI_MODEL 을 $model 로 맞추세요."

echo
if [ $fail -eq 0 ]; then
  printf '%s✓%s 프로젝트 규칙 통과\n' "$GRN" "$OFF"
else
  printf '%s✕%s 프로젝트 규칙 위반\n' "$RED" "$OFF"
fi
exit $fail
