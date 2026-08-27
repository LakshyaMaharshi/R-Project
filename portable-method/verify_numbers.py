# Verification harness — generic template. Copy into a project and adapt the CLAIMS block.
#
# WHAT THIS IS FOR
# Every number in a written deliverable should be traceable to a file the code produced.
# Checking that by eye does not work past about ten numbers. This checks it mechanically
# and exits non-zero when it fails, so it can sit in CI or a pre-handover script.
#
# IT CHECKS THREE THINGS, AND ALL THREE MATTER
#   Link 1  code output  -> frozen results file   (is the frozen file still current?)
#   Link 2  frozen file  -> prose                 (did every result reach the document?)
#   Link 3  prose        -> frozen file           (does every number in the prose come
#                                                  from somewhere, or was one invented?)
#
# Most harnesses only do Link 2. That is the weakest of the three: if the frozen file is
# stale, Link 2 passes while the document is wrong — which is exactly the failure a frozen
# file is supposed to prevent. Link 3 is the one that catches a number typed from memory.
#
# USAGE
#   python verify_numbers.py                 # check only
#   python verify_numbers.py --regen         # rerun the pipeline first, then check Link 1

import argparse, csv, os, re, subprocess, sys

# ---------------------------------------------------------------- configuration
ROOT   = os.path.dirname(os.path.abspath(__file__))
RESULTS = os.path.join(ROOT, "outputs", "results_final.csv")   # the frozen numbers
DOC     = os.path.join(ROOT, "writeup", "chapter4.md")         # the prose to check

# The exact commands that regenerate RESULTS, in order. Used by --regen and printed in
# the README as the documented run order. Keep these two in sync.
PIPELINE = [
    ["python", "src/preprocessing.py"],
    ["python", "src/train.py"],
    ["python", "src/evaluate.py"],
]

# One number the pipeline must reproduce, as a reproducibility gate. Pick something
# central that would move if anything upstream changed.
GATE = ("accuracy", "0.8734")


# ---------------------------------------------------------------- helpers
def rows(path):
    with open(path, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def fmt(x, dp=2):
    """Format a value the way the document formats it. Adapt to the document's style."""
    v = round(float(x), dp)
    s = f"{v:.{dp}f}"
    return "0." + "0" * dp if s.startswith("-0.") and float(s) == 0 else s


def load_doc():
    text = open(DOC, encoding="utf-8").read()
    # Normalise the characters that differ between a document and a CSV. A minus sign
    # typed by a word processor is not the same codepoint as a hyphen.
    return (text.replace("−", "-")     # U+2212 MINUS SIGN
                .replace("–", "-")     # en dash
                .replace(" ", " "))    # non-breaking space


# ---------------------------------------------------------------- link 1
def check_frozen_is_current(regen):
    """Is results_final.csv still what the code produces?

    Without this, every other check is checking a document against a file that may
    itself be out of date. Run the pipeline into a scratch copy and diff.
    """
    if not regen:
        print("link 1  SKIPPED (pass --regen to rerun the pipeline and diff)\n")
        return True

    before = open(RESULTS, encoding="utf-8").read() if os.path.exists(RESULTS) else None
    for cmd in PIPELINE:
        print("  running:", " ".join(cmd))
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout[-2000:], r.stderr[-2000:])
            sys.exit(f"pipeline step failed: {' '.join(cmd)}")
    after = open(RESULTS, encoding="utf-8").read()

    if before is None:
        print("link 1  results file did not exist; generated fresh\n")
    elif before != after:
        print("link 1  FAIL — the frozen results file was STALE and has been regenerated.")
        print("        Everything written from the old values must now be rechecked.\n")
        return False
    else:
        print("link 1  OK — frozen results match a fresh pipeline run\n")
    return True


# ---------------------------------------------------------------- link 2
class Checker:
    def __init__(self, text):
        self.text, self.checks, self.fails = text, [], []

    def want(self, label, needle, raw=None):
        """Assert `needle` appears in the document.

        `raw` is the unrounded value. Passing it means a near-miss can be reported at
        full precision, which is how rounding-boundary errors get caught: a value of
        -0.174954 renders as -0.17, and a document saying -0.18 is wrong by a rule, not
        by a typo.
        """
        alts = [needle]
        # A document often writes a positive bound as "+1.18" so the sign is unambiguous
        # beside a negative one. Accept both forms rather than forcing one convention.
        if ", " in needle:
            lo, hi = needle.split(", ", 1)
            if not hi.startswith("-"):
                alts.append(f"{lo}, +{hi}")
        if not needle.startswith("-"):
            alts.append("+" + needle)

        ok = any(a in self.text for a in alts)
        self.checks.append(needle)
        if not ok:
            note = ""
            if raw is not None:
                note = f"   (full precision {float(raw):.6f})"
            self.fails.append((label, needle, note))
        return ok


# ---------------------------------------------------------------- link 3
NUMBER = re.compile(r"(?<![\w.])[-+−]?\d+\.\d+(?![\w])")


def check_no_orphans(text, accounted):
    """Every decimal number in the prose should trace to a result file.

    Anything left over is either a number typed from memory, a hand-computed derivation,
    or a legitimate constant. All three deserve a look; the first is a defect.
    """
    found = {m.group().replace("−", "-") for m in NUMBER.finditer(text)}
    orphans = sorted(f for f in found if f.lstrip("+-") not in
                     {a.lstrip("+-") for a in accounted})
    return orphans


# ---------------------------------------------------------------- claims
def build_claims(c):
    """ADAPT THIS BLOCK. One `want` per number that appears in the prose.

    Add to it whenever a new number enters the document. The harness is only as good as
    its coverage, and coverage is the thing that decays silently as a draft grows.
    """
    for r in rows(RESULTS):
        # e.g. columns: model, metric, value, ci_lower, ci_upper, n
        c.want(f"{r['model']} {r['metric']}", fmt(r["value"], 3), raw=r["value"])
        if r.get("ci_lower"):
            c.want(f"{r['model']} {r['metric']} CI",
                   f"{fmt(r['ci_lower'], 3)}, {fmt(r['ci_upper'], 3)}")
        if r.get("n"):
            n = int(r["n"])
            c.want(f"{r['model']} n", f"{n:,}" if n >= 1000 else str(n))


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--regen", action="store_true",
                    help="rerun the pipeline first and diff the frozen results file")
    ap.add_argument("--strict-orphans", action="store_true",
                    help="fail on numbers in the prose that trace to no result file")
    args = ap.parse_args()

    fresh = check_frozen_is_current(args.regen)

    text = load_doc()
    c = Checker(text)
    build_claims(c)

    print(f"link 2  checked {len(c.checks)} values, {len(c.fails)} not found in the prose")
    for label, needle, note in c.fails:
        print(f"        MISSING  {label:<44} looked for '{needle}'{note}")

    orphans = check_no_orphans(text, c.checks)
    print(f"\nlink 3  {len(orphans)} number(s) in the prose trace to no result file")
    for o in orphans[:40]:
        print(f"        ORPHAN   {o}")
    if len(orphans) > 40:
        print(f"        ... and {len(orphans) - 40} more")

    # the reproducibility gate, stated in the README so a reader can check it too
    gate_ok = GATE[1] in text
    print(f"\ngate    {GATE[0]} = {GATE[1]}: {'OK' if gate_ok else 'NOT FOUND IN PROSE'}")

    failed = bool(c.fails) or not fresh or (args.strict_orphans and orphans)
    print("\nRESULT:", "FAIL" if failed else "PASS")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
