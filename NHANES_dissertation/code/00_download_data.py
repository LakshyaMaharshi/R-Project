"""Download the NHANES 2013-2014 files this analysis uses, into ../data/.

The repository already ships these files, so you only need this script if you want to
re-fetch them from source or verify provenance.

IMPORTANT - the URL pattern changed. Older NHANES documentation (and many tutorials)
give links of the form

    https://wwwn.cdc.gov/Nchs/Nhanes/2013-2014/DEMO_H.XPT        <- now returns a 404 HTML page

CDC restructured the site, and that pattern now silently returns an HTML "Page Not Found"
document with HTTP 200-style content rather than an error, so a naive download leaves you
with a 20 KB HTML file named `.xpt`. The working pattern is

    https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/DEMO_H.xpt

This script uses the working pattern and verifies that each download really is a SAS
transport file before saving it.

Usage:  python 00_download_data.py
"""
import sys
import urllib.request
from pathlib import Path

BASE = "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles"
DATA = Path(__file__).resolve().parent.parent / "data"

FILES = {
    "DEMO_H.xpt":   "Demographics: age, sex, race, education, income, survey design vars",
    "RXQ_RX_H.xpt": "Prescription medications (one row per prescription)",
    "CFQ_H.xpt":    "Cognitive functioning: DSST (CFDDS), animal fluency (CFDAST)",
    "MCQ_H.xpt":    "Medical conditions: stroke, cardiovascular disease",
    "DIQ_H.xpt":    "Diabetes",
    "DPQ_H.xpt":    "Depression screener (PHQ-9)",
    "HSQ_H.xpt":    "Self-rated health",
}

# SAS transport files begin with this marker; an HTML error page will not.
XPORT_MAGIC = b"HEADER RECORD"


def main():
    DATA.mkdir(parents=True, exist_ok=True)
    failed = []
    for name, desc in FILES.items():
        dest = DATA / name
        if dest.exists():
            print(f"[skip] {name} already present - {desc}")
            continue
        url = f"{BASE}/{name}"
        print(f"[get ] {name} ... ", end="", flush=True)
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                blob = r.read()
        except Exception as exc:
            print(f"FAILED ({exc})")
            failed.append(name)
            continue
        if not blob.startswith(XPORT_MAGIC):
            print(f"FAILED - got {len(blob)} bytes that are not a SAS transport file "
                  "(the URL pattern may have changed again)")
            failed.append(name)
            continue
        dest.write_bytes(blob)
        print(f"ok ({len(blob):,} bytes)")

    print("\nNot downloaded by this script (already in the repository):")
    print("  aas_combined.csv  - anticholinergic scale reference list, from the")
    print("                      Mur et al. (2025) supplementary repository")
    print("  iacb_scores.csv   - IACB scores; regenerate with 08_extract_iacb.py")
    print("  NHANES_2013_2014_MORT_2019_PUBLIC.dat - linked mortality file, unused")
    print("                      by the dissertation (see code/archive/)")

    if failed:
        print("\nFAILED:", ", ".join(failed))
        sys.exit(1)
    print("\nAll files present in", DATA)


if __name__ == "__main__":
    main()
