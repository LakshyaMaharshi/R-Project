# Writing a research document on top of an analysis — the method

Drop this folder into a project and tell the agent:

> Read `METHOD.md` and follow it. Start at Phase 0.

Nothing here is specific to a field or a language. It assumes only: there is code that
produces results, and a document that reports them.

**The one idea everything serves:** prose is written last, and every number in it is
generated, never typed from memory.

---

## Phase 0 — before writing a word

1. **Read the brief and extract the hard constraints.** Word limit *and what it excludes*
   (tables? captions? references? appendix?), required sections, referencing style,
   deadline, whether figures are expected. Write them at the top of `FACTS.md`. These
   determine the shape of everything else.

2. **Read the analysis code and its real outputs** — not the README's description of them.
   Establish which scripts are canonical and which are superseded. Move superseded code to
   `archive/` with a note per file saying it produces no number in the document.

3. **Run the whole pipeline yourself, end to end, before trusting any result file.**
   Result files can silently predate the last code change. Regenerate them, then diff
   against whatever the draft was written from. Do this *before* building any verification,
   or you will verify against stale numbers and call it a pass.

4. **Build `FACTS.md` from the freshly regenerated output.** Every headline estimate,
   interval, sample size and descriptive figure, under a heading saying *reuse verbatim, do
   not recompute*. The prose draws only from here.

5. **Define a reproducibility gate.** One concrete checkable result, stated in the README:
   "step 2 must report accuracy = 0.8734". If that matches, the pipeline behaves as it did
   when the text was written.

---

## Phase 1 — structure before prose

6. **Map required sections to a skeleton with a word budget each.** Budget under the limit.
   Sections that carry a new exhibit always run over, and trimming late costs more.

7. **Decide which table or figure carries each results section, before writing it.** Prose
   then interprets the exhibit instead of restating it. A section with no exhibit either
   needs one or belongs somewhere else.

8. **Write in derivation order, not document order.** Methods and Results first — they are
   pinned by what the data shows and cannot drift. Then Discussion, which depends on
   Results. Then Introduction, which frames what you now know you found. **Abstract last,
   always.**

---

## Phase 2 — draft, one section at a time

9. **Markdown is the source of truth; a script builds the final format.** Never hand-edit
   the generated file — it gets overwritten. If the generated file is locked by another
   program, write to a fallback name and **warn loudly**, or you will keep editing a stale
   copy.

10. **Every number comes from a result file.** If it is not in `FACTS.md` or an output, it
    does not go in the text.

11. **Anything unverified gets a visible `[TODO: what is needed]` marker.** Never fabricate
    a reference, a p-value or a sample size. A marker is a small fixable gap; a fabricated
    value is a defect that survives review.

12. **Verify every reference against the publisher record as you write** — authors, year,
    journal, volume, pages. Not in a batch at the end.

13. **Have the build script print a length check every run,** with the brief's exclusions
    computed separately, and warn when out of range.

---

## Phase 3 — verify mechanically, never by eye

14. **Build a verification harness as a permanent script** (template: `verify_numbers.py`).
    It checks a chain of three links:

    | Link | Question | Catches |
    | --- | --- | --- |
    | code → results file | is the results file still current? | a file that predates a code change |
    | results file → prose | did every result reach the document? | transcription slips, rounding errors |
    | prose → results file | does every number in the prose come from somewhere? | a number typed from memory |

    Most harnesses do only the middle link, which is the weakest: if the results file is
    stale it passes while the document is wrong. **Build the third link first** — regex
    every number in the prose, subtract everything a result file can justify, look at what
    is left. That tells you which numbers you cannot currently verify *at all*, which is a
    more useful map than a passing forward check.

    Two traps it must handle: **sign and format** must match the document's convention
    (`+1.18` vs `1.18`, `−` vs `-`), and **rounding boundaries** need full precision printed
    before you judge (a value of `-0.174954` renders `-0.17`, so a document saying `-0.18`
    is wrong by a rule, not a typo).

    Run it after every change. Grow it whenever a new number enters the document.

15. **Run a prose quality scan** — em-dashes, AI vocabulary, copula avoidance, filler,
    sentence-length variance. Aim for zero on the patterns and a length SD above ~10;
    uniform rhythm is itself a tell.

16. **Clean-clone test.** Copy the shareable folder elsewhere, delete all generated output,
    run the documented steps, confirm the reproducibility gate still matches.

---

## Phase 4 — the rule that catches the expensive bugs

17. **After any upstream change, rerun everything downstream AND re-audit every selector
    whose meaning depended on the old behaviour.**

    This is the one that costs most when skipped. Two real cases, both of which produced a
    confidently wrong document while raising no error:

    - A scoring rule changed so a value was never missing any more. A figure script selected
      its subset with `!is.na(x)`. That filter had been correct; afterwards it matched
      everything. The figure reported 78% where the truth was 22%.
    - Model terms were renamed. A figure's label map still matched the old name, so those
      rows fell to a fallback label, failed a later `%in%` filter, and were **silently
      dropped**. The figure went out missing the estimates it existed to show.

    Both are the same species: **a filter that drops rows without complaining.** So:

    ```
    dropped <- setdiff(unique(rows$label), expected_labels)
    if (length(dropped) > 0) stop("unlabelled rows would be dropped: ", dropped)
    stopifnot(sum(grepl("<the key row type>", rows$label)) >= <expected minimum>)
    ```

