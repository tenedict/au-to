#!/usr/bin/env python3
"""Build the CaptureTask integrated development plan as HTML and PDF."""

from __future__ import annotations

import html
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    Image,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Preformatted,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "INTEGRATED-DEVELOPMENT-PLAN.md"
HTML_OUTPUT = ROOT / "docs" / "CaptureTask-Development-Plan.html"
PDF_OUTPUT = ROOT / "output" / "pdf" / "CaptureTask-Development-Plan.pdf"
KOREAN_FONT = Path("/System/Library/Fonts/Supplemental/AppleGothic.ttf")

INK = colors.HexColor("#15231F")
MUTED = colors.HexColor("#5E6F68")
GREEN = colors.HexColor("#197A5B")
GREEN_DARK = colors.HexColor("#105B43")
MINT = colors.HexColor("#E7F4EE")
CREAM = colors.HexColor("#F7F5EF")
LINE = colors.HexColor("#D6E1DC")
AMBER = colors.HexColor("#B86C17")
WHITE = colors.white


def slugify(value: str) -> str:
    cleaned = re.sub(r"[^\w\s가-힣-]", "", value.lower(), flags=re.UNICODE)
    return re.sub(r"[-\s]+", "-", cleaned).strip("-")


def strip_markdown(value: str) -> str:
    value = re.sub(r"!\[([^\]]*)\]\([^)]+\)", r"\1", value)
    value = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", value)
    value = re.sub(r"[*_`]", "", value)
    return value.strip()


def inline_html(value: str) -> str:
    placeholders: list[str] = []

    def stash(fragment: str) -> str:
        placeholders.append(fragment)
        return f"@@INLINE{len(placeholders) - 1}@@"

    value = re.sub(
        r"!\[([^\]]*)\]\(([^)]+)\)",
        lambda match: stash(
            f'<figure><img src="{html.escape(match.group(2))}" '
            f'alt="{html.escape(match.group(1))}"><figcaption>'
            f"{html.escape(match.group(1))}</figcaption></figure>"
        ),
        value,
    )
    value = re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda match: stash(
            f'<a href="{html.escape(match.group(2))}">{html.escape(match.group(1))}</a>'
        ),
        value,
    )
    value = re.sub(
        r"`([^`]+)`",
        lambda match: stash(f"<code>{html.escape(match.group(1))}</code>"),
        value,
    )
    value = html.escape(value)
    value = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", value)
    value = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", value)
    for index, fragment in enumerate(placeholders):
        value = value.replace(f"@@INLINE{index}@@", fragment)
    return value


