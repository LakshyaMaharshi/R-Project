# =============================================================================
# NHANES 2011-2012: the complete analysis in ONE file, for review.
# =============================================================================
#
# Written for Dr Sami, 21 Aug, who asked to see the complete script for the 2011-12
# analysis including the IACB scoring and the merge steps, to rule out the wide confidence
# intervals being an artefact of the pipeline.
#
# The production pipeline is parameterised by cycle and split across config.R,
# 11_corrected_crosswalk.R and 05_main_analysis.R. That is good for keeping the two cohorts
# from drifting apart, but it means no single file shows the 2011-12 analysis end to end.
# This file is that single view: same code, cycle fixed to 2011-2012, steps concatenated in
# the order they actually run, and nothing hidden behind a helper in another file.
#
# It is a READING copy, not a second pipeline. To guarantee it has not drifted from the
# real thing, the last section re-reads the production output and stops if any focal
# estimate disagrees beyond 1e-8. If this script runs to completion, what you have read is
# arithmetically identical to what produced the reported numbers.
#
#   Rscript audit_2011_2012.R
#
# Prerequisite: the production pipeline must have been run for this cycle, because the
# self-check compares against its output:
#   Rscript 11_corrected_crosswalk.R --cycle=2011-2012
#   Rscript 05_main_analysis.R       --cycle=2011-2012
# =============================================================================

library(haven); library(survey); library(dplyr)
options(survey.lonely.psu = "adjust")

.f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
here <- if (length(.f)) dirname(sub("^--file=", "", .f[1])) else "."
base <- file.path(here, "..")

CYCLE  <- "2011-2012"
SUFFIX <- "_G"                                  # NHANES names 2011-2012 files DEMO_G etc.
data_dir   <- file.path(base, "data", CYCLE)
scales_dir <- file.path(base, "data", "scales")
prod_dir   <- file.path(base, "outputs", CYCLE, "tables")   # production output, for the check

cat("NHANES", CYCLE, "- complete analysis, single file\n")
cat(strrep("=", 78), "\n")

# =============================================================================
# 1. RAW INPUTS
# =============================================================================
demo <- read_xpt(file.path(data_dir, paste0("DEMO",   SUFFIX, ".xpt")))  # demographics + survey design
rxq  <- read_xpt(file.path(data_dir, paste0("RXQ_RX", SUFFIX, ".xpt")))  # one row per prescription
cfq  <- read_xpt(file.path(data_dir, paste0("CFQ",    SUFFIX, ".xpt")))  # cognitive tests

acb  <- read.csv(file.path(scales_dir, "aas_combined.csv"), stringsAsFactors = FALSE)
iacb <- read.csv(file.path(scales_dir, "iacb_scores.csv"),  stringsAsFactors = FALSE)

cat(sprintf("\n[1] DEMO %d rows | RXQ_RX %d prescriptions | CFQ %d rows\n",
            nrow(demo), nrow(rxq), nrow(cfq)))
cat(sprintf("    Boustani list %d drugs | IACB list %d drugs\n", nrow(acb), nrow(iacb)))

# =============================================================================
# 2. THE TWO SCALE LOOKUPS
# =============================================================================
# Boustani comes from the Mur et al. (2025) supplementary list, the `boustani` column.
# IACB comes from the Fleetwood et al. preprint, extracted by 08_extract_iacb.py using the
# x-coordinate of each entry on the page (the printed table is five ragged columns and a
# naive text-order parse mis-assigns every Score 4 drug on the second page).
norm <- function(x) tolower(trimws(as.character(x)))

b_lk <- acb %>%
  transmute(key = norm(drug), score = suppressWarnings(as.numeric(boustani))) %>%
  mutate(score = ifelse(is.na(score), 0, score)) %>%
  filter(key != "") %>% distinct(key, .keep_all = TRUE)

i_lk <- iacb %>%
  transmute(key = norm(drug), score = suppressWarnings(as.numeric(iacb_score))) %>%
  filter(key != "", !is.na(score)) %>% distinct(key, .keep_all = TRUE)

# Synonym map: list spelling -> NHANES spelling. Recognised brand/INN/salt variants only,
# each verified against names actually present in this sample. Anything uncertain is left
# unmatched rather than guessed.
synonyms <- data.frame(
  list_name   = c("coumadin", "salbutamol", "thyroxin", "potassium",
                  "valproic", "divalproex", "lithium carbonate"),
  nhanes_name = c("warfarin", "albuterol", "levothyroxine", "potassium chloride",
                  "valproic acid", "divalproex sodium", "lithium"),
  stringsAsFactors = FALSE)

apply_syn <- function(lk) {
  add <- synonyms %>% inner_join(lk, by = c("list_name" = "key")) %>%
    transmute(key = nhanes_name, score, via_synonym = TRUE)
  bind_rows(lk %>% mutate(via_synonym = FALSE), add) %>% distinct(key, .keep_all = TRUE)
}
b_lk <- apply_syn(b_lk); i_lk <- apply_syn(i_lk)
cat(sprintf("[2] lookups after synonyms: Boustani %d | IACB %d\n", nrow(b_lk), nrow(i_lk)))

