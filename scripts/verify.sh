#!/usr/bin/env bash
# Whenly 검증 — 사람 · Claude · Git Hook · CI 가 모두 이 명령 하나를 쓴다.
#
#   ./scripts/verify.sh          전체 (규칙 + 포맷 + 린트 + 백엔드 테스트 + iOS 테스트)
#   ./scripts/verify.sh --quick  빠른 것만 (iOS 테스트 제외) — pre-commit 용
#
# 설치 안 된 도구는 건너뛰되 무엇이 빠졌는지 알린다.
# 없다고 조용히 통과시키면 검증이 거짓말을 시작한다.

set -uo pipefail
cd "$(dirname "$0")/.."

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'
QUICK=0; [ "${1:-}" = "--quick" ] && QUICK=1
fail=0; skipped=()

step() { printf '\n%s▸ %s%s\n' "$BLD" "$1" "$OFF"; }
ok()   { printf '%s  ✓ %s%s\n' "$GRN" "$1" "$OFF"; }
bad()  { printf '%s  ✕ %s%s\n' "$RED" "$1" "$OFF"; fail=1; }
skip() { printf '%s  – %s (미설치)%s\n' "$DIM" "$1" "$OFF"; skipped+=("$2"); }

# ── 1. 프로젝트 전용 규칙 ────────────────────────────────────
step "프로젝트 규칙"
./scripts/check-project-rules.sh || fail=1

# ── 1-2. 문서 링크 ──────────────────────────────────────────
# 문서를 옮길 때마다 링크 몇 개가 조용히 죽는다. 눌러 보는 사람은 대개
# 이 저장소를 처음 여는 사람이라, 첫인상이 깨진 링크가 된다.
step "문서 링크"
if command -v python3 >/dev/null 2>&1; then
  out=$(./scripts/check-doc-links.sh 2>&1)
  if [ $? -eq 0 ]; then ok "$(echo "$out" | tail -1 | sed 's/^[^ ]* //')"
  else bad "깨진 문서 링크"; echo "$out" | head -12 | sed 's/^/    /'; fi
else
  skip "python3" "문서 링크 검사에 필요"
fi

# ── 2. 포맷 (Xcode 내장) ────────────────────────────────────
step "코드 포맷"
if xcrun --find swift-format >/dev/null 2>&1; then
  # 경고로만 다룬다. 스타일 때문에 빌드를 막지 않는다.
  # 자동 수정은 사람이 명시적으로 요청했을 때만 (작업 범위 밖 파일까지 번지면 리뷰가 불가능해진다)
  if out=$(swift format lint --recursive apps core tests 2>&1); then
    ok "swift-format"
  else
    printf '%s  ! swift-format 지적 %s건%s\n' "$YEL" "$(echo "$out" | grep -c 'error:')" "$OFF"
    echo "$out" | head -8 | sed 's/^/    /'
    printf '%s    고치기: swift format --in-place --recursive apps core tests%s\n' "$DIM" "$OFF"
  fi
else
  skip "swift-format" "Xcode 16+ 필요"
fi

# ── 3. 린트 ────────────────────────────────────────────────
step "SwiftLint"
if command -v swiftlint >/dev/null 2>&1; then
  # --strict 를 붙이면 .swiftlint.yml 의 severity 구분이 사라진다 — 경고로 둔 것까지
  # 전부 error 가 되어, 무엇이 진짜 막아야 할 것인지 설정만 보고는 알 수 없게 된다.
  # 막을 것은 severity: error 로 설정에 적는다.
  out=$(swiftlint lint --quiet 2>&1); rc=$?
  warnings=$(echo "$out" | grep -c ' warning: ')
  if [ $rc -eq 0 ]; then
    if [ "$warnings" -gt 0 ]; then
      printf '%s  ! SwiftLint 경고 %s건%s\n' "$YEL" "$warnings" "$OFF"
      echo "$out" | grep ' warning: ' | head -5 | sed 's|.*/auto_/||' | sed 's/^/    /'
    else
      ok "SwiftLint"
    fi
  else
    bad "SwiftLint"
    echo "$out" | grep ' error: ' | head -20 | sed 's|.*/auto_/||' | sed 's/^/    /'
  fi
else
  skip "SwiftLint" "brew install swiftlint"
fi

