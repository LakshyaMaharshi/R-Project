# Run the whole pipeline, for one cycle or for both, in the right order.
#
#   Rscript run_all.R                 # both cycles, then the cross-cohort comparison
#   Rscript run_all.R 2013-2014       # just the dissertation cycle
#   Rscript run_all.R 2011-2012       # just the validation cycle
#
# The order matters and is not obvious, which is exactly why this file exists: 11 writes
# crosswalk_corrected.csv, and 05, 07 and 10 all read it. 09 draws the figures from the
# CSVs the earlier steps wrote, and 12 compares the two finished cycles. Getting 11 and 05
# the wrong way round produces stale results rather than an error, so do not run them by
# hand in a different order.
#
# Each step runs in its own R process. That is deliberate - sourcing them into one session
# would let objects leak between scripts, and a stale variable surviving into the next
# script is the sort of thing that produces confident, wrong numbers.

STEPS <- c("11_corrected_crosswalk.R",       # 1. the drug-to-scale crosswalk + scale comparison
           "05_main_analysis.R",             # 2. primary/secondary models, Table 1, IPW
           "07_worked_examples.R",           # 3. drug-mix facts quoted in the text
           "10_appendix_tables.R",           # 4. full covariate tables for the appendix
           "09_figures.R",                   # 5. the five figures
           "13_export_participant_level.R")  # 6. participant-level M4 export (Dr Sami, 21 Aug)

# These need BOTH cycles finished, so they run once at the end rather than per cycle.
POOLED <- c("12_cohort_comparison.R",        # the two cycles side by side
            "14_pooled_cycle_interaction.R", # cycle x burden interaction - the key test
            "15_presentation_figures.R")     # slide-ready plots

.f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
here <- if (length(.f)) dirname(sub("^--file=", "", .f[1])) else "."
source(file.path(here, "config.R"))       # for the CYCLES registry

argv   <- commandArgs(trailingOnly = TRUE)
argv   <- argv[!grepl("^--", argv)]
cycles <- if (length(argv)) argv else names(CYCLES)

bad <- setdiff(cycles, names(CYCLES))
if (length(bad))
  stop("unknown cycle(s): ", paste(bad, collapse = ", "),
       "\n  known: ", paste(names(CYCLES), collapse = ", "))

rscript <- file.path(R.home("bin"), "Rscript")

run <- function(script, extra = character()) {
  cat("\n", strrep("=", 74), "\n>>> ", script, " ", paste(extra, collapse = " "),
      "\n", strrep("=", 74), "\n", sep = "")
  st <- system2(rscript, c(shQuote(file.path(here, script)), extra))
  # A failed step must stop the run. Carrying on would rebuild figures and comparison
  # tables from whatever stale CSVs happen to be lying around, which looks like success.
  if (st != 0) stop(script, " failed (exit ", st, ") - stopping.")
}

for (cyc in cycles) {
  cat("\n\n########## CYCLE ", cyc, " ##########\n", sep = "")
  for (s in STEPS) run(s, paste0("--cycle=", cyc))
}

# The pooled steps only mean anything with both cycles present.
if (length(cycles) > 1) {
  for (s in POOLED) run(s)
} else {
  cat("\n[skip] the pooled comparison, interaction test and presentation figures
      need both cycles. Run `Rscript run_all.R` with no argument to get them.\n")
}

cat("\nAll done. Results are in outputs/<cycle>/",
    if (length(cycles) > 1) " and outputs/comparison/" else "", "\n", sep = "")
