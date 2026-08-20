# Anticholinergic burden and cognition (NHANES)

Dissertation and analysis code for BIO-7057X, University of East Anglia.

**Everything is in [`NHANES_dissertation/`](NHANES_dissertation/)** — start with its
[README](NHANES_dissertation/README.md), which explains the analysis, how to run it, and
the reproducibility check.

The same pipeline runs on two independent NHANES cycles: **2013–2014**, which the
dissertation is written from, and **2011–2012**, an independent validation. The cycle is a
parameter, not a copy of the code — everything cycle-specific lives in
[`code/config.R`](NHANES_dissertation/code/config.R).

```bash
cd NHANES_dissertation/code
Rscript run_all.R          # both cycles + the cross-cohort comparison, ~2 minutes
```

| | |
| --- | --- |
| Dissertation | [`writeup/Dissertation_BIO-7057X_DRAFT.docx`](NHANES_dissertation/writeup/) |
| Analysis code | [`code/`](NHANES_dissertation/code/) — R and Python, `run_all.R` is the entry point |
| Data | [`data/`](NHANES_dissertation/data/) — NHANES public-use files for both cycles, included so the pipeline runs without a download |
| Results | [`outputs/2013-2014/`](NHANES_dissertation/outputs/) and [`outputs/2011-2012/`](NHANES_dissertation/outputs/) — tables and figures per cycle |
| Cross-cohort | [`outputs/comparison/`](NHANES_dissertation/outputs/comparison/) — the two cycles side by side |

Author: Jigneshbhai Siddhapura · Supervisor: Dr Saber Sami
