# NHANES 2013-2014 - ACB vs polypharmacy and cognition
# main analysis script (survey weighted) - Jignesh
#
# question Dr Sami wants answered: is anticholinergic burden (ACB) associated with
# cognition independently of the number of meds someone is on? "ACB is bad for
# cognition" on its own is already known, so the novel bit has to be
# ACB-beyond-polypharmacy.
#
# NB "associated with", not "predicts" - his 16 Aug note. This is one cross-sectional
# cycle, so nothing here is prediction. ipw_predictors below keeps its name because
# that model genuinely IS predicting response probability, which is a different thing.
#
# this is the proper redo after the v1 unweighted analysis (which was wrong -
# you can't ignore the NHANES weights). DSST is the primary outcome, animal
# fluency is secondary. ACB looked at both continuous and as 0 / 1-2 / 3+.
#
# everything is associational - NHANES med use is just recent prescriptions,
# this design cannot say anything about deprescribing. keep the language careful.

library(haven)
library(survey)
library(dplyr)
library(tidyr)

# this matters - without it the lonely PSU strata throw errors / NaN SEs
options(survey.lonely.psu = "adjust")

# figure out where the script lives so the relative paths work.
# took a couple tries to get this right on windows vs source() vs jupyter.
args_full <- commandArgs(trailingOnly = FALSE)
file_arg  <- grep("^--file=", args_full, value = TRUE)
if (length(file_arg) > 0) {
  # run with Rscript - the folder comes from the --file path
  script_dir <- dirname(normalizePath(sub("^--file=", "", file_arg[1]),
                                      winslash = "/", mustWork = FALSE))
} else {
  # interactive / Jupyter (IRkernel): just use the working dir, so you MUST
  # setwd() to the code/ folder before running this. see ../README.md.
  script_dir <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}
base_dir <- file.path(script_dir, "..")

data_dir <- file.path(base_dir, "data")
out_dir  <- file.path(base_dir, "outputs", "v2")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat("data dir:", normalizePath(data_dir, mustWork = FALSE), "\n")
cat("out dir: ", normalizePath(out_dir,  mustWork = FALSE), "\n")


## 1. load the raw NHANES files ------------------------------------------------
demo <- read_xpt(file.path(data_dir, "DEMO_H.xpt"))
rxq  <- read_xpt(file.path(data_dir, "RXQ_RX_H.xpt"))
cfq  <- read_xpt(file.path(data_dir, "CFQ_H.xpt"))

cat(sprintf("loaded: demo=%d rows, rxq=%d rows, cfq=%d rows\n",
            nrow(demo), nrow(rxq), nrow(cfq)))
# str(demo)   # uncomment if i forget the variable names again


## 2. ACB scoring (Boustani 2008, via the corrected crosswalk) ------------------
# Scoring now comes from crosswalk_corrected.csv, built by 11_corrected_crosswalk.R
# (run that first). The crosswalk splits combination products on ";" and scores each
# component, applies a small documented synonym map, and distinguishes a confirmed
# score of zero from a drug that is simply not on the list. For this single-scale
# primary analysis, drugs the list does not know remain at zero burden (the standard
# convention); the scale-comparison consequences of that convention are handled in
# 11 with the fully-classified and common-drug codings.
cw_path <- file.path(out_dir, "crosswalk_corrected.csv")
if (!file.exists(cw_path)) stop("crosswalk_corrected.csv not found - run 11_corrected_crosswalk.R first")
cw <- read.csv(cw_path, stringsAsFactors = FALSE)

rx <- rxq %>%
  filter(!is.na(RXDDRUG), RXDDRUG != "") %>%
  mutate(drug = tolower(trimws(as.character(RXDDRUG)))) %>%
  left_join(cw %>% select(drug, boustani_score, boustani_max), by = "drug")

cat(sprintf("Boustani resolution: %d/%d prescription rows resolved (%.1f%%); %.1f%% score > 0\n",
            sum(!is.na(rx$boustani_score)), nrow(rx), 100 * mean(!is.na(rx$boustani_score)),
            100 * mean(coalesce(rx$boustani_score, 0) > 0)))

