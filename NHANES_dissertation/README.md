# Anticholinergic burden and cognition in older US adults (NHANES)

Analysis code, data and write-up for the BIO-7057X dissertation:
*Is anticholinergic burden associated with cognition independently of polypharmacy?
A survey-weighted cross-sectional analysis in older US adults (NHANES 2013–2014).*

Author: Jigneshbhai Siddhapura · Supervisor: Dr Saber Sami · University of East Anglia

The dissertation is [`writeup/Dissertation_BIO-7057X_DRAFT.docx`](writeup/).

---

## Two cohorts

The same pipeline runs on two independent NHANES cycles. Nothing is duplicated between
them: one set of scripts, and the cycle is a parameter.

| Cycle | Role | File suffix | Command |
| --- | --- | --- | --- |
| **2013–2014** | The dissertation analysis | `_H` | default |
| **2011–2012** | Independent validation for the September presentation | `_G` | `--cycle=2011-2012` |

Everything that differs between cycles lives in [`code/config.R`](code/config.R) and
nowhere else. To add a future cycle, add one row to the `CYCLES` list there.

---

## What the analysis does

Adults aged 60+ (the cognitive module is only given to 60+). Anticholinergic burden is
scored from prescription records and tested against cognition **with medication count in
the same model**, so that burden and polypharmacy can be told apart. Everything is
survey-weighted (PSU, strata, MEC weights). Two scoring scales are compared head to head:

- **Boustani ACB** (0–3 per drug), from `data/scales/aas_combined.csv`
- **IACB** (0–4 per drug), from Fleetwood et al. (2021), SSRN preprint 3777231

Outcomes: Digit Symbol Substitution Test (primary), animal fluency and CERAD delayed
recall (secondary).

---

## Quick start

```bash
# 1. dependencies
Rscript code/00_install_packages.R      # haven, survey, dplyr, tidyr, ggplot2, scales
pip install -r requirements.txt         # only needed for the Python scripts

# 2. the 2013-2014 data ships with the repository; fetch the validation cycle
python code/00_download_data.py 2011-2012

# 3. run everything - both cycles, in the right order, plus the comparison
cd code
Rscript run_all.R
```

`run_all.R` is the recommended entry point. It takes about two minutes for both cycles.
To run one cycle only: `Rscript run_all.R 2013-2014`.

### Running steps individually

The order matters, and running them out of order produces **stale results rather than an
error**, so prefer `run_all.R`. If you do run them by hand:

| Step | Script | Needs | Produces |
| --- | --- | --- | --- |
| **1** | `11_corrected_crosswalk.R` | raw data + `data/scales/` | `crosswalk_corrected.csv`, scale-comparison models, standardised head-to-head, medication bands |
| **2** | `05_main_analysis.R` | the crosswalk | all primary/secondary model CSVs, Table 1, sample flow, IPW, `sessionInfo.txt` |
| **3** | `07_worked_examples.R` | the crosswalk | top anticholinergic drugs, age-equivalence figures |
| **4** | `10_appendix_tables.R` | the crosswalk | full covariate coefficients for Appendix C |
| **5** | `09_figures.R` | the CSVs from 1–2 | the five figures |
| **6** | `13_export_participant_level.R` | the crosswalk + step 2 | participant-level M4 export (SEQN, medicines, band, both burdens, DSST) |
| **7** | `12_cohort_comparison.R` | **both** cycles complete | the cross-cohort tables and Figure 6 |
| **8** | `14_pooled_cycle_interaction.R` | **both** cycles complete | pooled model with a cycle x burden interaction |
| **9** | `15_presentation_figures.R` | steps 7-8 | slide-ready figures in `outputs/comparison/presentation/` |

Add `--cycle=2011-2012` to any of them to run the validation cycle. Steps 1–5 generate
every number in the dissertation.

`audit_2011_2012.R` is a standalone reading copy of the whole 2011-2012 analysis in one
file, written for the supervisor. It is not part of the pipeline and reruns nothing that
matters: its last section re-reads the production output and stops if any focal estimate
has drifted by more than 1e-8.

**Is the difference between the cycles real?** `14_pooled_cycle_interaction.R` answers
that directly, by pooling both cycles and testing a cycle x burden interaction rather than
comparing a significant result in one cycle with a non-significant one in the other. It
halves the survey weights (the NHANES rule for combining two 2-year cycles) and checks that
no design stratum is shared between cycles before pooling.

Not part of the run: `00_download_data.py` (re-fetches raw data), `01_data_exploration.py`
and `02_acb_mapping.py` (exploratory, console output only), and `08_extract_iacb.py`,
which rebuilds `data/scales/iacb_scores.csv` from the IACB preprint. The extracted scores
already ship with the repository, so `08` only needs running if you want to reproduce that
extraction — and if you do, run it **before** step 1. See [`reference/`](reference/) for
where to obtain the preprint.

