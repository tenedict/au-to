#!/usr/bin/env python3
"""개발 보고서를 한 파일짜리 HTML 로 만든다.

    python3 scripts/build-report.py

`docs/report/template.html` 의 `{{IMG:이름}}` 자리에 `docs/report/assets/이름.png` 를
base64 로 심어 `output/report/CaptureTask-Report.html` 을 만든다.

**왜 심는가** — 보고서는 메일로 보내지고 다른 컴퓨터에서 열린다. 이미지를 바깥
파일로 두면 링크가 깨진 채로 전달되고, 받은 사람은 그림이 없는 문서를 읽게 된다.
한 파일이면 그런 일이 없다.

생성물은 커밋 대상이 아니라고 볼 수도 있지만, 이 저장소는 이미 `output/pdf/` 의
기획서를 함께 올린다 — 저장소를 받은 사람이 도구 없이 바로 열어 볼 수 있어야 한다.
소스(`docs/report/`)와 생성물(`output/report/`)은 자리를 나눠 둔다.
"""

import base64
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "docs" / "report" / "template.html"
ASSETS = ROOT / "docs" / "report" / "assets"
OUTPUT = ROOT / "output" / "report" / "CaptureTask-Report.html"

PLACEHOLDER = re.compile(r"\{\{IMG:([A-Za-z0-9._-]+)\}\}")


def main() -> int:
    if not TEMPLATE.exists():
        print(f"✕ 템플릿이 없습니다: {TEMPLATE}", file=sys.stderr)
        return 1

    html = TEMPLATE.read_text(encoding="utf-8")
    missing: list[str] = []

    def embed(match: re.Match[str]) -> str:
        name = match.group(1)
        path = ASSETS / f"{name}.png"
        if not path.exists():
            missing.append(name)
            return match.group(0)
        data = base64.b64encode(path.read_bytes()).decode()
        return f'<img alt="{name}" src="data:image/png;base64,{data}">'

    html = PLACEHOLDER.sub(embed, html)

    if missing:
        print("✕ 그림을 찾지 못했습니다:", ", ".join(sorted(set(missing))), file=sys.stderr)
        print(f"  {ASSETS} 를 확인하세요.", file=sys.stderr)
        return 1

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(html, encoding="utf-8")

    size = OUTPUT.stat().st_size / 1024 / 1024
    figures = len(re.findall(r"<img ", html))
    print(f"✓ {OUTPUT.relative_to(ROOT)}  ({size:.2f} MB · 그림 {figures}개)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
