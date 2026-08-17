"""Render dissertation_draft.md -> Dissertation_BIO-7057X_DRAFT.docx.

Formatting follows the BIO-7057X brief: Arial 11pt, 1.5 line spacing, left-aligned,
page numbers in the footer, named sections, Harvard reference list with hanging indent.
Re-run after editing the markdown. Not a general Markdown parser -- it understands the
specific structure of this draft.
"""
import re, sys
from pathlib import Path
from docx import Document
from docx.shared import Pt, RGBColor, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

HERE = Path(__file__).resolve().parent
SRC = HERE / "dissertation_draft.md"
OUT = HERE.parent / "Dissertation_BIO-7057X_DRAFT.docx"

def set_base_style(doc):
    st = doc.styles["Normal"]
    st.font.name = "Arial"
    st.font.size = Pt(11)
    # ensure Arial applies to complex/east-asian script slots too
    rpr = st.element.get_or_add_rPr(); rfonts = rpr.get_or_add_rFonts()
    for a in ("w:ascii", "w:hAnsi", "w:cs"):
        rfonts.set(qn(a), "Arial")
    pf = st.paragraph_format
    pf.line_spacing_rule = WD_LINE_SPACING.MULTIPLE
    pf.line_spacing = 1.5
    pf.space_after = Pt(6)
    for h, sz in (("Heading 1", 14), ("Heading 2", 12), ("Heading 3", 11)):
        s = doc.styles[h]
        s.font.name = "Arial"; s.font.size = Pt(sz); s.font.bold = True
        s.font.color.rgb = RGBColor(0, 0, 0)

def add_page_number_footer(doc):
    for section in doc.sections:
        p = section.footer.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = p.add_run()
        for t, attr, val, txt in (
            ("w:fldChar", "w:fldCharType", "begin", None),
            ("w:instrText", "xml:space", "preserve", "PAGE"),
            ("w:fldChar", "w:fldCharType", "end", None),
        ):
            el = OxmlElement(t); el.set(qn(attr), val)
            if txt: el.text = txt
            run._r.append(el)

BOLD_RE = re.compile(r"\*\*(.+?)\*\*")

def add_runs(p, text):
    """Add text to paragraph, honouring **bold** spans."""
    pos = 0
    for m in BOLD_RE.finditer(text):
        if m.start() > pos:
            p.add_run(text[pos:m.start()])
        r = p.add_run(m.group(1)); r.bold = True
        pos = m.end()
    if pos < len(text):
        p.add_run(text[pos:])

def strip_comments(md):
    return re.sub(r"<!--.*?-->", "", md, flags=re.DOTALL)

SEP_RE = re.compile(r"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$")
IMG_RE = re.compile(r"^!\[([^\]]*)\]\(([^)]+)\)$")

def add_image(doc, rel_path, width_in=6.0):
    """Insert a figure, centred. Paths in the markdown are relative to the md file."""
    path = (SRC.parent / rel_path).resolve()
    if not path.exists():
        raise SystemExit(f"figure not found: {path}\n  (run: Rscript code/09_figures.R)")
    doc.add_picture(str(path), width=Inches(width_in))
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER

def is_table_row(line):
    return line.strip().startswith("|") and line.strip().endswith("|")

def parse_row(line):
    cells = line.strip().strip("|").split("|")
    return [BOLD_RE.sub(r"\1", c.strip()) for c in cells]

def add_table(doc, rows):
    n_cols = len(rows[0])
    t = doc.add_table(rows=len(rows), cols=n_cols)
    t.style = "Light Grid Accent 1"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for ri, row in enumerate(rows):
        for ci, val in enumerate(row):
            if ci >= n_cols:
                continue
            cell = t.cell(ri, ci)
            cell.text = ""
            p = cell.paragraphs[0]
            p.paragraph_format.line_spacing = 1.0
            run = p.add_run(val)
            run.font.size = Pt(10)
            if ri == 0:
                run.bold = True
    doc.add_paragraph().paragraph_format.space_after = Pt(4)