# roll up to one row per person (unresolved drugs contribute 0 burden)
exposure <- rx %>%
  group_by(SEQN) %>%
  summarise(
    n_drugs     = n(),                                   # total prescriptions = polypharmacy
    acb_burden  = sum(coalesce(boustani_score, 0)),      # ACB burden - the exposure
    n_acb_drugs = sum(coalesce(boustani_score, 0) > 0),  # how many anticholinergics
    n_highpot   = sum(coalesce(boustani_max, 0) == 3),   # any component at the top score
    .groups = "drop"
  )


## 3. optional comorbidity files (Dr Sami item 1) ------------------------------
# He asked for stroke / diabetes / CVD / depression / self-rated health as
# covariates. Those live in separate NHANES files that aren't downloaded by
# default, so load each ONLY if present and otherwise leave the column NA.
# That way the script still runs end-to-end with just the 3 core files.
#
# files needed for the full set:
#   MCQ_H.xpt  -> stroke (MCQ160F), heart disease (MCQ160B/C/D/E)
#   DIQ_H.xpt  -> diabetes (DIQ010)
#   DPQ_H.xpt  -> depression, PHQ-9 (DPQ010..DPQ090)
#   HSQ_H.xpt  -> self-rated health (HSD010)

# helper - 1=yes 2=no, everything else (7 refused / 9 dont know / .) -> NA
yn <- function(x) ifelse(x == 1, 1L, ifelse(x == 2, 0L, NA_integer_))

como <- tibble(SEQN = demo$SEQN)  # start from everyone, fill what we can

mcq_path <- file.path(data_dir, "MCQ_H.xpt")
if (file.exists(mcq_path)) {
  mcq <- read_xpt(mcq_path)
  mcq2 <- mcq %>% transmute(
    SEQN,
    stroke = yn(MCQ160F),
    # CVD = any of CHF / coronary HD / angina / heart attack. stroke kept separate.
    cvd = pmax(yn(MCQ160B), yn(MCQ160C), yn(MCQ160D), yn(MCQ160E), na.rm = TRUE)
  )
  como <- left_join(como, mcq2, by = "SEQN")
  cat("MCQ_H loaded - got stroke + CVD\n")
} else {
  como$stroke <- NA_integer_; como$cvd <- NA_integer_
  cat("[skip] MCQ_H.xpt not found - stroke/CVD will be NA\n")
}

diq_path <- file.path(data_dir, "DIQ_H.xpt")
if (file.exists(diq_path)) {
  diq <- read_xpt(diq_path)
  # DIQ010: 1 yes, 2 no, 3 borderline, 7/9 missing. counting borderline as no.
  como <- left_join(como, diq %>% transmute(SEQN, diabetes = yn(DIQ010)), by = "SEQN")
  cat("DIQ_H loaded - got diabetes\n")
} else {
  como$diabetes <- NA_integer_
  cat("[skip] DIQ_H.xpt not found - diabetes will be NA\n")
}

dpq_path <- file.path(data_dir, "DPQ_H.xpt")
if (file.exists(dpq_path)) {
  dpq <- read_xpt(dpq_path)
  # DPQ010..DPQ090 are the nine scored items, each 0-3. DPQ100 asks how difficult the
  # symptoms made things and is NOT part of the score, so it stays out.
  phq_items <- paste0("DPQ0", c("10","20","30","40","50","60","70","80","90"))
  d <- dpq %>% select(SEQN, any_of(phq_items))
  # 7 refused / 9 don't know -> NA
  d[phq_items] <- lapply(d[phq_items], function(x) ifelse(x %in% c(7, 9), NA, x))
  d$n_ans   <- rowSums(!is.na(d[phq_items]))
  d$partial <- rowSums(d[phq_items], na.rm = TRUE)
  d$n_miss  <- length(phq_items) - d$n_ans

  # Dr Sami asked me to check this and he was right to. The old line was
  #   phq9 <- rowSums(items, na.rm = TRUE); depression <- phq9 >= 10
  # which scores an unanswered item as if the person had answered "not at all". 527
  # people in DPQ_H answered NONE of the nine items and were all being handed a PHQ-9
  # of 0 and depression = 0 - a fabricated negative, not a measurement. In the 60+
  # cognitive sample that was 141 people wrongly called not-depressed, 125 of whom
  # answered nothing at all, and they were then kept in M4+ on that basis.
  #
  # Items only ever add, so two cases are decidable without the missing answers:
  #   partial >= 10                  -> over the cutoff whatever the missing items are
  #   partial + 3*n_missing < 10     -> under it even if every missing item were a 3
  # Anything else is genuinely unknown and becomes NA, which drops the person from
  # the comorbidity models rather than inventing an answer for them.
  d$depression <- ifelse(d$partial >= 10, 1L,
                  ifelse(d$partial + 3 * d$n_miss < 10, 0L, NA_integer_))
  como <- left_join(como, d %>% select(SEQN, depression), by = "SEQN")
  cat(sprintf(paste0("DPQ_H loaded - PHQ-9 depression: %d yes / %d no / %d undetermined ",
                     "(%d had an incomplete PHQ-9)\n"),
              sum(d$depression == 1, na.rm = TRUE), sum(d$depression == 0, na.rm = TRUE),
              sum(is.na(d$depression)), sum(d$n_ans < length(phq_items))))
} else {
  como$depression <- NA_integer_
  cat("[skip] DPQ_H.xpt not found - depression will be NA\n")
}

