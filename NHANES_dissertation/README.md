# Anticholinergic burden and cognition in older US adults (NHANES 2013–2014)

Analysis code and data for the BIO-7057X dissertation:
*Does anticholinergic burden predict cognition independently of polypharmacy?
A survey-weighted cross-sectional analysis in older US adults (NHANES 2013–2014).*

Author: Jigneshbhai Siddhapura · Supervisor: Dr Saber Sami · University of East Anglia

The dissertation is `writeup/Dissertation_BIO-7057X_DRAFT.docx`.

---

## What the analysis does

Adults aged 60+ in NHANES 2013–2014 (n = 1,785 given the cognitive module; **1,592 with a
valid DSST**, the primary analysis sample). Anticholinergic burden is scored from
prescription records and tested against cognition **with medication count in the same
model**, so that burden and polypharmacy can be told apart. Everything is survey-weighted
(PSU, strata, MEC weights). Two scoring scales are compared head to head:

- **Boustani ACB** (0–3 per drug), from `data/aas_combined.csv`
- **IACB** (0–4 per drug), from Fleetwood et al. (2021), SSRN preprint 3777231

Outcomes: Digit Symbol Substitution Test (primary), animal fluency (secondary).

---

## Quick start

```bash
# 1. dependencies
Rscript code/00_install_packages.R      # haven, survey, dplyr, tidyr, ggplot2, scales
pip install -r requirements.txt         # only needed for the Python scripts

# 2. the analysis (run from the code/ directory)
cd code
Rscript 11_corrected_crosswalk.R        # builds the drug-score crosswalk + scale comparison
Rscript 05_main_analysis.R              # primary + secondary models, Table 1, missingness, IPW
Rscript 07_worked_examples.R            # drug-mix figures quoted in the text
Rscript 10_appendix_tables.R            # full covariate coefficients for the appendix
Rscript 09_figures.R                    # the five figures
```

Note the order: `11` runs FIRST, because it writes `outputs/v2/crosswalk_corrected.csv`,
the canonical drug-to-score mapping that every other script reads. The crosswalk splits
combination products, applies a small documented synonym map, and distinguishes a
confirmed score of zero from a drug that is simply not on a scale's list.

Everything writes to `outputs/`. The data are already in `data/`, so no download step is
needed. Total runtime is roughly a minute.

### Run order and dependencies

| Step | Script | Needs | Produces |
| --- | --- | --- | --- |
| — | `00_install_packages.R` | — | R packages |
| — | `00_download_data.py` | internet | re-fetches the NHANES `.xpt` files (optional; already supplied) |
| opt | `01_data_exploration.py` | raw data | console summary only — exploratory |
| opt | `02_acb_mapping.py` | raw data | early ACB mapping — exploratory |
| — | `08_extract_iacb.py` | `reference/ssrn-3777231 (1).pdf` | `data/iacb_scores.csv` (already supplied) |
| **1** | **`11_corrected_crosswalk.R`** | raw data + `data/iacb_scores.csv` | `crosswalk_corrected.csv`, scale-comparison models, match rates, unmatched-drug list |
| **2** | **`05_main_analysis.R`** | crosswalk + raw data | all primary/secondary model CSVs, Table 1, sample flow, `sessionInfo.txt` |
| **3** | `07_worked_examples.R` | crosswalk + raw data | top anticholinergic drugs, age-equivalence figures |
| **4** | `10_appendix_tables.R` | crosswalk + raw data | full covariate coefficients for Appendix C |
| **5** | `09_figures.R` | the CSVs from steps 1–2 | the five PNG figures |

Steps 1–5 generate every number in the dissertation. `01`, `02` and `08` are optional:
`01`/`02` are exploratory, and `08` only needs re-running if you want to regenerate
`iacb_scores.csv` from the PDF rather than use the supplied copy. **If you do re-run `08`,
run it before `11`.**

`code/archive/` holds five superseded scripts (unweighted models, a Python port, a
mortality merge, and the original scale comparison whose absent-drug coding was corrected
by `11`). **None of them produces a dissertation number** — see `code/archive/README.md`.

---

## Layout

```
code/            analysis scripts (numbering skips 03/04 — those are in archive/)
data/            NHANES .xpt files, the two scale reference lists
outputs/
  figures/       the five figures used in the dissertation
  v2/            all result CSVs + sessionInfo.txt
reference/       assessment brief; the IACB preprint that 08 reads
writeup/         the dissertation .docx, plus the markdown source and its build script
```

To rebuild the .docx from the markdown source: `python writeup/drafts/build_docx.py`
(close Word first, or it writes to a `_UPDATED` copy instead).

---

## Notes on the data

**NHANES files.** Public-use, from the CDC. The `.xpt` files are included so the code runs
without a download step. If you re-fetch them, note that the widely-cited URL pattern
`wwwn.cdc.gov/Nchs/Nhanes/2013-2014/*.XPT` **no longer works** — CDC restructured the site
and it now returns an HTML error page that will silently save as a `.xpt`. The working
pattern is `wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/*.xpt`.
`00_download_data.py` uses the working pattern and validates each file.

**`aas_combined.csv`.** Reference list of anticholinergic scales, from the supplementary
repository of Mur et al. (2025). The `boustani` column is used here.

**`iacb_scores.csv`.** 205 drugs with IACB scores, extracted from the supplied preprint by
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
environment that produced the results is recorded in `outputs/v2/sessionInfo.txt`.
Python 3.11 for the extraction and document-build scripts.

Two analysis choices worth knowing when reading the code:

- The survey design is built on the **full** sample and then subset to 60+, rather than
  filtering the data frame first. Filtering first gives incorrect standard errors.
- Confidence intervals use the **design degrees of freedom** (≈15) rather than residual
  degrees of freedom. With few design df, adding categorical covariates drives the residual
  df toward zero and `confint()` returns unusable intervals.

---

## Reproducibility check

`05_main_analysis.R` should report, for the fully adjusted DSST model (M4):

```
acb_burden   -1.4159   95% CI (-2.0279, -0.8038)   p < 0.001   n = 1468
```

If that matches, the pipeline is behaving as it did when the dissertation was written.
