"""Download the NHANES files this analysis uses, for whichever cycle you ask for.

    python 00_download_data.py                  # 2013-2014 (the dissertation cycle)
    python 00_download_data.py 2011-2012        # the validation cycle Dr Sami asked for

Files land in ../data/<cycle>/. The 2013-2014 set already ships with the repository, so
you only need this script for the 2011-2012 cycle or to re-verify provenance.

IMPORTANT - the URL pattern changed. Older NHANES documentation (and many tutorials)
give links of the form

    https://wwwn.cdc.gov/Nchs/Nhanes/2013-2014/DEMO_H.XPT        <- now returns a 404 HTML page

CDC restructured the site, and that pattern now silently returns an HTML "Page Not Found"
document rather than an error, so a naive download leaves you with a 20 KB HTML file
named `.xpt`. The working pattern is

    https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/DEMO_H.xpt

This script uses the working pattern and verifies that each download really is a SAS
transport file before saving it.
"""
import sys
import urllib.request
from pathlib import Path

# Mirrors code/config.R - the cycle suffix and the year that goes in the URL. Keep the
# two in step; config.R is the authority for the R side, this is its Python twin.
CYCLES = {
    "2013-2014": {"suffix": "_H", "url_year": "2013"},
    "2011-2012": {"suffix": "_G", "url_year": "2011"},
}
DEFAULT_CYCLE = "2013-2014"

# Stem -> what it is for. The suffix is added per cycle.
FILES = {
    "DEMO":   "Demographics: age, sex, race, education, income, survey design vars",
    "RXQ_RX": "Prescription medications (one row per prescription)",
    "CFQ":    "Cognitive functioning: DSST (CFDDS), animal fluency (CFDAST), CERAD recall (CFDCSR)",
    "MCQ":    "Medical conditions: stroke, cardiovascular disease",
    "DIQ":    "Diabetes",
    "DPQ":    "Depression screener (PHQ-9)",
    "HSQ":    "Self-rated health",
}

XPORT_MAGIC = b"HEADER RECORD"   # SAS transport marker; an HTML error page will not have it


def main() -> None:
    cycle = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_CYCLE
    if cycle not in CYCLES:
        sys.exit(f"unknown cycle {cycle!r} - known: {', '.join(CYCLES)}")

    suffix = CYCLES[cycle]["suffix"]
    base = f"https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/{CYCLES[cycle]['url_year']}/DataFiles"
    dest_dir = Path(__file__).resolve().parent.parent / "data" / cycle
    dest_dir.mkdir(parents=True, exist_ok=True)
    print(f"cycle {cycle} (suffix {suffix}) -> {dest_dir}")

    failed = []
    for stem, desc in FILES.items():
        name = f"{stem}{suffix}.xpt"
        dest = dest_dir / name
        if dest.exists():
            print(f"[skip] {name} already present - {desc}")
            continue
        print(f"[get ] {name} ... ", end="", flush=True)
        try:
            with urllib.request.urlopen(f"{base}/{name}", timeout=180) as r:
                blob = r.read()
        except Exception as exc:
            print(f"FAILED ({exc})")
            failed.append(name)
            continue
        if not blob.startswith(XPORT_MAGIC):
            print(f"FAILED - got {len(blob):,} bytes that are not a SAS transport file "
                  "(the URL pattern may have changed again)")
            failed.append(name)
            continue
        dest.write_bytes(blob)
        print(f"ok ({len(blob):,} bytes)")

    print("\nNot downloaded by this script (they are not cycle-specific, and ship with the repo):")
    print("  data/scales/aas_combined.csv - anticholinergic scale reference list, from the")
    print("                                 Mur et al. (2025) supplementary repository")
    print("  data/scales/iacb_scores.csv  - IACB scores; regenerate with 08_extract_iacb.py")

    if failed:
        print("\nFAILED:", ", ".join(failed))
        sys.exit(1)
    print(f"\nAll {cycle} files present in {dest_dir}")


if __name__ == "__main__":
    main()