def split_table_row(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def markdown_to_html(source: str) -> tuple[str, list[tuple[int, str, str]]]:
    lines = source.splitlines()
    parts: list[str] = []
    toc: list[tuple[int, str, str]] = []
    paragraph: list[str] = []
    list_type: str | None = None
    in_code = False
    code_lines: list[str] = []
    code_language = ""
    index = 0

    def flush_paragraph() -> None:
        nonlocal paragraph
        if paragraph:
            parts.append(f"<p>{inline_html(' '.join(item.strip() for item in paragraph))}</p>")
            paragraph = []

    def close_list() -> None:
        nonlocal list_type
        if list_type:
            parts.append(f"</{list_type}>")
            list_type = None

    while index < len(lines):
        line = lines[index]

        if line.startswith("```"):
            flush_paragraph()
            close_list()
            if in_code:
                language_class = f' class="language-{html.escape(code_language)}"' if code_language else ""
                parts.append(
                    f"<pre><code{language_class}>{html.escape(chr(10).join(code_lines))}</code></pre>"
                )
                code_lines = []
                code_language = ""
                in_code = False
            else:
                code_language = line[3:].strip()
                in_code = True
            index += 1
            continue
        if in_code:
            code_lines.append(line)
            index += 1
            continue

        heading = re.match(r"^(#{1,3})\s+(.+)$", line)
        if heading:
            flush_paragraph()
            close_list()
            level = len(heading.group(1))
            title = strip_markdown(heading.group(2))
            anchor = slugify(title)
            if level >= 2:
                toc.append((level, title, anchor))
            parts.append(f'<h{level} id="{anchor}">{inline_html(heading.group(2))}</h{level}>')
            index += 1
            continue

        if (
            "|" in line
            and index + 1 < len(lines)
            and re.match(r"^\s*\|?\s*:?-{3,}", lines[index + 1])
        ):
            flush_paragraph()
            close_list()
            headers = split_table_row(line)
            index += 2
            rows: list[list[str]] = []
            while index < len(lines) and "|" in lines[index] and lines[index].strip():
                rows.append(split_table_row(lines[index]))
                index += 1
            parts.append("<div class=\"table-wrap\"><table><thead><tr>")
            parts.extend(f"<th>{inline_html(cell)}</th>" for cell in headers)
            parts.append("</tr></thead><tbody>")
            for row in rows:
                parts.append("<tr>")
                parts.extend(f"<td>{inline_html(cell)}</td>" for cell in row)
                parts.append("</tr>")
            parts.append("</tbody></table></div>")
            continue

        unordered = re.match(r"^\s*-\s+(.+)$", line)
        ordered = re.match(r"^\s*(\d+)\.\s+(.+)$", line)
        if unordered or ordered:
            flush_paragraph()
            desired = "ul" if unordered else "ol"
            if list_type != desired:
                close_list()
                parts.append(f"<{desired}>")
                list_type = desired
            content = unordered.group(1) if unordered else ordered.group(2)
            parts.append(f"<li>{inline_html(content)}</li>")
            index += 1
            continue

        if line.startswith(">"):
            flush_paragraph()
            close_list()
            parts.append(f"<blockquote>{inline_html(line.lstrip('> ').strip())}</blockquote>")
            index += 1
            continue

        if re.match(r"^\s*---+\s*$", line):
            flush_paragraph()
            close_list()
            parts.append("<hr>")
            index += 1
            continue

        if not line.strip():
            flush_paragraph()
            close_list()
        elif re.match(r"^!\[[^\]]*\]\([^)]+\)$", line.strip()):
            flush_paragraph()
            close_list()
            parts.append(inline_html(line.strip()))
        else:
            paragraph.append(line)
        index += 1

    flush_paragraph()
    close_list()
    return "\n".join(parts), toc


def build_html(markdown_text: str) -> None:
    body, toc = markdown_to_html(markdown_text)
    toc_html = "\n".join(
        f'<a class="toc-level-{level}" href="#{anchor}">{html.escape(title)}</a>'
        for level, title, anchor in toc
    )
    document = f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="CaptureTask iOS 개인 비서 통합 개발 기획서">
  <title>CaptureTask 통합 개발 기획서</title>
  <style>
    :root {{
      --ink: #15231f;
      --muted: #5e6f68;
      --green: #197a5b;
      --green-dark: #105b43;
      --mint: #e7f4ee;
      --cream: #f7f5ef;
      --line: #d6e1dc;
      --amber: #b86c17;
      --white: #ffffff;
      font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo",
        "Noto Sans KR", "Segoe UI", sans-serif;
      color: var(--ink);
      background: var(--cream);
    }}
    * {{ box-sizing: border-box; }}
    html {{ scroll-behavior: smooth; }}
    body {{ margin: 0; line-height: 1.72; }}
    .topbar {{
      position: sticky; top: 0; z-index: 10;
      display: flex; align-items: center; justify-content: space-between;
      padding: 12px 24px; color: var(--white);
      background: rgba(16, 91, 67, .95); backdrop-filter: blur(12px);
    }}
    .brand {{ font-weight: 750; letter-spacing: -.02em; }}
    .print-button {{
      border: 1px solid rgba(255,255,255,.55); border-radius: 999px;
      padding: 8px 14px; color: var(--white); background: transparent;
      font: inherit; cursor: pointer;
    }}
    .layout {{
      display: grid; grid-template-columns: minmax(210px, 260px) minmax(0, 860px);
      gap: 44px; max-width: 1220px; margin: 0 auto; padding: 42px 28px 100px;
    }}
    .toc {{
      position: sticky; top: 86px; align-self: start; max-height: calc(100vh - 110px);
      overflow: auto; padding: 18px; border: 1px solid var(--line);
      border-radius: 18px; background: rgba(255,255,255,.72);
    }}
    .toc-title {{
      margin-bottom: 10px; color: var(--green-dark);
      font-size: .76rem; font-weight: 800; letter-spacing: .12em; text-transform: uppercase;
    }}
    .toc a {{
      display: block; padding: 5px 8px; border-radius: 8px;
      color: var(--muted); font-size: .82rem; line-height: 1.35; text-decoration: none;
    }}
    .toc a:hover {{ color: var(--green-dark); background: var(--mint); }}
    .toc-level-3 {{ padding-left: 20px !important; font-size: .76rem !important; }}
    main {{
      min-width: 0; overflow: hidden; border: 1px solid var(--line);
      border-radius: 28px; background: var(--white);
      box-shadow: 0 20px 60px rgba(21,35,31,.08);
    }}
    article {{ padding: 64px 72px 80px; }}
    h1 {{
      margin: -64px -72px 24px; padding: 92px 72px 36px;
      color: var(--white); background:
        radial-gradient(circle at 85% 10%, rgba(255,255,255,.18), transparent 35%),
        linear-gradient(135deg, var(--green-dark), var(--green));
      font-size: clamp(2.5rem, 6vw, 4.5rem); line-height: 1.08; letter-spacing: -.055em;
    }}
    h2 {{
      margin: 64px 0 18px; padding-top: 14px;
      color: var(--green-dark); font-size: 1.75rem; line-height: 1.25; letter-spacing: -.035em;
      border-top: 1px solid var(--line);
    }}
    h3 {{ margin: 34px 0 12px; color: var(--ink); font-size: 1.16rem; }}
    p {{ margin: 0 0 16px; }}
    blockquote {{
      margin: 0 0 28px; padding: 16px 20px; border-left: 4px solid #82c9ad;
      border-radius: 0 12px 12px 0; color: var(--green-dark); background: var(--mint);
      font-size: 1.05rem; font-weight: 650;
    }}
    ul, ol {{ margin: 10px 0 22px; padding-left: 24px; }}
    li {{ margin: 5px 0; }}
    .table-wrap {{
      margin: 18px 0 28px; overflow-x: auto; border: 1px solid var(--line);
      border-radius: 14px;
    }}
    table {{ width: 100%; border-collapse: collapse; font-size: .89rem; line-height: 1.45; }}
    th {{
      padding: 12px 14px; color: var(--green-dark); background: var(--mint);
      text-align: left; font-weight: 750; vertical-align: top;
    }}
    td {{ padding: 11px 14px; border-top: 1px solid var(--line); vertical-align: top; }}
    tr:nth-child(even) td {{ background: #fbfcfb; }}
    code {{
      padding: .12em .38em; border-radius: 6px; color: #9b3f12; background: #f8eee7;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .88em;
    }}
    pre {{
      margin: 18px 0 28px; padding: 18px 20px; overflow-x: auto;
      border: 1px solid #243a33; border-radius: 14px; color: #ecf8f3; background: #15231f;
      line-height: 1.55;
    }}
    pre code {{ padding: 0; color: inherit; background: transparent; font-size: .82rem; }}
    figure {{ margin: 30px auto; text-align: center; }}
    figure img {{
      display: block; max-width: min(100%, 360px); max-height: 720px; margin: 0 auto;
      border: 1px solid var(--line); border-radius: 28px;
      box-shadow: 0 18px 50px rgba(21,35,31,.14);
    }}
    figcaption {{ margin-top: 10px; color: var(--muted); font-size: .82rem; }}
    hr {{ margin: 48px 0 24px; border: 0; border-top: 1px solid var(--line); }}
    a {{ color: var(--green-dark); text-underline-offset: 3px; }}
    @media (max-width: 900px) {{
      .layout {{ display: block; padding: 18px 12px 60px; }}
      .toc {{ position: relative; top: auto; max-height: 300px; margin-bottom: 18px; }}
      main {{ border-radius: 18px; }}
      article {{ padding: 40px 24px 60px; }}
      h1 {{ margin: -40px -24px 24px; padding: 64px 24px 30px; }}
    }}
    @media print {{
      :root {{ background: white; }}
      .topbar, .toc {{ display: none; }}
      .layout {{ display: block; max-width: none; padding: 0; }}
      main {{ border: 0; border-radius: 0; box-shadow: none; }}
      article {{ padding: 0; }}
      h1 {{ margin: 0; print-color-adjust: exact; -webkit-print-color-adjust: exact; }}
      h2 {{ break-before: page; }}
      h2, h3 {{ break-after: avoid; }}
      table, pre, figure {{ break-inside: avoid; }}
    }}
  </style>
</head>
<body>
  <header class="topbar">
    <div class="brand">CaptureTask · Development Plan</div>
    <button class="print-button" onclick="window.print()">인쇄 / PDF 저장</button>
  </header>
  <div class="layout">
    <nav class="toc" aria-label="문서 목차">
      <div class="toc-title">Contents</div>
      {toc_html}
    </nav>
    <main>
      <article>{body}</article>
    </main>
  </div>
</body>
</html>
"""
    HTML_OUTPUT.write_text(document, encoding="utf-8")


def inline_pdf(value: str) -> str:
    value = html.escape(value.strip())
    value = re.sub(r"!\[([^\]]*)\]\([^)]+\)", r"\1", value)
    value = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<link href="\2" color="#105B43">\1</link>', value)
    value = re.sub(r"`([^`]+)`", r'<font color="#9B3F12">\1</font>', value)
    value = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", value)
    value = re.sub(r"\*([^*]+)\*", r"<i>\1</i>", value)
    return value


class PlanDocTemplate(BaseDocTemplate):
    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph):
            style_name = flowable.style.name
            if style_name in ("PlanH1", "PlanH2", "PlanH3"):
                level = {"PlanH1": 0, "PlanH2": 1, "PlanH3": 2}[style_name]
                text = flowable.getPlainText()
                key = f"heading-{self.seq.nextf('heading')}"
                self.canv.bookmarkPage(key)
                self.canv.addOutlineEntry(text, key, level=level, closed=False)
                if style_name == "PlanH2":
                    self.notify("TOCEntry", (0, text, self.page, key))


def page_decoration(canvas, doc):
    canvas.saveState()
    width, height = A4
    if doc.page > 1:
        canvas.setFillColor(GREEN_DARK)
        canvas.rect(0, height - 10 * mm, width, 10 * mm, fill=1, stroke=0)
        canvas.setFont("CTK", 7.5)
        canvas.setFillColor(WHITE)
        canvas.drawString(18 * mm, height - 6.7 * mm, "CaptureTask · 통합 개발 기획서")
        canvas.setFillColor(MUTED)
        canvas.drawString(18 * mm, 9 * mm, "2026-08-01 · Version 1.0")
        canvas.drawRightString(width - 18 * mm, 9 * mm, f"{doc.page}")
        canvas.setStrokeColor(LINE)
        canvas.line(18 * mm, 13 * mm, width - 18 * mm, 13 * mm)
    canvas.restoreState()


def make_styles():
    pdfmetrics.registerFont(TTFont("CTK", str(KOREAN_FONT)))
    pdfmetrics.registerFontFamily("CTK", normal="CTK", bold="CTK", italic="CTK", boldItalic="CTK")
    sample = getSampleStyleSheet()
    return {
        "cover": ParagraphStyle(
            "PlanH1",
            parent=sample["Title"],
            fontName="CTK",
            fontSize=31,
            leading=39,
            textColor=GREEN_DARK,
            alignment=TA_LEFT,
            spaceAfter=10 * mm,
        ),
        "subtitle": ParagraphStyle(
            "Subtitle",
            fontName="CTK",
            fontSize=13,
            leading=20,
            textColor=GREEN,
            leftIndent=4 * mm,
            borderColor=GREEN,
            borderWidth=0,
            borderPadding=8,
            backColor=MINT,
            spaceAfter=8 * mm,
        ),
        "h2": ParagraphStyle(
            "PlanH2",
            fontName="CTK",
            fontSize=20,
            leading=27,
            textColor=GREEN_DARK,
            spaceAfter=6 * mm,
            keepWithNext=True,
        ),
        "h3": ParagraphStyle(
            "PlanH3",
            fontName="CTK",
            fontSize=12.5,
            leading=18,
            textColor=INK,
            spaceBefore=4 * mm,
            spaceAfter=2.5 * mm,
            keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "Body",
            fontName="CTK",
            fontSize=9.2,
            leading=15.2,
            textColor=INK,
            spaceAfter=3.2 * mm,
            wordWrap="CJK",
        ),
        "small": ParagraphStyle(
            "Small",
            fontName="CTK",
            fontSize=7.7,
            leading=11.5,
            textColor=INK,
            wordWrap="CJK",
        ),
        "table_header": ParagraphStyle(
            "TableHeader",
            fontName="CTK",
            fontSize=7.3,
            leading=10.5,
            textColor=GREEN_DARK,
            wordWrap="CJK",
        ),
        "bullet": ParagraphStyle(
            "Bullet",
            fontName="CTK",
            fontSize=9.1,
            leading=14.5,
            leftIndent=6 * mm,
            firstLineIndent=-4 * mm,
            textColor=INK,
            spaceAfter=1.2 * mm,
            wordWrap="CJK",
        ),
        "quote": ParagraphStyle(
            "Quote",
            fontName="CTK",
            fontSize=10.5,
            leading=17,
            leftIndent=4 * mm,
            rightIndent=4 * mm,
            borderColor=GREEN,
            borderWidth=0,
            borderPadding=8,
            backColor=MINT,
            textColor=GREEN_DARK,
            spaceAfter=5 * mm,
            wordWrap="CJK",
        ),
        "code": ParagraphStyle(
            "Code",
            fontName="CTK",
            fontSize=7.3,
            leading=10.8,
            leftIndent=4 * mm,
            rightIndent=4 * mm,
            borderPadding=7,
            backColor=INK,
            textColor=colors.HexColor("#ECF8F3"),
            spaceAfter=5 * mm,
            wordWrap="CJK",
        ),
        "toc_title": ParagraphStyle(
            "TOCTitle",
            fontName="CTK",
            fontSize=22,
            leading=28,
            textColor=GREEN_DARK,
            spaceAfter=8 * mm,
        ),
        "toc_l1": ParagraphStyle(
            "TOCLevel1",
            fontName="CTK",
            fontSize=9.5,
            leading=15,
            leftIndent=0,
            firstLineIndent=0,
            textColor=INK,
        ),
        "toc_l2": ParagraphStyle(
            "TOCLevel2",
            fontName="CTK",
            fontSize=8,
            leading=12,
            leftIndent=8 * mm,
            firstLineIndent=0,
            textColor=MUTED,
        ),
    }


def table_flowable(rows: list[list[str]], styles, available_width: float) -> Table:
    column_count = max(len(row) for row in rows)
    normalized = [row + [""] * (column_count - len(row)) for row in rows]
    if column_count == 2:
        widths = [available_width * 0.30, available_width * 0.70]
    elif column_count == 3:
        widths = [available_width * 0.19, available_width * 0.40, available_width * 0.41]
    elif column_count == 4:
        widths = [
            available_width * 0.14,
            available_width * 0.25,
            available_width * 0.43,
            available_width * 0.18,
        ]
    else:
        widths = [available_width / column_count] * column_count
    data = []
    for row_index, row in enumerate(normalized):
        style = styles["table_header"] if row_index == 0 else styles["small"]
        data.append([Paragraph(inline_pdf(cell), style) for cell in row])
    table = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), MINT),
                ("TEXTCOLOR", (0, 0), (-1, 0), GREEN_DARK),
                ("GRID", (0, 0), (-1, -1), 0.35, LINE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [WHITE, colors.HexColor("#FBFCFB")]),
            ]
        )
    )
    return table


def markdown_to_pdf_story(markdown_text: str, styles, content_width: float):
    lines = markdown_text.splitlines()
    story = []
    paragraph: list[str] = []
    in_code = False
    code_lines: list[str] = []
    first_heading = True
    toc_added = False
    index = 0
    ordered_index = 0

    def flush_paragraph():
        nonlocal paragraph
        if paragraph:
            text = " ".join(item.strip() for item in paragraph)
            story.append(Paragraph(inline_pdf(text), styles["body"]))
            paragraph = []

    while index < len(lines):
        line = lines[index]

        if line.startswith("```"):
            flush_paragraph()
            if in_code:
                code_block = Preformatted(
                    "\n".join(code_lines),
                    styles["code"],
                    maxLineLength=96,
                )
                code_table = Table([[code_block]], colWidths=[content_width], hAlign="LEFT")
                code_table.setStyle(
                    TableStyle(
                        [
                            ("BACKGROUND", (0, 0), (-1, -1), INK),
                            ("BOX", (0, 0), (-1, -1), 0.4, GREEN_DARK),
                            ("LEFTPADDING", (0, 0), (-1, -1), 7),
                            ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                            ("TOPPADDING", (0, 0), (-1, -1), 7),
                            ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                        ]
                    )
                )
                story.append(code_table)
                story.append(Spacer(1, 5 * mm))
                code_lines = []
                in_code = False
            else:
                in_code = True
            index += 1
            continue
        if in_code:
            code_lines.append(line)
            index += 1
            continue

        heading = re.match(r"^(#{1,3})\s+(.+)$", line)
        if heading:
            flush_paragraph()
            level = len(heading.group(1))
            title = strip_markdown(heading.group(2))
            if level == 1 and first_heading:
                story.append(Spacer(1, 23 * mm))
                story.append(Paragraph(inline_pdf(title), styles["cover"]))
                first_heading = False
            elif level == 2:
                if not toc_added:
                    story.append(Spacer(1, 7 * mm))
                    story.append(PageBreak())
                    story.append(Paragraph("목차", styles["toc_title"]))
                    toc = TableOfContents()
                    toc.levelStyles = [styles["toc_l1"], styles["toc_l2"]]
                    toc.dotsMinLevel = 0
                    story.append(toc)
                    story.append(PageBreak())
                    toc_added = True
                elif not title.startswith(("18. ", "19. ")):
                    story.append(PageBreak())
                story.append(Paragraph(inline_pdf(title), styles["h2"]))
            elif level == 3:
                story.append(Paragraph(inline_pdf(title), styles["h3"]))
            index += 1
            continue

        if (
            "|" in line
            and index + 1 < len(lines)
            and re.match(r"^\s*\|?\s*:?-{3,}", lines[index + 1])
        ):
            flush_paragraph()
            rows = [split_table_row(line)]
            index += 2
            while index < len(lines) and "|" in lines[index] and lines[index].strip():
                rows.append(split_table_row(lines[index]))
                index += 1
            story.append(table_flowable(rows, styles, content_width))
            story.append(Spacer(1, 4 * mm))
            continue

        unordered = re.match(r"^\s*-\s+(.+)$", line)
        ordered = re.match(r"^\s*(\d+)\.\s+(.+)$", line)
        if unordered or ordered:
            flush_paragraph()
            if ordered:
                ordered_index = int(ordered.group(1))
                label = f"{ordered_index}."
                value = ordered.group(2)
            else:
                ordered_index = 0
                label = "•"
                value = unordered.group(1)
            story.append(Paragraph(f"{label} {inline_pdf(value)}", styles["bullet"]))
            index += 1
            continue

        if line.startswith(">"):
            flush_paragraph()
            story.append(Paragraph(inline_pdf(line.lstrip("> ").strip()), styles["subtitle"]))
            index += 1
            continue

        image_match = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)$", line.strip())
        if image_match:
            flush_paragraph()
            image_path = (SOURCE.parent / image_match.group(2)).resolve()
            if image_path.exists():
                image = Image(str(image_path))
                max_height = 165 * mm
                max_width = 78 * mm
                scale = min(max_width / image.imageWidth, max_height / image.imageHeight)
                image.drawWidth = image.imageWidth * scale
                image.drawHeight = image.imageHeight * scale
                caption = Paragraph(inline_pdf(image_match.group(1)), styles["small"])
                story.append(KeepTogether([image, Spacer(1, 2 * mm), caption]))
                story.append(Spacer(1, 4 * mm))
            index += 1
            continue

        if re.match(r"^\s*---+\s*$", line):
            flush_paragraph()
            story.append(Spacer(1, 3 * mm))
            index += 1
            continue

        if not line.strip():
            flush_paragraph()
        else:
            paragraph.append(line)
        index += 1

    flush_paragraph()
    return story


def build_pdf(markdown_text: str) -> None:
    PDF_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    styles = make_styles()
    left = right = 18 * mm
    top = 18 * mm
    bottom = 17 * mm
    content_width = A4[0] - left - right
    frame = Frame(left, bottom, content_width, A4[1] - top - bottom, id="normal")
    template = PageTemplate(id="plan", frames=[frame], onPage=page_decoration)
    doc = PlanDocTemplate(
        str(PDF_OUTPUT),
        pagesize=A4,
        leftMargin=left,
        rightMargin=right,
        topMargin=top,
        bottomMargin=bottom,
        title="CaptureTask 통합 개발 기획서",
        author="CaptureTask Project",
        subject="iOS screenshot-to-task assistant product and engineering plan",
        creator="CaptureTask documentation build",
    )
    doc.addPageTemplates([template])
    story = markdown_to_pdf_story(markdown_text, styles, content_width)
    doc.multiBuild(story)


def main() -> None:
    markdown_text = SOURCE.read_text(encoding="utf-8")
    build_html(markdown_text)
    build_pdf(markdown_text)
    print(f"HTML: {HTML_OUTPUT}")
    print(f"PDF:  {PDF_OUTPUT}")


if __name__ == "__main__":
    main()