hsq_path <- file.path(data_dir, "HSQ_H.xpt")
if (file.exists(hsq_path)) {
  hsq <- read_xpt(hsq_path)
  # HSD010: 1 excellent ... 5 poor, 7/9 missing. collapse to fair/poor vs better.
  hsq2 <- hsq %>% transmute(
    SEQN,
    srh_fairpoor = ifelse(HSD010 %in% c(4, 5), 1L,
                   ifelse(HSD010 %in% c(1, 2, 3), 0L, NA_integer_))
  )
  como <- left_join(como, hsq2, by = "SEQN")
  cat("HSQ_H loaded - got self-rated health\n")
} else {
  como$srh_fairpoor <- NA_integer_
  cat("[skip] HSQ_H.xpt not found - self-rated health will be NA\n")
}

# which health vars actually have data? used later to build the model formula.
health_vars <- c("stroke", "cvd", "diabetes", "depression", "srh_fairpoor")
health_available <- health_vars[vapply(health_vars,
                      function(v) any(!is.na(como[[v]])), logical(1))]
cat("health covariates available:",
    if (length(health_available)) paste(health_available, collapse = ", ") else "NONE yet",
    "\n")


## 4. build the person-level analysis frame (start from FULL demo) -------------
analysis <- demo %>%
  left_join(cfq %>% select(SEQN, CFDDS, CFDAST, CFDCSR), by = "SEQN") %>%
  left_join(exposure, by = "SEQN") %>%
  left_join(como, by = "SEQN") %>%
  mutate(
    # no prescription record = 0 drugs / 0 burden (not missing)
    n_drugs     = ifelse(is.na(n_drugs), 0, n_drugs),
    acb_burden  = ifelse(is.na(acb_burden), 0, acb_burden),
    n_acb_drugs = ifelse(is.na(n_acb_drugs), 0, n_acb_drugs),
    n_highpot   = ifelse(is.na(n_highpot), 0, n_highpot)
  )

# covariates
analysis <- analysis %>%
  mutate(
    age = as.numeric(RIDAGEYR),
    sex = factor(RIAGENDR, levels = c(1, 2), labels = c("Male", "Female")),

    # DMDEDUC2: 7 refused, 9 dont know -> NA
    educ_code = ifelse(DMDEDUC2 %in% c(7, 9), NA, DMDEDUC2),
    education = factor(educ_code, levels = 1:5,
      labels = c("<9th grade", "9-11th grade", "HS grad/GED",
                 "Some college/AA", "College grad+")),

    # RIDRETH3 race/ethnicity (NH White as reference)
    race = factor(RIDRETH3, levels = c(3, 1, 2, 4, 6, 7),
      labels = c("NH White", "Mexican American", "Other Hispanic",
                 "NH Black", "NH Asian", "Other/Multi")),

    income_pir = as.numeric(INDFMPIR),   # poverty-income ratio, capped at 5 by NHANES

    # Dr Sami wants ACB as a category too: 0 / 1-2 / 3+
    acb_cat = cut(acb_burden, breaks = c(-Inf, 0, 2, Inf),
                  labels = c("ACB 0", "ACB 1-2", "ACB 3+"), right = TRUE),

    age60       = age >= 60,
    in_cfq      = SEQN %in% cfq$SEQN,
    has_dsst    = !is.na(CFDDS),
    has_fluency = !is.na(CFDAST)
  )