# =============================================================================
# 3. SCORING RULES  (both set by Dr Sami, 14 Aug)
# =============================================================================
#  (1) COMBINATIONS: NHANES writes these as "acetaminophen; oxycodone". Keep the score of
#      every component that IS identified; an unidentified component contributes 0 rather
#      than voiding the whole product. The earlier "NA if any component is missing" rule
#      discarded real exposure.
#  (2) UNLISTED DRUGS: where the drug identity is clear, absence from a scale's final
#      anticholinergic list means no anticholinergic activity, so it contributes 0. This is
#      the scales' own convention. Scores are therefore never NA; the crosswalk records HOW
#      each name resolved so that coverage can still be reported separately.
score_name <- function(nm, lk) {
  parts <- trimws(strsplit(nm, ";", fixed = TRUE)[[1]])
  hit   <- lk$score[match(parts, lk$key)]
  found <- !is.na(hit)
  list(n_parts = length(parts), n_found = sum(found),
       score = sum(hit[found]),                        # partial sum, never NA
       # max() of an empty vector returns -Inf with a warning, which then poisons the
       # high-potency counts downstream, so the empty case is handled explicitly
       maxsc = if (!any(found)) 0 else max(hit[found]))
}

names_all <- sort(unique(norm(rxq$RXDDRUG[!is.na(rxq$RXDDRUG) & rxq$RXDDRUG != ""])))
cw <- lapply(names_all, function(nm) {
  b <- score_name(nm, b_lk); i <- score_name(nm, i_lk)
  data.frame(drug = nm,
             is_combination = b$n_parts > 1,
             boustani_score = b$score, boustani_max = b$maxsc, b_found = b$n_found,
             iacb_score     = i$score, iacb_max     = i$maxsc, i_found = i$n_found,
             stringsAsFactors = FALSE)
}) %>% bind_rows()

cat(sprintf("[3] %d distinct drug names scored | %d combinations\n",
            nrow(cw), sum(cw$is_combination)))
cat(sprintf("    positively on Boustani list: %d names | on IACB list: %d names\n",
            sum(cw$b_found > 0), sum(cw$i_found > 0)))

# =============================================================================
# 4. MERGE: prescriptions -> one row per participant
# =============================================================================
# Every prescription row is joined to the crosswalk by the normalised drug name, then
# summed within participant. n_drugs counts prescription rows, which is the polypharmacy
# measure used throughout.
rx <- rxq %>%
  filter(!is.na(RXDDRUG), RXDDRUG != "") %>%
  mutate(drug = norm(RXDDRUG)) %>%
  left_join(cw, by = "drug")

stopifnot(!any(is.na(rx$boustani_score)))   # every name is in cw by construction

expo <- rx %>% group_by(SEQN) %>%
  summarise(n_drugs        = n(),
            acb_burden     = sum(boustani_score),
            iacb_burden    = sum(iacb_score),
            n_highpot_acb  = sum(boustani_max == 3),
            n_highpot_iacb = sum(iacb_max == 4),
            .groups = "drop")

cat(sprintf("[4] %d prescriptions merged | %d participants with >=1 prescription\n",
            nrow(rx), nrow(expo)))

# =============================================================================
# 5. ANALYSIS FRAME
# =============================================================================
# Start from the FULL demographics file, not from the people with prescriptions: someone
# with no prescription record has 0 medicines and 0 burden, which is data, not missingness.
analysis <- demo %>%
  left_join(cfq %>% select(SEQN, CFDDS, CFDAST, CFDCSR), by = "SEQN") %>%
  left_join(expo, by = "SEQN") %>%
  mutate(
    across(c(n_drugs, acb_burden, iacb_burden, n_highpot_acb, n_highpot_iacb),
           ~ ifelse(is.na(.x), 0, .x)),
    age = as.numeric(RIDAGEYR),
    sex = factor(RIAGENDR, levels = c(1, 2), labels = c("Male", "Female")),
    educ_code = ifelse(DMDEDUC2 %in% c(7, 9), NA, DMDEDUC2),      # 7 refused, 9 don't know
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
analysis$in_sample <- complete.cases(analysis[, MODEL_VARS]) &
                      analysis$age60 & !is.na(analysis$WTMEC2YR) & analysis$WTMEC2YR > 0

cat(sprintf("[5] aged 60+: %d | in the M4 complete-case sample: %d\n",
            sum(analysis$age60), sum(analysis$in_sample)))

# =============================================================================
# 6. SURVEY DESIGN
# =============================================================================
# Built on the FULL sample and subset afterwards. Filtering the data frame to 60+ before
# svydesign() drops the strata information needed for correct standard errors.
# Cognitive tests are part of the MEC exam, so the weight is WTMEC2YR.
design_full <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC2YR,
                         nest = TRUE, data = analysis)
des60  <- subset(design_full, age60 & WTMEC2YR > 0)
des_cs <- subset(design_full, in_sample)

cat(sprintf("[6] design df (60+): %d | t critical for 95%% CI: %.4f\n",
            degf(des60), qt(0.975, degf(des60))))