# ── 4. 백엔드 테스트 ────────────────────────────────────────
# iOS 테스트보다 훨씬 빠르다. --quick 에서도 돈다.
step "백엔드 테스트"
if command -v node >/dev/null 2>&1; then
  if out=$(cd server && npm test 2>&1); then
    ok "백엔드 $(echo "$out" | grep -E '^# pass ' | tail -1 | tr -dc '0-9')건 통과"
  else
    bad "백엔드 테스트 실패"
    echo "$out" | grep -E '^not ok|^# fail|Error' | head -20 | sed 's/^/    /'
  fi
else
  skip "node" "Node 22+ 필요 — https://nodejs.org"
fi

# ── 5. iOS 빌드 · 테스트 ───────────────────────────────────
if [ $QUICK -eq 1 ]; then
  step "iOS 빌드 · 테스트"
  printf '%s  – 건너뜀 (--quick)%s\n' "$DIM" "$OFF"
else
  step "iOS 빌드 · 테스트"
  SIM_ID=$(./scripts/select-simulator.sh) || { printf '%s  ✕ 시뮬레이터 없음%s\n' "$RED" "$OFF"; exit 1; }

  # Secrets.xcconfig 는 커밋되지 않는다. 없으면 xcodegen 이 configFiles 를 찾지 못해
  # 실패하고, 새 체크아웃과 CI 가 전부 막힌다 — 실제로 CI 가 한 번 이걸로 죽었다.
  # 예제의 기본값은 로컬 백엔드라 그대로 복사해도 안전하다.
  if [ ! -f config/apple/Secrets.xcconfig ]; then
    cp config/apple/Secrets.xcconfig.example config/apple/Secrets.xcconfig \
      && printf '%s  · config/apple/Secrets.xcconfig 를 예제에서 만들었습니다 (로컬 백엔드)%s\n' \
           "$DIM" "$OFF"
  fi

  # 생성물이 소스보다 오래되면 새 파일이 타깃에 안 들어간 채 초록이 난다.
  if command -v xcodegen >/dev/null 2>&1; then
    if ! out=$(xcodegen generate 2>&1); then
      bad "xcodegen generate 실패"
      echo "$out" | tail -5 | sed 's/^/    /'
    fi
  else
    skip "xcodegen" "brew install xcodegen"
  fi

  set -o pipefail
  if command -v xcbeautify >/dev/null 2>&1; then
    xcodebuild test -project Whenly.xcodeproj -scheme Whenly -sdk iphonesimulator \
      -destination "id=$SIM_ID" -derivedDataPath build CODE_SIGNING_ALLOWED=NO 2>&1 | xcbeautify --quiet
    rc=$?
  else
    out=$(xcodebuild test -project Whenly.xcodeproj -scheme Whenly -sdk iphonesimulator \
      -destination "id=$SIM_ID" -derivedDataPath build CODE_SIGNING_ALLOWED=NO 2>&1); rc=$?
    echo "$out" | grep -E '(^|[^-])error:|Executed .* tests' | sed 's/^/    /'
    skipped+=("xcbeautify — brew install xcbeautify")
  fi
  [ $rc -eq 0 ] && ok "iOS 테스트 통과" || bad "iOS 테스트 실패"

  # macOS 앱은 iOS 와 Models·Services·Store·Shared 를 공유한다. 공유 코드를 고치면
  # 여기가 먼저 깨지는데, 빌드하지 않으면 그 사실을 아무도 모른 채 초록이 난다.
  step "macOS 빌드"
  if out=$(xcodebuild build -project Whenly.xcodeproj -scheme WhenlyMac \
             -derivedDataPath build CODE_SIGNING_ALLOWED=NO 2>&1); then
    ok "macOS 앱 빌드"
  else
    bad "macOS 앱 빌드 실패"
    echo "$out" | grep -E '(^|[^-])error:' | head -10 | sed 's/^/    /'
  fi
fi

# ── 결과 ───────────────────────────────────────────────────
echo
if [ ${#skipped[@]} -gt 0 ]; then
  printf '%s건너뛴 검사%s\n' "$YEL" "$OFF"
  for s in "${skipped[@]}"; do printf '  · %s\n' "$s"; done
  echo
fi

if [ $fail -eq 0 ]; then
  printf '%s%s검증 통과%s\n' "$GRN" "$BLD" "$OFF"
else
  printf '%s%s검증 실패 — 완료했다고 보고하지 않는다%s\n' "$RED" "$BLD" "$OFF"
fi
exit $fail
