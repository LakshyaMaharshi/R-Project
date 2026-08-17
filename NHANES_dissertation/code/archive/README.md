# Archived scripts — superseded, not used for any dissertation result

Nothing in this folder produces a number that appears in the dissertation. They are kept
only as a record of earlier work. **Do not run these expecting the reported results** —
run the pipeline in `../` instead (see the project README).

| Script | What it was | Why it is archived |
| --- | --- | --- |
| `04_regression_models.py` | First pass at the cognition models, plus Cox models for mortality | **Unweighted.** Ignores the NHANES survey design, so both the estimates and the standard errors are wrong for a complex sample. Superseded by `05_main_analysis.R`. |
| `04_regression_models.R` | R version of the same first pass | Same problem — the header says so: "these are UNWEIGHTED — don't quote these numbers". |
| `05_main_analysis.py` | Python port of the main survey-weighted analysis, using `samplics` | Written when R was not installed on the machine. R is now installed, and **every number in the dissertation comes from `05_main_analysis.R`**. Kept because it independently reproduces the same design-based approach. |
| `03_merge_mortality.py` | Parses the NHANES linked-mortality `.dat` and merges it on | The mortality strand was dropped. The dissertation is entirely cross-sectional and uses no mortality outcome. `data/NHANES_2013_2014_MORT_2019_PUBLIC.dat` is retained only for completeness. |
| `06_scale_sensitivity.R` | First version of the Boustani-vs-IACB comparison | Scored any drug absent from a scale's list as zero, conflating "scored 0 by the list" with "not on the list". With unequal list coverage this biased the between-scale comparison, as the supervisor identified. Superseded by `11_corrected_crosswalk.R`. |

## Why the main folder skips 03, 04 and 06

The remaining scripts keep their original numbers (01, 02, 05–09) rather than being
renumbered, so that references to them elsewhere — including `08_extract_iacb.py`, which is
named in the dissertation's methods — stay valid. The gaps are these five files.
