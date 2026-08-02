#!/usr/bin/env bash
# 문서의 상대 링크가 실제 파일을 가리키는지 검사한다.
#
#   ./scripts/check-doc-links.sh
#
# 문서를 옮길 때마다 링크 몇 개가 조용히 죽는다. 죽은 링크는 눌러 보기 전까지
# 아무도 모르고, 눌러 보는 사람은 대개 이 저장소를 처음 여는 사람이다.
# 바깥 주소(http)는 검사하지 않는다 — 네트워크에 기대는 검사는 흔들린다.

set -uo pipefail
cd "$(dirname "$0")/.."

RED=$'\033[31m'; GRN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'

python3 - "$@" <<'PY'
import os
import re
import subprocess
import sys

files = subprocess.run(["git", "ls-files", "*.md"], capture_output=True, text=True, check=True)
LINK = re.compile(r"\]\(([^)\s]+)\)")

broken = []
checked = 0
for path in files.stdout.splitlines():
    if not path or not os.path.exists(path):
        continue
    base = os.path.dirname(path)
    for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
        for target in LINK.findall(line):
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            target = target.split("#", 1)[0]
            if not target:
                continue
            checked += 1
            if not os.path.exists(os.path.normpath(os.path.join(base, target))):
                broken.append((path, lineno, target))

for path, lineno, target in broken:
    print(f"\033[31m✕\033[0m {path}:{lineno}  →  {target}")

print()
if broken:
    print(f"\033[31m✕\033[0m 깨진 링크 {len(broken)}개 / 검사한 링크 {checked}개")
    sys.exit(1)
print(f"\033[32m✓\033[0m 문서 링크 {checked}개 전부 살아 있음")
PY