# quick sanity check on the exposure categories before going further
cat("\nACB category counts (60+ only):\n")
print(table(analysis$acb_cat[analysis$age60], useNA = "ifany"))

# inclusion = 60+ (the cognitive module was only given to 60+).
# complete-case is handled per model later.
analysis$analytic <- analysis$age60


## sample flow / exclusion accounting ------------------------------------------
flow <- tibble(
  step = c("Full NHANES 2013-2014 (DEMO_H)",
           "Aged 60+",
           "  ...given cognitive module (in CFQ_H)",
           "  ...with valid DSST (CFDDS)",
           "  ...with valid animal fluency (CFDAST)"),
  n = c(nrow(analysis),
        sum(analysis$age60),
        sum(analysis$age60 & analysis$in_cfq),
        sum(analysis$age60 & analysis$has_dsst),
        sum(analysis$age60 & analysis$has_fluency))
)
write.csv(flow, file.path(out_dir, "table_sample_flow.csv"), row.names = FALSE)
cat("\n=== SAMPLE FLOW ===\n"); print(flow)
# observation: a noticeable chunk of the 60+ who were given the module are still
# missing DSST. that gap is exactly what the missingness section below digs into.


## 5. survey design - build on the FULL sample, subset after --------------------
# IMPORTANT: do NOT pre-filter the data frame before svydesign(). if you drop the
# under-60s first the SEs come out wrong. build on everyone, subset() the design.
# cognitive tests are part of the MEC exam so the weight is WTMEC2YR.
design_full <- svydesign(
  ids     = ~SDMVPSU,
  strata  = ~SDMVSTRA,
  weights = ~WTMEC2YR,
  nest    = TRUE,
  data    = analysis
)

# analytic subpopulation: 60+ with a usable MEC weight
design_60 <- subset(design_full, age60 & WTMEC2YR > 0)
cat("\nanalytic design n (rows) =", nrow(design_60), "\n")

# Write the design df out so the figures can build their intervals the same way the
# models do. 09_figures.R was using 1.96 for the Table 2 error bars while every model
# here uses qt(0.975, degf) on ~15 df, so the figure's bars were narrower than the
# analysis they illustrate. Publishing the number beats hardcoding it in two places.
write.csv(data.frame(design = "60+ with positive MEC weight",
                     degf = degf(design_60), t_crit_95 = qt(0.975, degf(design_60))),
          file.path(out_dir, "design_df.csv"), row.names = FALSE)
cat(sprintf("design df = %d, t crit (95%%) = %.4f\n",
            degf(design_60), qt(0.975, degf(design_60))))


## 6. survey-weighted Table 1 (Dr Sami item 4) ---------------------------------
# weighted mean + SE for a continuous var
wmean <- function(des, var) {
  est <- svymean(as.formula(paste0("~", var)), des, na.rm = TRUE)
  c(mean = as.numeric(est), se = as.numeric(SE(est)))
}
# weighted % per level of a factor
wprop <- function(des, var) {
  est <- svymean(as.formula(paste0("~", var)), des, na.rm = TRUE)
  data.frame(level = names(est), pct = as.numeric(est) * 100,
             se = as.numeric(SE(est)) * 100, row.names = NULL)
}

cont_vars <- c("age", "income_pir", "n_drugs", "acb_burden",
               "n_acb_drugs", "n_highpot", "CFDDS", "CFDAST")
cat_vars  <- c("sex", "race", "education", "acb_cat")

t1_cont <- lapply(cont_vars, function(v) {
  m <- wmean(design_60, v)
  data.frame(variable = v, weighted_mean = m["mean"], se = m["se"],
             n_nonmiss = sum(!is.na(design_60$variables[[v]])), row.names = NULL)
}) %>% bind_rows()

t1_cat <- lapply(cat_vars, function(v) {
  d <- wprop(design_60, v); d$variable <- v; d
}) %>% bind_rows() %>% select(variable, level, pct, se)

write.csv(t1_cont, file.path(out_dir, "table1_continuous.csv"),  row.names = FALSE)
write.csv(t1_cat,  file.path(out_dir, "table1_categorical.csv"), row.names = FALSE)

