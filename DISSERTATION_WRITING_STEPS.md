# How to write the dissertation — the actual sequence

Hand this to the agent. It is the order of operations, not a style guide. The companion
`CLAUDE_DISSERTATION_PLAYBOOK.md` covers the state files and guardrails; this covers what
to do first, second, third, and what to check before moving on.

The whole method rests on one idea: **prose is the last thing you write, and every number
in it is generated, never typed from memory.** Everything below serves that.

---

## Phase 0 — Before writing a single word

**1. Read the assessment brief and extract the hard constraints into a checklist.**
Word limit *and what it excludes* (tables? captions? references? appendix?), required
section headings, referencing style, deadline, whether figures are expected, what may go in
an appendix. Put this at the top of `_working/FACTS.md`. You will be held to it, and it
determines the shape of everything else.

**2. Read the analysis code and its real outputs — not the README's summary of them.**
Establish which scripts are canonical and which are superseded. This distinction saves
days. Anything superseded moves to `archive/` with a per-file note saying it produces no
number in the document.

**3. Run the whole pipeline yourself, end to end, before trusting any result file.**
The CSVs sitting in the output folder may predate the last code change. Regenerate them.
This has caught stale numbers more than once — outputs that looked fine and were produced
by a script that had since been corrected.

**4. Build `FACTS.md` from the freshly regenerated output.**
Every headline estimate, CI, p-value, sample size and descriptive figure, under a heading
that says *reuse verbatim, do not recompute*. This is what the prose draws from.

**5. Define the reproducibility gate.** One concrete checkable result, in the README:
"`05_main_analysis.R` must report M4 burden = −1.3654". If that matches, the pipeline is
behaving as it did when the text was written.

---

## Phase 1 — Structure before prose

**6. Map the brief's required sections to a skeleton with a word budget per section.**
Budget deliberately under the limit. A results section that has to carry a new table always
runs over, and trimming late costs more than planning early.

**7. For each results section, decide which table or figure carries it — before writing.**
Prose then describes and interprets the exhibit rather than restating it. If a section has
no exhibit, ask whether it needs one or whether it belongs somewhere else.

**8. Write in derivation order, not document order.**
Methods and Results first: they are constrained by what the data actually shows, so they
cannot drift. Then Discussion, which depends on Results. Then Introduction, which frames
what you now know you found. **Abstract last, always** — it summarises a finished document,
and writing it early guarantees rework.

---

## Phase 2 — Draft, one section at a time

**9. Markdown is the source of truth. A build script generates the .docx.**
Never hand-edit the generated file; it gets overwritten. The build script should render
markdown pipe-tables as real Word tables and `![alt](path)` as embedded images.

**10. Every number in prose is copied from a result file, not from memory or an earlier
draft.** If a value is not in `FACTS.md` or a CSV, it does not go in the text.

**11. Anything unverified gets a visible `[CITE: what is needed]` or `[TODO: ...]` marker.**
Never fabricate a reference, a p-value or a sample size. A marker is a small fixable gap; a
fabricated value is a defect that survives review.

**12. Every reference is verified against PubMed or the publisher record before use** —
authors, year, journal, volume, pages. Do this as you write, not in a batch at the end.

**13. Have the build script print a word-count breakdown on every run**, with the
exclusions the brief allows computed separately, and a loud warning when out of range.

---

## Phase 3 — Verify mechanically, never by eye

**14. Build a verification harness as a permanent script, not a one-off snippet.**
This is the highest-value artifact in the project.

**Build it *after* the clean rerun in step 3, never before.** A harness built against
outputs that predate the last code change will pass, and passing certifies staleness. Rerun
the pipeline, diff the regenerated results against whatever the prose was written from, and
only then start checking.

It has to verify a chain of three links, not one:

| Link | Question | What it catches |
| --- | --- | --- |
| code output → frozen results file | is the frozen file still what the code produces? | a results file that predates a code change |
| frozen file → prose | did every result reach the document intact? | transcription slips, rounding boundaries, stale values |
| prose → frozen file | does every number in the prose come from somewhere? | a number typed from memory |

Most harnesses only do the middle one, which is the weakest of the three: if the frozen file
is stale, that check passes while the document is wrong — precisely the failure a frozen
file exists to prevent. The third link is the only one that catches an invented number, and
it is cheap: regex every decimal in the prose, subtract everything accounted for, look at
what is left. Legitimate leftovers (a hand-derived ratio, a constant from the literature)
are worth being able to name.

The middle link reads every result CSV, formats each value the way the document formats it,
and greps the markdown for it:

```python
for r in rows("models_dsst_primary.csv"):
    want(f"{r['model']} / {r['term']} est", num(r["estimate"]))
    want(f"{r['model']} / {r['term']} CI", f"{num(r['ci_lower'])}, {num(r['ci_upper'])}")
```

Run it after **every** change to text or code. Grow it whenever a new number enters the
document — sample sizes, design degrees of freedom, AIC values, anything a reader could
check. It ends in a count: `checked 182 values, 0 not found in the text`.

Two things it must handle: the document's sign convention (`+1.18` vs `1.18`, `−` vs `-`)
and rounding boundaries — print full precision before deciding `−0.1750` renders as `−0.17`.

