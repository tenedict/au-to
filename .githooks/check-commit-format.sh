#!/usr/bin/env bash
# 커밋 제목이 이 저장소의 규칙을 지키는지 검사한다.
#
#   ./.githooks/check-commit-format.sh --file <메시지파일>   commit-msg 훅이 쓰는 형태
#   ./.githooks/check-commit-format.sh <base>..<head>        CI 의 최종 강제
#   ./.githooks/check-commit-format.sh                       인자 없으면 최근 20개
#
# 규칙 — CLAUDE.md `## Git · 커밋`
#   Conventional Commits · 제목은 명령형 영문 소문자 · 72자 이내
#
# 왜 PRBODY 를 막나 —
#   PR 본문과 커밋 메시지를 한 파일에 담고 `PRBODY` 로 가르는 방식을 쓰다가,
#   GitHub squash 병합이 그 파일을 통째로 커밋 메시지로 삼은 적이 있다.
#   PR 본문 첫 줄이 제목이 되고 진짜 제목은 본문 속에 묻혔다 (#10 #12 그리고 PR #2).
#   구분자가 메시지에 남아 있다는 건 그 사고가 또 났다는 뜻이다.

set -uo pipefail

TYPES='feat|fix|docs|test|refactor|chore|style|perf|build|ci|revert'
SUBJECT_RE="^(${TYPES})(\([a-z0-9._-]+\))?!?: .+"

# 메시지 하나를 검사한다. 위반 사유를 한 줄씩 stdout 으로 뱉고, 있으면 1 을 돌려준다.
check_message() {
  local msg="$1" subject second reasons=()

  subject="$(printf '%s\n' "$msg" | grep -v '^#' | sed '/./,$!d' | head -1)"
  second="$(printf '%s\n' "$msg" | grep -v '^#' | sed '/./,$!d' | sed -n '2p')"

  # 사람이 쓰지 않은 제목 — 검사 대상이 아니다
  case "$subject" in
    Merge\ *|Revert\ \"*|fixup!\ *|squash!\ *|amend!\ *) return 0 ;;
  esac

  printf '%s\n' "$msg" | grep -q '^[[:space:]]*PRBODY[[:space:]]*$' \
    && reasons+=('PRBODY 구분자가 메시지에 남아 있습니다 — PR 본문이 커밋 메시지로 새어 들어갔습니다')

  printf '%s' "$subject" | grep -qE "$SUBJECT_RE" \
    || reasons+=("제목이 Conventional Commits 형식이 아닙니다 (${TYPES//|/, } 중 하나로 시작)")

  printf '%s' "$subject" | grep -qE '[가-힣]' \
    && reasons+=('제목은 영문으로 씁니다 — 한글은 본문에 씁니다')

  printf '%s' "$subject" | grep -qE '\*\*|__|`' \
    && reasons+=('제목에 마크다운 강조를 쓰지 않습니다')

  printf '%s' "$subject" | grep -qE '\.$' \
    && reasons+=('제목을 마침표로 끝내지 않습니다')

  local len
  len="$(printf '%s' "$subject" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')"
  [ "$len" -gt 72 ] && reasons+=("제목이 ${len}자입니다 — 72자 이내로 줄여 주세요")

  [ -n "$second" ] && reasons+=('제목 다음 줄은 비워 둡니다')

  [ ${#reasons[@]} -eq 0 ] && return 0
  printf '    · %s\n' "${reasons[@]}"
  return 1
}

usage_hint() {
  cat >&2 <<'EOF'

이 저장소의 커밋 제목 규칙 — CLAUDE.md `## Git · 커밋`

  <type>(<scope>): <명령형 영문 소문자 요약>      72자 이내
                                                 ← 빈 줄
  왜 그렇게 했는지는 본문에 한글로 적는다.

  feat  fix  docs  test  refactor  chore  style  perf  build  ci  revert

  예)  fix(macos): make the droplet actually transparent
       feat(notifications): ask for confirmation after a capture

PR 을 squash 로 병합하면 PR 제목이 그대로 커밋 제목이 됩니다.
PR 제목부터 이 형식으로 씁니다.

EOF
}

# --- 메시지 파일 하나 (commit-msg 훅) ---
if [ "${1:-}" = "--file" ]; then
  msg_file="${2:-}"
  [ -n "$msg_file" ] && [ -f "$msg_file" ] || exit 0
  if ! out="$(check_message "$(cat "$msg_file")")"; then
    {
      printf '\n✕ 커밋 제목이 규칙에 맞지 않습니다.\n\n'
      printf '%s\n' "$out"
    } >&2
    usage_hint
    exit 1
  fi
  exit 0
fi

# --- 커밋 범위 (CI) ---
range="${1:-}"
if [ -z "$range" ] || ! git rev-parse "$range" >/dev/null 2>&1; then
  range="HEAD~20..HEAD"
  git rev-parse "$range" >/dev/null 2>&1 || range="HEAD"
fi

fail=0
while read -r sha; do
  [ -n "$sha" ] || continue
  if ! out="$(check_message "$(git log -1 --format='%B' "$sha")")"; then
    fail=1
    printf '✕ %s\n' "$(git log -1 --format='%h %s' "$sha")"
    printf '%s\n' "$out"
  fi
done < <(git rev-list "$range" 2>/dev/null)

if [ "$fail" -ne 0 ]; then
  usage_hint
  cat >&2 <<'EOF'
이미 올린 커밋은 메시지를 다시 써야 합니다.

  git rebase -i <base>     고칠 커밋을 reword 로 표시합니다

EOF
  exit 1
fi

echo "✓ 커밋 제목이 규칙에 맞음 ($range)"
exit 0