# Table 1 stratified by ACB category - this is the version for the writeup
t1_by_acb <- svyby(~age + n_drugs + CFDDS + CFDAST + income_pir,
                   ~acb_cat, design_60, svymean, na.rm = TRUE)
write.csv(t1_by_acb, file.path(out_dir, "table1_by_acb_category.csv"), row.names = FALSE)

cat("\n=== TABLE 1 (survey-weighted, continuous) ===\n"); print(t1_cont)


## 7. missingness analysis - DSST present vs absent (Dr Sami item 3) -----------
# is the DSST missingness informative? (he said the missing ones look older /
# poorer / on more meds, want to confirm and then do an IPW sensitivity)
miss_vars_cont <- c("age", "n_drugs", "acb_burden", "income_pir")
miss_vars_cat  <- c("sex", "education", "race")

miss_cont <- lapply(miss_vars_cont, function(v) {
  by_tab <- svyby(as.formula(paste0("~", v)), ~has_dsst, design_60, svymean, na.rm = TRUE)
  tt <- tryCatch(svyttest(as.formula(paste0(v, " ~ has_dsst")), design_60),
                 error = function(e) NULL)
  data.frame(
    variable     = v,
    mean_missing = by_tab[by_tab$has_dsst == FALSE, 2],
    mean_present = by_tab[by_tab$has_dsst == TRUE,  2],
    p_value      = if (!is.null(tt)) as.numeric(tt$p.value) else NA_real_,
    row.names    = NULL
  )
}) %>% bind_rows()

# Rao-Scott chi-square for the categorical ones
miss_cat <- lapply(miss_vars_cat, function(v) {
  ch <- tryCatch(svychisq(as.formula(paste0("~", v, " + has_dsst")), design_60),
                 error = function(e) NULL)
  data.frame(variable = v,
             p_value = if (!is.null(ch)) as.numeric(ch$p.value) else NA_real_,
             row.names = NULL)
}) %>% bind_rows()

write.csv(miss_cont, file.path(out_dir, "missingness_continuous.csv"),  row.names = FALSE)
write.csv(miss_cat,  file.path(out_dir, "missingness_categorical.csv"), row.names = FALSE)
cat("\n=== MISSINGNESS: DSST present vs absent ===\n"); print(miss_cont); print(miss_cat)
# if the means here differ a lot (and p small) the missingness is NOT random,
# which is the justification for the IPW model in section 9.


## 8. regression models - the 5-model sequence (Dr Sami item 5) ----------------
# focal-term extractor: pull a term's estimate / 95% CI / p out of an svyglm.
# NOTE: do NOT use confint() here - it builds the CI off the residual df
# (design df minus the number of parameters). NHANES only has ~15 design df, so
# once race + education go in the fully-adjusted models the residual df hits 0
# and confint() spits out Inf / NaN. found this the hard way when M4 CIs blew up.
# so compute Wald CIs against the DESIGN df (degf) instead - this is what Lumley
# recommends for svyglm and it doesn't get eaten by model size. pass dfree in.
tidy_term <- function(fit, term, model_name, outcome, n_used, dfree) {
  co  <- summary(fit)$coefficients
  est <- co[, "Estimate"]
  se  <- co[, "Std. Error"]
  tcrit <- qt(0.975, dfree)
  # recompute the p-value off the same design df too - otherwise summary() uses
  # the blown-out residual df and you get a CI that excludes 0 sitting next to a
  # p of 0.14, which looks broken (it is). keep CI and p on the same df.
  hits <- grep(paste0("^", gsub("([][().])", "\\\\\\1", term)), rownames(co), value = TRUE)
  if (length(hits) == 0) return(NULL)
  do.call(rbind, lapply(hits, function(rn) {
    pval <- 2 * pt(-abs(est[rn] / se[rn]), df = dfree)
    data.frame(model = model_name, outcome = outcome, term = rn,
               estimate = unname(est[rn]),
               ci_lower = unname(est[rn] - tcrit * se[rn]),
               ci_upper = unname(est[rn] + tcrit * se[rn]),
               p_value  = unname(pval),
               n_used   = n_used, row.names = NULL)
  }))
}