**15. Run the prose quality scan** — em-dashes, AI vocabulary, copula avoidance, filler,
sentence-length variance. Aim for zero on the patterns and an SD above ~10.

**16. Run the plagiarism method on your own distinctive phrases**, and be explicit that no
local tool substitutes for the institution's own check.

**17. Clean-clone test.** Copy the shareable folder elsewhere, delete `outputs/` entirely,
run the documented steps, confirm the reproducibility gate still matches.

---

## Phase 4 — The rule that catches the expensive bugs

**18. After any upstream change, rerun everything downstream AND re-audit every selector
whose meaning depended on the old behaviour.**

This is the one that costs most when skipped. Two real examples from this project, both of
which produced a wrong document while raising no error at all:

- A scoring rule changed so every drug carried a numeric score instead of sometimes being
  missing. A figure script selected "drugs on both lists" with `!is.na(score)`. That filter
  had been correct; after the change it matched everything. The figure reported 78%
  agreement instead of 22%.
- Model terms were renamed from `acb_zerofill` to `acb_burden`. A figure's label map still
  matched the old name, so every burden row fell to a fallback label, failed the row filter,
  and was **silently dropped**. The published figure showed no burden estimates at all —
  the entire point of that figure — and nothing errored.

Both are the same species: **a filter that drops rows without complaining.** Countermeasure:

```r
dropped <- setdiff(unique(fp$row_lab), ord)
if (length(dropped) > 0) stop("rows with no label would be dropped: ",
                              paste(dropped, collapse = ", "))
stopifnot(sum(grepl("- Burden$", as.character(fp$row_lab))) >= 8)
```

Every filter or label map that can drop rows gets a guard that errors, plus a printed count
on each run that can be matched against the prose.

**19. Guards read from the source of truth, never a pasted constant.**
A hardcoded expected value went stale twice and failed for the wrong reason. Replace it:

```r
ref <- read.csv("models_dsst_primary.csv") %>%
  filter(model == "M4: fully adjusted", term == "acb_burden") %>% pull(estimate)
if (abs(chk$estimate - ref) > 0.001) stop("disagrees with 05_main_analysis.R")
```

**20. Figures must use the same statistical conventions as the models.**
A dose-response figure used a 1.96 normal multiplier while every model used the design
degrees of freedom, so the figure's intervals were narrower than the analysis beside it.
Have the analysis script *write out* the convention (`design_df.csv`) and the figure script
read it, so neither hardcodes it.

**21. Figures are generated from result files, never from re-typed numbers**, and every
figure script prints a self-check line (`20/91 agree exactly (22.0%)`) that can be matched
against the text.

---

## Phase 5 — Supervisor review cycles

**22. Send the revised tables and code *before* rewriting large parts of the text.**
Rewriting prose around numbers that then change is wasted work, and supervisors ask for
this explicitly. Wait for sign-off on the numbers, then rewrite.

**23. Log every request in `progress.txt` under `=== FEEDBACK ===` with a done state.**
Framing instructions ("do not claim either scale is superior") are standing constraints —
they must survive a context reset and apply to every later draft.

**24. When the criticism is correct, open by conceding it, then show you have already
quantified the damage.** "You were right, it was wrong. 527 people were affected, here is
the fix, here is what changed." That reads as competence. Defensiveness does not.

**25. Report faithfully.** If a fix changes the headline numbers, give the new ones. If it
does not change the conclusions, say that too, and show why.

---

## Phase 6 — The trim

**26. Trim only after the numbers are verified, then re-verify.**
Cut in this order: redundancy between Discussion and Conclusion first, then over-explained
methods, then background the argument does not use. Never cut a caveat, a limitation or a
number to save words. Re-run the verification harness afterwards — a trim can delete a value
you still cite elsewhere.

**27. Update the declared word count on the title page.** It goes stale silently.

---

## Handover checklist

- [ ] Pipeline reruns clean, end to end, in the documented order
- [ ] Verification harness: N values checked, 0 mismatches
- [ ] Clean-clone test passes; reproducibility gate matches
- [ ] Zero `[CITE]` / `[TODO]` markers
- [ ] Every reference verified against a publisher record
- [ ] Word count inside the limit, declared figure updated
- [ ] Figures regenerated after the last code change; self-checks match the prose
- [ ] Every filter that can drop rows has a guard
- [ ] Internal notes and draft emails are outside the shared folder
- [ ] Placeholders filled (registration number, date, version)

---

## Session-start prompt for the agent

```
Read DISSERTATION_WRITING_STEPS.md and CLAUDE_DISSERTATION_PLAYBOOK.md, then
_working/progress.txt for the resume point and _working/FACTS.md for verified facts.

Work one section at a time: plan, draft, verify every number against the source CSVs with
the verification script, then log to progress.txt before moving on.

Never invent a number, a citation or a sample size — use [TODO: ...] markers instead.
After any change to the analysis code, rerun everything downstream and re-run the
verification script before touching the text.

Tell me plainly when a result is negative or an earlier claim has to weaken.

Start with the next item under "NEXT (resume here)".
```

---

*Distilled from an MSc dissertation built on a survey-weighted NHANES analysis: several
supervisor review rounds, a post-submission correction, and two silent bugs that produced a
confidently wrong document without raising a single error. The verification harness and the
guards in Phase 4 are the parts that actually caught things.*
