from __future__ import annotations

from pathlib import Path
import re

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    PageBreak,
    Paragraph,
    Preformatted,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs" / "SIMUFIRE_ARCHITECTURE_TWO_ZONE.md"
OUTPUT = ROOT / "docs" / "SIMUFIRE_ARCHITECTURE_TWO_ZONE.pdf"


def _clean_inline(text: str) -> str:
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = re.sub(r"`([^`]+)`", r"<font name='Courier'>\1</font>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    return text


def _footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.HexColor("#666666"))
    canvas.drawString(1.6 * cm, 1.0 * cm, "SimuFire - arquitectura y modelo two-zone")
    canvas.drawRightString(19.4 * cm, 1.0 * cm, f"Pagina {doc.page}")
    canvas.restoreState()


def build() -> None:
    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(
        name="TitleCustom",
        parent=styles["Title"],
        fontName="Helvetica-Bold",
        fontSize=22,
        leading=27,
        alignment=TA_CENTER,
        spaceAfter=18,
        textColor=colors.HexColor("#1f2933"),
    ))
    styles.add(ParagraphStyle(
        name="H1Custom",
        parent=styles["Heading1"],
        fontName="Helvetica-Bold",
        fontSize=15,
        leading=19,
        spaceBefore=12,
        spaceAfter=8,
        textColor=colors.HexColor("#174a7c"),
    ))
    styles.add(ParagraphStyle(
        name="H2Custom",
        parent=styles["Heading2"],
        fontName="Helvetica-Bold",
        fontSize=12,
        leading=15,
        spaceBefore=8,
        spaceAfter=5,
        textColor=colors.HexColor("#2f5d62"),
    ))
    styles.add(ParagraphStyle(
        name="BodyCustom",
        parent=styles["BodyText"],
        fontName="Helvetica",
        fontSize=9.2,
        leading=12.8,
        spaceAfter=5,
    ))
    styles.add(ParagraphStyle(
        name="BulletCustom",
        parent=styles["BodyText"],
        fontName="Helvetica",
        fontSize=9.0,
        leading=12.3,
        leftIndent=12,
        firstLineIndent=-8,
        spaceAfter=3,
    ))
    code_style = ParagraphStyle(
        name="Code",
        fontName="Courier",
        fontSize=7.4,
        leading=9,
        leftIndent=4,
        rightIndent=4,
        spaceBefore=4,
        spaceAfter=6,
        backColor=colors.HexColor("#f4f6f8"),
        borderColor=colors.HexColor("#d9e2ec"),
        borderWidth=0.5,
        borderPadding=5,
    )

    lines = SOURCE.read_text(encoding="utf-8").splitlines()
    story = []
    in_code = False
    code_lines: list[str] = []
    list_buffer: list[str] = []

    def flush_list():
        nonlocal list_buffer
        for item in list_buffer:
            story.append(Paragraph("&bull; " + _clean_inline(item), styles["BulletCustom"]))
        list_buffer = []

    def flush_code():
        nonlocal code_lines
        if code_lines:
            story.append(Preformatted("\n".join(code_lines), code_style))
            code_lines = []

    first_heading = True
    for raw in lines:
        line = raw.rstrip()
        if line.startswith("```"):
            if in_code:
                flush_code()
                in_code = False
            else:
                flush_list()
                in_code = True
            continue
        if in_code:
            code_lines.append(line)
            continue
        if not line.strip():
            flush_list()
            story.append(Spacer(1, 2))
            continue
        if line.startswith("# "):
            flush_list()
            story.append(Paragraph(_clean_inline(line[2:]), styles["TitleCustom"]))
            first_heading = False
        elif line.startswith("## "):
            flush_list()
            if not first_heading and line.startswith("## 7. "):
                story.append(PageBreak())
            story.append(Paragraph(_clean_inline(line[3:]), styles["H1Custom"]))
        elif line.startswith("### "):
            flush_list()
            story.append(Paragraph(_clean_inline(line[4:]), styles["H2Custom"]))
        elif line.startswith("- "):
            list_buffer.append(line[2:])
        elif re.match(r"^\d+\. ", line):
            flush_list()
            story.append(Paragraph(_clean_inline(line), styles["BodyCustom"]))
        else:
            flush_list()
            story.append(Paragraph(_clean_inline(line), styles["BodyCustom"]))

    flush_list()
    flush_code()

    doc = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        rightMargin=1.6 * cm,
        leftMargin=1.6 * cm,
        topMargin=1.5 * cm,
        bottomMargin=1.5 * cm,
        title="SimuFire: arquitectura actual y modelo de dos zonas",
    )
    doc.build(story, onFirstPage=_footer, onLaterPages=_footer)


if __name__ == "__main__":
    build()
    print(OUTPUT)