# fit one svyglm on 60+ restricted to complete cases of the vars it uses
fit_model <- function(outcome, rhs, vars, model_name, focal_terms) {
  needed  <- unique(c(outcome, vars))
  cc_flag <- complete.cases(design_60$variables[, needed, drop = FALSE])
  des <- design_60
  des$variables$.cc <- cc_flag
  des_m  <- subset(des, .cc)
  n_used <- sum(cc_flag)
  dfree  <- degf(des_m)   # design degrees of freedom for the CIs
  fit <- svyglm(as.formula(paste(outcome, "~", rhs)), design = des_m)
  bind_rows(lapply(focal_terms, tidy_term, fit = fit, model_name = model_name,
                   outcome = outcome, n_used = n_used, dfree = dfree))
}

run_outcome <- function(outcome) {
  base_cov <- "age + sex + race + education + income_pir"

  out <- list(
    # 1 - med count alone
    fit_model(outcome, "n_drugs", "n_drugs",
              "M1: count alone", "n_drugs"),
    # 2 - ACB burden alone
    fit_model(outcome, "acb_burden", "acb_burden",
              "M2: ACB alone", "acb_burden"),
    # 3 - both in together. THIS is the key comparison - does ACB survive
    #     once drug count is in the model?
    fit_model(outcome, "acb_burden + n_drugs", c("acb_burden", "n_drugs"),
              "M3: ACB + count", c("acb_burden", "n_drugs")),
    # 4 - fully adjusted (demographics + SES)
    fit_model(outcome, paste("acb_burden + n_drugs +", base_cov),
              c("acb_burden", "n_drugs", "age", "sex", "race", "education", "income_pir"),
              "M4: fully adjusted", c("acb_burden", "n_drugs")),
    # 5a - ACB as a category instead of continuous
    fit_model(outcome, paste("acb_cat + n_drugs +", base_cov),
              c("acb_cat", "n_drugs", "age", "sex", "race", "education", "income_pir"),
              "M5a: ACB category", "acb_cat"),
    # 5b - high-potency anticholinergic count
    fit_model(outcome, paste("n_highpot + n_drugs +", base_cov),
              c("n_highpot", "n_drugs", "age", "sex", "race", "education", "income_pir"),
              "M5b: high-potency", "n_highpot")
  )

  # M4+ : fully adjusted PLUS the health/comorbidity covariates, but only if
  # those files were actually loaded above (otherwise the model is all-NA).
  if (length(health_available) > 0) {
    rhs4b   <- paste("acb_burden + n_drugs +", base_cov, "+",
                     paste(health_available, collapse = " + "))
    vars4b  <- c("acb_burden", "n_drugs", "age", "sex", "race",
                 "education", "income_pir", health_available)
    out[[length(out) + 1]] <- fit_model(outcome, rhs4b, vars4b,
                                "M4+: + comorbidities", c("acb_burden", "n_drugs"))
  }
  bind_rows(out)
}

dsst_results    <- run_outcome("CFDDS")   # PRIMARY
fluency_results <- run_outcome("CFDAST")  # SECONDARY

write.csv(dsst_results,    file.path(out_dir, "models_dsst_primary.csv"),      row.names = FALSE)
write.csv(fluency_results, file.path(out_dir, "models_fluency_secondary.csv"), row.names = FALSE)

cat("\n=== PRIMARY OUTCOME: DSST (survey-weighted) ===\n");        print(dsst_results)
cat("\n=== SECONDARY OUTCOME: animal fluency (survey-weighted) ===\n"); print(fluency_results)
# main finding to look at: the acb_burden coefficient in M4 should still be
# negative and significant with n_drugs in the model. that's the whole point.


## 9. IPW sensitivity for informative DSST missingness (Dr Sami item 3) --------
# complete-case assumes the missing DSST are missing at random, but section 7
# suggests they aren't (older/poorer/higher ACB drop out). so reweight the
# responders by the inverse probability of having a DSST score, then refit M4
# and see if acb_burden moves. if it barely moves, complete-case is defensible.
#
# (an alternative would be full multiple imputation - heavier to set up with the
#  survey design, leaving that as a possible next step. IPW is the lighter check.)

ipw_predictors <- "age + sex + race + education + income_pir + acb_burden + n_drugs"
ipw_df <- design_60$variables
cc_resp <- complete.cases(ipw_df[, c("age","sex","race","education",
                                     "income_pir","acb_burden","n_drugs")])

