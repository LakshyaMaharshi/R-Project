# regression models - cognition (lm) + mortality (Cox)
# this was the earlier round before Dr Sami told me to switch to the survey
# weighted approach (see 05_main_analysis.R for the proper version).
# keeping it because the mortality/Cox bit isn't redone there yet.
# NOTE: these are UNWEIGHTED - don't quote these numbers in the writeup, the
# weighted ones in 05 are the ones that count.

library(survival)

# tiny helper - default if NULL. picked this up from a stackoverflow answer.
`%||%` <- function(a, b) if (!is.null(a)) a else b

# path setup so it can find things relative to this file.
# Rscript uses the --file path; in jupyter it falls back to the working dir
# (so setwd() to the code/ folder first).
args_full <- commandArgs(trailingOnly = FALSE)
file_arg  <- grep("^--file=", args_full, value = TRUE)
if (length(file_arg) > 0) {
  script_dir <- dirname(normalizePath(sub("^--file=", "", file_arg[1]),
                                      winslash = "/", mustWork = FALSE))
} else {
  script_dir <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}
base_dir <- file.path(script_dir, "..")

input_path    <- file.path(base_dir, "outputs", "analysis_dataset_with_mortality.csv")
out_cognitive <- file.path(base_dir, "outputs", "cognitive_models_results.csv")
out_mortality <- file.path(base_dir, "outputs", "mortality_cox_results.csv")