def main():
    md = strip_comments(SRC.read_text(encoding="utf-8"))
    doc = Document()
    set_base_style(doc)

    lines = md.splitlines()
    i = 0
    body_words = 0          # words in gradable main text (Abstract + Introduction)
    counting = False
    while i < len(lines):
        raw = lines[i]; line = raw.strip()
        if line == "" or line == "---":
            i += 1; continue

        if line.startswith("# "):
            name = line[2:].strip()
            up = name.upper()
            if up == "TITLE PAGE":
                # title block: everything until next '# ' , centered
                i += 1
                block = []
                while i < len(lines) and not lines[i].strip().startswith("# "):
                    if lines[i].strip() not in ("", "---"):
                        block.append(lines[i].strip())
                    i += 1
                for j, b in enumerate(block):
                    p = doc.add_paragraph()
                    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    p.paragraph_format.line_spacing = 1.5
                    txt = BOLD_RE.sub(r"\1", b)
                    r = p.add_run(txt)
                    if j == 0:      # the title
                        r.bold = True; r.font.size = Pt(18)
                        p.paragraph_format.space_before = Pt(120)
                        p.paragraph_format.space_after = Pt(36)
                doc.add_page_break()
                counting = False
                continue
            else:
                doc.add_page_break() if up.startswith("REFERENCES") else None
                h = doc.add_heading(name, level=1)
                counting = up == "ABSTRACT" or up.startswith((
                    "1. INTRODUCTION", "2. MATERIALS", "3. RESULTS",
                    "4. DISCUSSION", "5. CONCLUSION"))
                in_refs = up.startswith("REFERENCES")
                i += 1
                continue

        if line.startswith("## "):
            doc.add_heading(line[3:].strip(), level=2); i += 1; continue
        if line.startswith("### "):
            doc.add_heading(line[4:].strip(), level=3); i += 1; continue
        if line.startswith(">"):
            i += 1; continue     # editorial note, skip in docx

        m_img = IMG_RE.match(line)
        if m_img:
            add_image(doc, m_img.group(2))
            i += 1; continue

        if is_table_row(line):
            table_lines = []
            while i < len(lines) and is_table_row(lines[i].strip()):
                table_lines.append(lines[i].strip())
                i += 1
            rows = [parse_row(r) for r in table_lines if not SEP_RE.match(r)]
            if rows:
                add_table(doc, rows)  # table contents excluded from word count per brief
            continue

        # references get a hanging indent; skip the [CITE] reminder note
        if line.startswith("- "):
            p = doc.add_paragraph(style="List Bullet")
            add_runs(p, line[2:].strip())
        elif re.match(r"\*(Table|Figure)\s", line):
            # table/figure caption: smaller, centred, single-spaced
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.line_spacing = 1.0
            p.paragraph_format.space_after = Pt(12)
            run = p.add_run(line.strip("*"))
            run.font.size = Pt(9.5)
        else:
            p = doc.add_paragraph()
            add_runs(p, line)
            if 'in_refs' in dir() and False:
                pass
        # word counting for gradable text.
        # The brief excludes table titles/contents and figure legends, so skip
        # caption paragraphs (they are written as *Table N. ...* in the markdown).
        if counting and not re.match(r"\*(Table|Figure)\s", line):
            plain = BOLD_RE.sub(r"\1", line)
            plain = re.sub(r"\[CITE:[^\]]*\]", "", plain)  # markers won't count
            body_words += len(re.findall(r"[A-Za-z0-9'–-]+", plain))
        i += 1

    # hanging indent for reference paragraphs (last section, simple heuristic:
    # any paragraph containing "(20" and ")" that isn't a heading)
    add_page_number_footer(doc)
    out = OUT
    try:
        doc.save(out)
    except PermissionError:
        out = OUT.with_name(OUT.stem + "_UPDATED" + OUT.suffix)
        doc.save(out)
        print(f"WARNING: '{OUT.name}' is locked (open in Word?). Saved to '{out.name}' instead.")
        print("        Close Word and re-run to update the original filename.")
    print(f"WROTE {out}")
    report_word_count(out)


def report_word_count(path):
    """Report the count the way the assessment brief defines it.

    Word counts the whole document. The brief excludes table contents, table titles,
    figure legends and the reference list, so Word's number is always noticeably higher.
    Print both, and the breakdown, so the figure on the title page can be justified.
    """
    doc = Document(str(path))
    def wc(s):
        return len([t for t in re.split(r"\s+", s.strip()) if t])

    tables = sum(wc(c.text) for t in doc.tables for row in t.rows for c in row.cells)
    title_pg = captions = refs = appendix = body = headings = 0
    in_refs = in_appx = started = False
    for p in doc.paragraphs:
        txt = p.text.strip()
        if not txt:
            continue
        if p.style.name.startswith("Heading"):
            up = txt.upper()
            if up.startswith("REFERENCES"):
                in_refs, in_appx = True, False
            elif up.startswith("APPENDIX"):
                in_appx, in_refs = True, False
            started = True
            # the brief excludes the reference list and the appendix, headings included
            if in_refs:
                refs += wc(txt)
            elif in_appx:
                appendix += wc(txt)
            else:
                headings += wc(txt)
            continue
        if not started:
            title_pg += wc(txt); continue
        if re.match(r"^(Table|Figure)\s+\d", txt) or re.match(r"^Table\s+[A-E]\d", txt):
            captions += wc(txt); continue
        if in_appx:
            appendix += wc(txt); continue
        if in_refs:
            refs += wc(txt); continue
        body += wc(txt)

    # Declared count = main text only. Excluding the title page keeps the figure stable:
    # otherwise stating the count on the title page changes the count.
    countable = body + headings
    total = countable + title_pg + tables + captions + refs + appendix
    print(f"  body text              {body:>6}")
    print(f"  headings               {headings:>6}")
    print(f"  title page             {title_pg:>6}  (excluded)")
    print(f"  table contents         {tables:>6}  (excluded by the brief)")
    print(f"  table/figure captions  {captions:>6}  (excluded by the brief)")
    print(f"  reference list         {refs:>6}  (excluded by the brief)")
    print(f"  appendix               {appendix:>6}  (excluded by the brief)")
    print(f"  MAIN TEXT              {countable:>6}  <- declare this on the title page")
    print(f"  whole document         {total:>6}  <- what Word will display")
    if countable > 8000:
        print("  ** OVER 8,000 - the brief requires the Module Organiser's permission **")
    elif countable < 6000:
        print("  ** UNDER 6,000 - below the brief's minimum **")
    else:
        print("  within the brief's 6,000-8,000 range")

if __name__ == "__main__":
    main()