# model P(has DSST | covariates) among everyone 60+ with complete covariates
resp_mod <- glm(as.formula(paste("has_dsst ~", ipw_predictors)),
                data = ipw_df[cc_resp, ], family = binomial())
phat <- rep(NA_real_, nrow(ipw_df))
phat[cc_resp] <- predict(resp_mod, type = "response")
# print(summary(resp_mod))   # uncomment to see what drives missingness

# inverse-probability weight = base MEC weight * 1/phat, responders only.
# note: treating the estimated weights as fixed here, so SEs are a touch
# optimistic - fine for a sensitivity check, would bootstrap for the real thing.
ipw_df$ipw_w <- ipw_df$WTMEC2YR * (1 / phat)
resp_data <- ipw_df[ipw_df$has_dsst & cc_resp & is.finite(ipw_df$ipw_w), ]

ipw_design <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA,
                        weights = ~ipw_w, nest = TRUE, data = resp_data)

fit_ipw <- svyglm(CFDDS ~ acb_burden + n_drugs + age + sex + race + education + income_pir,
                  design = ipw_design)
ipw_df_free <- degf(ipw_design)
ipw_res <- bind_rows(
  tidy_term(fit_ipw, "acb_burden", "M4-IPW: DSST", "CFDDS", nrow(resp_data), ipw_df_free),
  tidy_term(fit_ipw, "n_drugs",    "M4-IPW: DSST", "CFDDS", nrow(resp_data), ipw_df_free)
)
write.csv(ipw_res, file.path(out_dir, "models_dsst_ipw.csv"), row.names = FALSE)
cat("\n=== IPW-WEIGHTED DSST (vs complete-case M4) ===\n"); print(ipw_res)
# compare this acb_burden estimate to the M4 one above - if they're close, the
# informative missingness isn't biasing the headline result much.


## 10. stroke-exclusion sensitivity (Dr Sami item 2) ---------------------------
# drop anyone who's had a stroke and refit M4 - cognition could be driven by the
# stroke rather than the meds in those people. needs the stroke var from MCQ_H.
if ("stroke" %in% health_available) {
  cat("\nrunning stroke-exclusion sensitivity...\n")
  design_nostroke <- subset(design_full,
                            age60 & WTMEC2YR > 0 & (is.na(stroke) | stroke == 0))
  ns_vars <- c("CFDDS","acb_burden","n_drugs","age","sex","race","education","income_pir")
  cc <- complete.cases(design_nostroke$variables[, ns_vars])
  des_ns <- design_nostroke
  des_ns$variables$.cc <- cc
  des_ns <- subset(des_ns, .cc)

  fit_ns <- svyglm(CFDDS ~ acb_burden + n_drugs + age + sex + race + education + income_pir,
                   design = des_ns)
  ns_df_free <- degf(des_ns)
  sens <- bind_rows(
    tidy_term(fit_ns, "acb_burden", "M6: exclude stroke", "CFDDS", sum(cc), ns_df_free),
    tidy_term(fit_ns, "n_drugs",    "M6: exclude stroke", "CFDDS", sum(cc), ns_df_free)
  )
  write.csv(sens, file.path(out_dir, "models_dsst_exclude_stroke.csv"), row.names = FALSE)
  print(sens)
} else {
  cat("\n[skip] no stroke variable (MCQ_H.xpt not loaded) - ",
      "download it to run the stroke-exclusion sensitivity.\n", sep = "")
}


## 11. save the cleaned 60+ dataset + session info -----------------------------
clean_cols <- c("SEQN", "age", "sex", "race", "education", "income_pir",
                "n_drugs", "acb_burden", "acb_cat", "n_acb_drugs", "n_highpot",
                "stroke", "cvd", "diabetes", "depression", "srh_fairpoor",
                "CFDDS", "CFDAST", "CFDCSR",
                "WTMEC2YR", "SDMVPSU", "SDMVSTRA", "has_dsst", "has_fluency")
clean <- analysis %>% filter(age60) %>% select(any_of(clean_cols))
write.csv(clean, file.path(out_dir, "analysis_dataset_clean.csv"), row.names = FALSE)

writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))

cat("\ndone. outputs in:", normalizePath(out_dir, mustWork = FALSE), "\n")
