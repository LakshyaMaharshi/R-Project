"""Extract the IACB (International Anticholinergic Burden) drug scores from the
supervisor-supplied paper into data/scales/iacb_scores.csv.

Source: reference/ssrn-3777231 (1).pdf
        Fleetwood et al., "A novel machine learning approach to anticholinergic burden
        quantification", SSRN preprint 3777231 (NOT peer reviewed). Saber Sami is senior
        author. Supplementary drug list, pages 22-23 of the PDF (labelled "6 of 8"/"7 of 8").

Why coordinates and not text order:
  The list is a 5-column table (Score 0|1|2|3|4). Rows are RAGGED - columns run out at
  different points, and page 23 has an EMPTY Score-3 column while Score-4 continues.
  Reading the extracted text left-to-right therefore mis-assigns scores: every Score-4
  drug on page 23 (protriptyline, amitriptyline, atropine, ...) would be recorded as
  Score 3. So each drug's score is taken from the x-coordinate of its text span, which
  is exact regardless of raggedness.

Verified: parsed counts per page match the rendered pages read visually
  page 22 -> 20/20/20/16/20   page 23 -> 23/45/11/0/30   total 205 drugs.

Note: drug names are reproduced exactly as printed in the paper, including its own
spellings ("choral", "thyroxin", "dydogesterone", "caritine") and the one brand name
("coumadin"). Normalisation for matching happens in the R script, not here.
"""
import collections
import csv
from pathlib import Path

import fitz  # pymupdf

HERE = Path(__file__).resolve().parent
PDF = HERE.parent / "reference" / "ssrn-3777231 (1).pdf"
OUT = HERE.parent / "data" / "scales" / "iacb_scores.csv"

PAGES = (21, 22)                                   # 0-based indices
ANCHORS = [76.5, 172.5, 267.4, 368.3, 447.1]       # x of Score 0..4 columns
TOL = 6.0


# The PDF sets "fl"/"fi" as single typographic ligature glyphs, and PyMuPDF returns them
# as those Unicode characters rather than as plain letters. Left unconverted, entries such
# as "fluoxetine" and "moxifloxacin" can never match a drug name typed normally.
LIGATURES = {
    "ﬀ": "ff", "ﬁ": "fi", "ﬂ": "fl", "ﬃ": "ffi", "ﬄ": "ffl",
    "ﬅ": "st", "ﬆ": "st",
}


def deligature(s):
    for lig, plain in LIGATURES.items():
        s = s.replace(lig, plain)
    return s


def column_of(x):
    for i, a in enumerate(ANCHORS):
        if abs(x - a) <= TOL:
            return i
    return None


def main():
    doc = fitz.open(PDF)

    # The drug table shares its "Score 0..4" header text with Table 3 (keywords) on the
    # same page. Table 3 sits at different x anchors, but to be safe we also ignore
    # everything above the drug table's own header.
    header_y = None
    for block in doc[PAGES[0]].get_text("dict")["blocks"]:
        for line in block.get("lines", []):
            for span in line["spans"]:
                if span["text"].strip() == "Score 0" and abs(span["bbox"][0] - ANCHORS[0]) < 1:
                    header_y = span["bbox"][1]
    if header_y is None:
        raise SystemExit("could not locate the drug-table header - PDF layout changed?")

    cells = collections.defaultdict(dict)          # (page, y) -> {col: text}
    for pi in PAGES:
        for block in doc[pi].get_text("dict")["blocks"]:
            for line in block.get("lines", []):
                for span in line["spans"]:
                    text = deligature(span["text"]).strip()
                    if not text:
                        continue
                    x, y = span["bbox"][0], round(span["bbox"][1], 1)
                    if pi == PAGES[0] and y <= header_y + 1:
                        continue                   # keyword table / header
                    col = column_of(x)
                    if col is None:
                        continue
                    prev = cells[(pi, y)].get(col, "")
                    cells[(pi, y)][col] = (prev + " " + text).strip()

    rows = []
    for key in sorted(cells):
        for col, text in sorted(cells[key].items()):
            if text and text[0].islower():         # drug names are lowercase in this table
                rows.append((text, col))

    seen, deduped = set(), []
    for drug, score in rows:
        if drug in seen:
            print(f"  [dup] {drug} appears more than once - keeping first")
            continue
        seen.add(drug)
        deduped.append((drug, score))

    per_score = collections.Counter(s for _, s in deduped)
    print("drugs extracted:", len(deduped))
    print("per score:", {f"score {k}": per_score[k] for k in sorted(per_score)})

    expected = {0: 43, 1: 65, 2: 31, 3: 16, 4: 50}   # verified against rendered pages
    if {k: per_score[k] for k in sorted(per_score)} != expected:
        raise SystemExit(f"FAIL: counts {dict(per_score)} != visually verified {expected}")

    checks = {"oxybutynin": 4, "tolterodine": 4, "amitriptyline": 4, "solifenacin": 4,
              "probenecid": 0, "pravastatin": 0, "salbutamol": 0, "quetiapine": 3}
    lookup = dict(deduped)
    for drug, want in checks.items():
        got = lookup.get(drug)
        if got != want:
            raise SystemExit(f"FAIL sanity check: {drug} scored {got}, expected {want}")
    print("sanity checks passed (potent drugs score high, inert drugs score 0)")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["drug", "iacb_score"])
        for drug, score in sorted(deduped):
            w.writerow([drug, score])
    print("wrote", OUT)


if __name__ == "__main__":
    main()