# pull the focal predictor rows out of an lm fit (estimate + 95% CI + p)
extract_lm_rows <- function(fit, model_name, outcome_name, predictors, n_used) {
  sm <- summary(fit)
  coef_tbl <- as.data.frame(sm$coefficients)
  ci_tbl   <- as.data.frame(confint(fit))

  rows <- list()
  for (pred in predictors) {
    if (pred %in% rownames(coef_tbl) && pred %in% rownames(ci_tbl)) {
      rows[[length(rows) + 1]] <- data.frame(
        model       = model_name,
        outcome     = outcome_name,
        predictor   = pred,
        coefficient = unname(coef_tbl[pred, "Estimate"]),
        ci_lower    = unname(ci_tbl[pred, 1]),
        ci_upper    = unname(ci_tbl[pred, 2]),
        p_value     = unname(coef_tbl[pred, "Pr(>|t|)"]),
        n_used      = n_used,
        stringsAsFactors = FALSE
      )
    }
  }

  # return an empty frame with the right cols if nothing matched (keeps rbind happy)
  if (length(rows) == 0) {
    return(data.frame(
      model = character(), outcome = character(), predictor = character(),
      coefficient = numeric(), ci_lower = numeric(), ci_upper = numeric(),
      p_value = numeric(), n_used = integer(), stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

# same idea for cox, but report hazard ratios (exp coef) not raw coefs
extract_cox_rows <- function(fit, model_name, predictors, n_used, events) {
  sm <- summary(fit)
  coef_tbl <- as.data.frame(sm$coefficients)
  ci_tbl   <- as.data.frame(sm$conf.int)

  rows <- list()
  for (pred in predictors) {
    if (pred %in% rownames(coef_tbl) && pred %in% rownames(ci_tbl)) {
      rows[[length(rows) + 1]] <- data.frame(
        model        = model_name,
        predictor    = pred,
        hazard_ratio = unname(ci_tbl[pred, "exp(coef)"]),
        ci_lower     = unname(ci_tbl[pred, "lower .95"]),
        ci_upper     = unname(ci_tbl[pred, "upper .95"]),
        p_value      = unname(coef_tbl[pred, "Pr(>|z|)"]),
        n_used       = n_used,
        events       = events,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) {
    return(data.frame(
      model = character(), predictor = character(), hazard_ratio = numeric(),
      ci_lower = numeric(), ci_upper = numeric(), p_value = numeric(),
      n_used = integer(), events = integer(), stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

run_lm_model <- function(df, formula_text, model_name, outcome_name, focal_predictors) {
  needed <- unique(c(outcome_name, "RIDAGEYR", "sex", "education", focal_predictors))
  model_df <- df[complete.cases(df[, needed]), needed, drop = FALSE]   # complete case
  fit <- lm(as.formula(formula_text), data = model_df)
  extract_lm_rows(fit, model_name, outcome_name, focal_predictors, nrow(model_df))
}

run_cox_model <- function(df, formula_text, model_name, focal_predictors) {
  needed <- unique(c("follow_up_years", "MORTSTAT", "RIDAGEYR", "sex", "education", focal_predictors))
  model_df <- df[complete.cases(df[, needed]), needed, drop = FALSE]
  # drop zero/negative follow-up and anything that isn't a clean 0/1 status
  model_df <- model_df[model_df$follow_up_years > 0 & model_df$MORTSTAT %in% c(0, 1), ]

  fit <- coxph(as.formula(formula_text), data = model_df)
  extract_cox_rows(fit, model_name, focal_predictors,
                   nrow(model_df), sum(model_df$MORTSTAT == 1))
}

# --- load + recode ---
df <- read.csv(input_path, stringsAsFactors = FALSE)
cat("loaded", nrow(df), "rows from", basename(input_path), "\n")

df$RIDAGEYR        <- as.numeric(df$RIDAGEYR)
df$acb_burden      <- as.numeric(df$acb_burden)
df$n_drugs         <- as.numeric(df$n_drugs)
df$CFDDS           <- as.numeric(df$CFDDS)
df$CFDAST          <- as.numeric(df$CFDAST)
df$MORTSTAT        <- as.numeric(df$MORTSTAT)
df$follow_up_years <- as.numeric(df$follow_up_years)

df$sex <- factor(df$RIAGENDR, levels = c(1, 2), labels = c("Male", "Female"))  # 1=M 2=F

# education 7/9 are refused/dont-know, not real levels
df$education_raw <- as.numeric(df$DMDEDUC2)
df$education_raw[df$education_raw %in% c(7, 9)] <- NA
df$education <- factor(df$education_raw, levels = c(1, 2, 3, 4, 5), ordered = TRUE)

# --- cognitive models (DSST + fluency, 3 each) ---
# basic sequence: ACB only, drug count only, both together
cog_results <- list(
  run_lm_model(df, "CFDDS ~ acb_burden + RIDAGEYR + sex + education",
               "ACB only", "CFDDS", c("acb_burden")),
  run_lm_model(df, "CFDDS ~ n_drugs + RIDAGEYR + sex + education",
               "Drug count only", "CFDDS", c("n_drugs")),
  run_lm_model(df, "CFDDS ~ acb_burden + n_drugs + RIDAGEYR + sex + education",
               "Both together", "CFDDS", c("acb_burden", "n_drugs")),
  run_lm_model(df, "CFDAST ~ acb_burden + RIDAGEYR + sex + education",
               "ACB only", "CFDAST", c("acb_burden")),
  run_lm_model(df, "CFDAST ~ n_drugs + RIDAGEYR + sex + education",
               "Drug count only", "CFDAST", c("n_drugs")),
  run_lm_model(df, "CFDAST ~ acb_burden + n_drugs + RIDAGEYR + sex + education",
               "Both together", "CFDAST", c("acb_burden", "n_drugs"))
)

cognitive_tbl <- do.call(rbind, cog_results)
write.csv(cognitive_tbl, out_cognitive, row.names = FALSE)

# --- mortality Cox models (3) ---
cox_results <- list(
  run_cox_model(df, "Surv(follow_up_years, MORTSTAT) ~ acb_burden + RIDAGEYR + sex + education",
                "ACB only", c("acb_burden")),
  run_cox_model(df, "Surv(follow_up_years, MORTSTAT) ~ n_drugs + RIDAGEYR + sex + education",
                "Drug count only", c("n_drugs")),
  run_cox_model(df, "Surv(follow_up_years, MORTSTAT) ~ acb_burden + n_drugs + RIDAGEYR + sex + education",
                "Both together", c("acb_burden", "n_drugs"))
)

mortality_tbl <- do.call(rbind, cox_results)
write.csv(mortality_tbl, out_mortality, row.names = FALSE)

cat("saved cognitive results to:", out_cognitive, "\n")
cat("saved mortality Cox results to:", out_mortality, "\n")
cat("cognitive rows:", nrow(cognitive_tbl), " mortality rows:", nrow(mortality_tbl), "\n")