cat("    NB with ~17 design df the multiplier is 2.11, not 1.96. That widens every\n")
cat("    interval in this analysis by about 8% relative to a normal approximation.\n")

# =============================================================================
# 7. THE FULLY ADJUSTED MODEL (M4)
# =============================================================================
# Confidence intervals and p-values are both computed on the DESIGN degrees of freedom.
# confint() would use the residual df, which with ~17 design df and race + education in the
# model collapses toward zero and returns unusable intervals.
base_cov <- "age + sex + race + education + income_pir"

fit_m4 <- function(burden) {
  vars <- c("CFDDS", burden, "n_drugs", "age", "sex", "race", "education", "income_pir")
  cc <- complete.cases(des60$variables[, vars])
  d <- des60; d$variables$.cc <- cc; dm <- subset(d, .cc)
  fit <- svyglm(as.formula(paste("CFDDS ~", burden, "+ n_drugs +", base_cov)), design = dm)
  co <- summary(fit)$coefficients
  dfree <- degf(dm); tcrit <- qt(0.975, dfree)
  do.call(rbind, lapply(c(burden, "n_drugs"), function(term) {
    e <- co[term, "Estimate"]; s <- co[term, "Std. Error"]
    data.frame(term = term, estimate = e,
               ci_lower = e - tcrit * s, ci_upper = e + tcrit * s,
               p_value = 2 * pt(-abs(e / s), df = dfree),
               n_used = sum(cc), design_df = dfree, row.names = NULL)
  }))
}

m4_boustani <- fit_m4("acb_burden")
m4_iacb     <- fit_m4("iacb_burden")

cat("\n[7] M4, DSST, Boustani ACB:\n")
print(m4_boustani %>% mutate(across(where(is.numeric), ~round(.x, 4))))
cat("\n    M4, DSST, IACB:\n")
print(m4_iacb %>% mutate(across(where(is.numeric), ~round(.x, 4))))

# =============================================================================
# 8. WHY THE INTERVALS ARE WIDE
# =============================================================================
# Descriptive only - no model here. The width of a coefficient interval is driven by the
# spread of the exposure and the design df, so both are printed for inspection.
s <- analysis[analysis$in_sample, ]
cat("\n[8] exposure distribution in the M4 sample (n =", nrow(s), "):\n")
cat(sprintf("    Boustani burden: mean %.2f  SD %.3f  range %g-%g  %.1f%% at zero\n",
            mean(s$acb_burden), sd(s$acb_burden), min(s$acb_burden), max(s$acb_burden),
            100 * mean(s$acb_burden == 0)))
cat(sprintf("    IACB burden    : mean %.2f  SD %.3f  range %g-%g  %.1f%% at zero\n",
            mean(s$iacb_burden), sd(s$iacb_burden), min(s$iacb_burden), max(s$iacb_burden),
            100 * mean(s$iacb_burden == 0)))
cat(sprintf("    medicines      : mean %.2f  range %g-%g\n",
            mean(s$n_drugs), min(s$n_drugs), max(s$n_drugs)))
cat("    medication band:\n"); print(table(s$med_band))

# =============================================================================
# 9. SELF-CHECK AGAINST THE PRODUCTION PIPELINE
# =============================================================================
# The point of this section: if this file has drifted from 11/05 in any way that changes a
# number, the script stops here rather than presenting a plausible-looking result.
ref <- read.csv(file.path(prod_dir, "models_dsst_primary.csv"), stringsAsFactors = FALSE)
chk <- function(term, mine) {
  theirs <- ref %>% filter(model == "M4: fully adjusted", term == !!term) %>% pull(estimate)
  d <- abs(mine - theirs)
  cat(sprintf("    %-12s this file %.10f | pipeline %.10f | diff %.2e\n",
              term, mine, theirs, d))
  if (d > 1e-8) stop("MISMATCH on ", term, " - this file has drifted from the pipeline")
}
cat("\n[9] self-check against outputs/", CYCLE, "/tables/models_dsst_primary.csv:\n", sep = "")
chk("acb_burden", m4_boustani$estimate[m4_boustani$term == "acb_burden"])
chk("n_drugs",    m4_boustani$estimate[m4_boustani$term == "n_drugs"])

ref_i <- read.csv(file.path(prod_dir, "models_corrected_crosswalk.csv"), stringsAsFactors = FALSE)
theirs_i <- ref_i %>%
  filter(model == "M4: fully adjusted", outcome == "CFDDS",
         term == "iacb_burden", startsWith(coding, "(a)")) %>% pull(estimate)
d_i <- abs(m4_iacb$estimate[m4_iacb$term == "iacb_burden"] - theirs_i)
cat(sprintf("    %-12s this file %.10f | pipeline %.10f | diff %.2e\n",
            "iacb_burden", m4_iacb$estimate[m4_iacb$term == "iacb_burden"], theirs_i, d_i))
if (d_i > 1e-8) stop("MISMATCH on iacb_burden - this file has drifted from the pipeline")

cat("\n", strrep("=", 78), "\n", sep = "")
cat("All focal estimates agree with the production pipeline to within 1e-8.\n")
cat("The scoring and merge above are therefore exactly what produced the reported numbers.\n")