18. **Guards read from the source of truth, never a pasted constant.** A hardcoded expected
    value goes stale after a legitimate change and fails for the wrong reason, which trains
    you to ignore it. Read the reference value from the canonical output file.

19. **Figures use the same conventions as the models.** A figure once used a normal
    approximation for its intervals while every model used the design degrees of freedom,
    so the figure disagreed with the analysis beside it. Have the analysis script *write the
    convention out to a file* and the figure script read it.

20. **Figures are generated from result files, never re-typed numbers,** and each figure
    script prints a self-check line that can be matched against the prose.

21. **Anything quoted in the text must exist in a file, not only in console output.**
    Console-only statistics cannot be verified and go stale invisibly. If it is worth
    quoting, write it to a CSV.

---

## Phase 5 — review cycles

22. **Send revised tables and code *before* rewriting large parts of the text.** Rewriting
    prose around numbers that then change is wasted work.

23. **Log every request with a done state.** Framing instructions ("do not claim X is
    superior") are standing constraints that must survive a context reset.

24. **When the criticism is correct, concede first, then show you have already quantified
    the damage.** "You were right. N cases were affected, here is the fix, here is what
    changed." That reads as competence; defensiveness does not.

25. **Report faithfully.** If a fix moves the headline numbers, give the new ones. If it
    does not change the conclusions, say that too, and show why.

---

## Phase 6 — trim last

26. **Trim only after the numbers are verified, then re-verify.** Cut redundancy between
    Discussion and Conclusion first, then over-explained methods, then unused background.
    Never cut a caveat, a limitation or a number to save words. Re-run the harness after —
    a trim can delete a value you still cite elsewhere.

27. **Update the declared word count.** It goes stale silently.

---

## State files

| File | Job | Lifetime |
| --- | --- | --- |
| `FACTS.md` | verified facts and figures, *reuse verbatim* | whole project |
| `progress.txt` | resume point, newest block on top | whole project |
| `verify_numbers.py` | the harness | whole project |
| todo list | current session only | one session |

`progress.txt` structure:

```
=== CONTEXT ===   who is involved, deadlines, what this is for
=== STATUS ===    what is done, where the artifacts are
=== DECISIONS === judgement calls and WHY
=== FEEDBACK ===  each request from a reviewer, done/not-done
=== NEXT ===      numbered, specific, immediately actionable
=== CAUTIONS ===  standing rules that must survive a context reset
```

Keep internal notes and draft emails **outside** the folder you share. A draft email about
a reviewer should never sit in the directory you send that reviewer.

---

## Handover checklist

- [ ] Pipeline reruns clean, end to end, in documented order
- [ ] Harness: N values checked, 0 mismatches, all three links
- [ ] Clean-clone test passes; reproducibility gate matches
- [ ] Zero `[TODO]` markers
- [ ] Every reference verified against a publisher record
- [ ] Length inside the limit; declared figure updated
- [ ] Figures regenerated after the last code change; self-checks match the prose
- [ ] Every row-dropping filter has a guard
- [ ] Nothing quoted exists only in console output
- [ ] Internal notes outside the shared folder
- [ ] Placeholders filled (ID, date, version)

---

## Session-start prompt

```
Read METHOD.md, then progress.txt for the resume point and FACTS.md for verified facts.

Work one section at a time: plan, draft, verify every number against the source files with
verify_numbers.py, then log to progress.txt before moving on.

Never invent a number, a citation or a sample size — use [TODO: ...] markers instead.
After any change to the analysis code, rerun everything downstream and re-run the harness
before touching the text.

Tell me plainly when a result is negative or an earlier claim has to weaken.

Start with the next item under "NEXT".
```

---

## Failure catalogue

| Failure | How it hides | Countermeasure |
| --- | --- | --- |
| A filter's meaning changes when an upstream rule changes | Nothing errors; it matches more or fewer rows and the output is confidently wrong | Re-audit every downstream selector after a semantics change |
| A label map still matches a pre-rename term | Silent; the exhibit simply lacks the rows that mattered | Guards that **error** on unmatched input, plus a printed row count |
| A guard hardcodes its expected value | Goes stale, fails for the wrong reason, trains you to ignore it | Read the reference from the canonical output |
| A figure uses a different statistical convention from the models | Plausible-looking intervals that disagree with the analysis | Analysis writes the convention to a file; figure reads it |
| A number exists only in console output | Unverifiable; goes stale invisibly | Write it to a file if it is worth quoting |
| Stale generated files after a code change | Old and new values mix in one document | Regenerate everything downstream; delete before rebuild |
| Missing treated as zero | A confident, wrong conclusion | Hold unknowns as null; report missingness explicitly |
| A download returns an error page under the expected filename | Parses as garbage much later | Validate content, not just exit status |
| Text extracted from PDFs contains ligatures or smart quotes | Exact-match lookups silently fail for a subset | Normalise Unicode before matching |
| Ragged multi-column tables read in reading order | Values attach to the wrong column, plausibly | Parse by coordinate; verify against a rendered page |
| A file open in another program blocks a write | Silent fallback; you keep editing a stale copy | Fallback filename **and** a loud warning |
| Dependency file inherited from another project | Anyone following the README installs the wrong things | Generate deps from actual imports |
| Waiting on an unavailable person | Days lost, deadline unchanged | Decide, document, disclose |
