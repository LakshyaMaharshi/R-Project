# Participant-level export for the M4 analytic sample.
#
# Dr Sami asked for this on 21 Aug, to check the result is not an artefact of the scoring
# or the merge: SEQN, medication count, medication band, Boustani burden, IACB burden, DSST.
#
#   Rscript 13_export_participant_level.R --cycle=2011-2012
#   Rscript 13_export_participant_level.R                     (2013-2014)
#
# The exposures are rebuilt here from crosswalk_corrected.csv using exactly the same
# person-level rollup as 11_corrected_crosswalk.R, and the M4 sample is defined by exactly
# the same complete-case rule. The script then CHECKS its own row count against the n_used
# that 05_main_analysis.R recorded for M4, and stops if they differ - so this file cannot
# quietly describe a different set of people from the ones the estimates came from.
#
# Writes outputs/<cycle>/tables/participant_level_m4_<cycle>.csv

library(haven); library(dplyr)

.f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
source(file.path(if (length(.f)) dirname(sub("^--file=", "", .f[1])) else ".", "config.R"))

cw_path <- file.path(out_dir, "crosswalk_corrected.csv")
if (!file.exists(cw_path))
  stop("crosswalk_corrected.csv not found for ", CYCLE,
       " - run 11_corrected_crosswalk.R --cycle=", CYCLE, " first")

demo <- read_xpt(xpt("DEMO"))
rxq  <- read_xpt(xpt("RXQ_RX"))
cfq  <- read_xpt(xpt("CFQ"))
cw   <- read.csv(cw_path, stringsAsFactors = FALSE)

norm <- function(x) tolower(trimws(as.character(x)))

## person-level exposures - identical rollup to section 4 of 11_corrected_crosswalk.R ----
expo <- rxq %>%
  filter(!is.na(RXDDRUG), RXDDRUG != "") %>%
  mutate(drug = norm(RXDDRUG)) %>%
  left_join(cw, by = "drug") %>%
  group_by(SEQN) %>%
  summarise(n_drugs     = n(),
            acb_burden  = sum(boustani_score),
            iacb_burden = sum(iacb_score),
            .groups = "drop")

## same covariate construction and same complete-case rule as 05 / 11 -------------------
analysis <- demo %>%
  left_join(cfq %>% select(SEQN, CFDDS), by = "SEQN") %>%
  left_join(expo, by = "SEQN") %>%
  mutate(
    # no prescription record = 0 medicines and 0 burden, not missing
    across(c(n_drugs, acb_burden, iacb_burden), ~ ifelse(is.na(.x), 0, .x)),
    age = as.numeric(RIDAGEYR),
    sex = factor(RIAGENDR, levels = c(1, 2), labels = c("Male", "Female")),
    educ_code = ifelse(DMDEDUC2 %in% c(7, 9), NA, DMDEDUC2),
    education = factor(educ_code, levels = 1:5,
      labels = c("<9th grade", "9-11th grade", "HS grad/GED",
                 "Some college/AA", "College grad+")),
    race = factor(RIDRETH3, levels = c(3, 1, 2, 4, 6, 7),
      labels = c("NH White", "Mexican American", "Other Hispanic",
                 "NH Black", "NH Asian", "Other/Multi")),
    income_pir = as.numeric(INDFMPIR),
    med_band = cut(n_drugs, breaks = c(-Inf, 4, 9, Inf),
                   labels = c("0-4 medicines", "5-9 medicines", ">=10 medicines")),
    age60 = age >= 60)

MODEL_VARS <- c("CFDDS", "n_drugs", "age", "sex", "race", "education", "income_pir")
in_m4 <- complete.cases(analysis[, MODEL_VARS]) &
         analysis$age60 & !is.na(analysis$WTMEC2YR) & analysis$WTMEC2YR > 0

out <- analysis %>%
  filter(in_m4) %>%
  transmute(SEQN,
            medication_count = n_drugs,
            medication_band  = as.character(med_band),
            boustani_burden  = acb_burden,
            iacb_burden      = iacb_burden,
            DSST             = CFDDS) %>%
  arrange(SEQN)

## guard: this must be the same sample the M4 estimate was computed on -------------------
ref_path <- file.path(out_dir, "models_dsst_primary.csv")
if (!file.exists(ref_path))
  stop("models_dsst_primary.csv not found - run 05_main_analysis.R --cycle=", CYCLE, " first")
ref_n <- read.csv(ref_path, stringsAsFactors = FALSE) %>%
  filter(model == "M4: fully adjusted", term == "acb_burden") %>% pull(n_used)
cat(sprintf("\nexported rows: %d | M4 n_used in models_dsst_primary.csv: %d\n", nrow(out), ref_n))
if (nrow(out) != ref_n)
  stop("row count disagrees with the M4 model sample - the export and the estimates would ",
       "describe different people")
cat("sample matches the fitted M4 model.\n")

dest <- file.path(out_dir, paste0("participant_level_m4_", CYCLE, ".csv"))
write.csv(out, dest, row.names = FALSE)

## a short description of what was exported, so the file can be sanity-checked at a glance
cat("\n================ PARTICIPANT-LEVEL EXPORT,", CYCLE, "================\n")
cat(sprintf("participants: %d\n", nrow(out)))
cat("\nmedication band:\n"); print(table(out$medication_band))
cat(sprintf("\nmedication count: mean %.2f, median %g, range %g-%g\n",
            mean(out$medication_count), median(out$medication_count),
            min(out$medication_count), max(out$medication_count)))
cat(sprintf("Boustani burden : mean %.2f, SD %.3f, range %g-%g | %.1f%% score zero\n",
            mean(out$boustani_burden), sd(out$boustani_burden),
            min(out$boustani_burden), max(out$boustani_burden),
            100 * mean(out$boustani_burden == 0)))
cat(sprintf("IACB burden     : mean %.2f, SD %.3f, range %g-%g | %.1f%% score zero\n",
            mean(out$iacb_burden), sd(out$iacb_burden),
            min(out$iacb_burden), max(out$iacb_burden),
            100 * mean(out$iacb_burden == 0)))
cat(sprintf("DSST            : mean %.1f, SD %.1f, range %g-%g\n",
            mean(out$DSST), sd(out$DSST), min(out$DSST), max(out$DSST)))
cat(sprintf("\ncorrelation between the two burdens (Spearman): %.3f\n",
            cor(out$boustani_burden, out$iacb_burden, method = "spearman")))

cat("\nwrote:", normalizePath(dest, winslash = "/", mustWork = FALSE), "\n")