`code/archive/` holds five superseded scripts. **None of them produces a number that
appears in the dissertation** — see [`code/archive/README.md`](code/archive/README.md).

---

## Layout

```
code/
  config.R              which cycle to run + every path. The only cycle-aware file.
  run_all.R             runs the whole pipeline in the correct order
  00-15_*.R / *.py      the pipeline; numbering skips 03/04/06 (see archive/)
  audit_2011_2012.R     the 2011-2012 analysis in one readable file, self-checking
  archive/              superseded scripts, kept for provenance
data/
  2013-2014/            NHANES .xpt files for the dissertation cycle
  2011-2012/            NHANES .xpt files for the validation cycle
  scales/               the two drug-score reference lists (not cycle-specific)
outputs/
  2013-2014/
    tables/             every result CSV + sessionInfo.txt
    figures/            the five figures used in the dissertation
  2011-2012/            same structure, validation cycle
  comparison/           cross-cohort tables, the pooled interaction test, Figure 6
    presentation/       slide-ready figures for the September presentation
reference/              where to obtain the IACB preprint that 08 reads
writeup/                the dissertation .docx, plus its markdown source and build script
```

To rebuild the .docx from the markdown source: `python writeup/drafts/build_docx.py`
(close Word first, or it writes to a `_UPDATED` copy instead).

---

## Notes on the data

**NHANES files.** Public-use, from the CDC. The 2013–2014 files are included so the
dissertation cycle runs without a download step. If you re-fetch them, note that the
widely-cited URL pattern `wwwn.cdc.gov/Nchs/Nhanes/2013-2014/*.XPT` **no longer works** —
CDC restructured the site and it now returns an HTML error page that will silently save as
a `.xpt`. The working pattern is `wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/*.xpt`.
`00_download_data.py` uses the working pattern and validates that each file really is a
SAS transport file before saving it.

**`aas_combined.csv`.** Reference list of anticholinergic scales, from the supplementary
repository of Mur et al. (2025). The `boustani` column is used here.

**`iacb_scores.csv`.** 205 drugs with IACB scores, extracted from the preprint by
`08_extract_iacb.py`. The published list is a five-column table (Score 0–4) whose columns
run out at different points — on the second page the Score 3 column is empty while Score 4
continues. Reading the table in text order therefore assigns the wrong score to every
Score 4 drug on that page, so the script assigns scores from each entry's **x-coordinate**
on the page instead, and checks the parsed counts against the printed pages.

**Mortality.** `NHANES_2013_2014_MORT_2019_PUBLIC.dat` is retained for completeness but is
not used: the dissertation is entirely cross-sectional.

---

## Software

R 4.6.1 with `survey` 4.5, `haven` 2.5.5, `dplyr` 1.2.1, `tidyr` 1.3.2 — the exact
environment that produced each set of results is recorded in that cycle's
`outputs/<cycle>/tables/sessionInfo.txt`. Python 3.11 for the extraction and
document-build scripts.

Three analysis choices worth knowing when reading the code:

- The survey design is built on the **full** sample and then subset to 60+, rather than
  filtering the data frame first. Filtering first gives incorrect standard errors.
- Confidence intervals use the **design degrees of freedom** (15 in 2013–2014, 17 in
  2011–2012) rather than residual degrees of freedom. With few design df, adding
  categorical covariates drives the residual df toward zero and `confint()` returns
  unusable intervals. The design df is written to `design_df.csv` so the figures use the
  same multiplier as the models rather than a hardcoded 1.96.
- `DIQ010 == 3` ("borderline" diabetes) is coded as **no diagnosed diabetes**, not as
  missing. It is a real answer rather than a non-response, and treating it as missing
  dropped 97 participants (2013-2014) and 62 (2011-2012) out of every comorbidity model.
- The PHQ-9 depression covariate is scored by **deterministic bounding**, not
  `rowSums(na.rm = TRUE)`. The latter scores an unanswered item as "not at all", which
  turns a non-response into a fabricated negative. See the comment in `05_main_analysis.R`.

---

## Reproducibility check

`05_main_analysis.R` should report, for the fully adjusted DSST model (M4) on the
**2013–2014** cycle:

```
acb_burden   -1.3654   95% CI (-1.9250, -0.8058)   p < 0.001   n = 1468
```

That is the estimate the dissertation reports as −1.37 (−1.92, −0.81). If it matches, the
pipeline is behaving as it did when the dissertation was written.

Two guards run automatically and stop the pipeline rather than producing a quietly wrong
figure: `10_appendix_tables.R` refits M4 independently and fails if its focal estimate
disagrees with `05_main_analysis.R`, and `09_figures.R` fails if any model row would be
dropped from Figure 3 for want of a label. Both were added after real bugs of exactly
those two shapes.
