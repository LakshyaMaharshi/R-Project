# Supplementary tables for the dissertation appendix.
#
# The main analysis scripts save only the focal coefficients (burden, medication count),
# because those are what the results sections report. This script refits the same fully
# adjusted models and saves the COMPLETE coefficient tables, including every covariate,
# so the appendix can show that the models behave sensibly (age negative, education
# positive, and so on) rather than asking the reader to take that on trust.
#
# Same design, same covariates, same design-df confidence intervals as 05/06 - only the
# reporting differs. Run after 05_main_analysis.R and 06_scale_sensitivity.R.

library(haven)
library(survey)
library(dplyr)

options(survey.lonely.psu = "adjust")

# Paths and which NHANES cycle to run both come from config.R - see there. Pass
# --cycle=2011-2012 to run the validation cycle; no argument means the dissertation cycle.
.f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
source(file.path(if (length(.f)) dirname(sub("^--file=", "", .f[1])) else ".", "config.R"))

demo <- read_xpt(xpt("DEMO"))
rxq  <- read_xpt(xpt("RXQ_RX"))
cfq  <- read_xpt(xpt("CFQ"))
# scoring comes from the corrected crosswalk (built by 11_corrected_crosswalk.R)
cw <- read.csv(file.path(out_dir, "crosswalk_corrected.csv"), stringsAsFactors = FALSE)

exposure <- rxq %>%
  filter(!is.na(RXDDRUG), RXDDRUG != "") %>%
  mutate(drug = tolower(trimws(as.character(RXDDRUG)))) %>%
  left_join(cw %>% select(drug, boustani_score, iacb_score), by = "drug") %>%
  group_by(SEQN) %>%
  summarise(n_drugs = n(),
            acb_burden  = sum(coalesce(boustani_score, 0)),
            iacb_burden = sum(coalesce(iacb_score, 0)), .groups = "drop")

analysis <- demo %>%
  left_join(cfq %>% select(SEQN, CFDDS, CFDAST), by = "SEQN") %>%
  left_join(exposure, by = "SEQN") %>%
  mutate(across(c(n_drugs, acb_burden, iacb_burden), ~ ifelse(is.na(.x), 0, .x)),
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
    age60 = age >= 60)

des <- subset(svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC2YR,
                        nest = TRUE, data = analysis), age60 & WTMEC2YR > 0)

# full coefficient table for one fully adjusted model
full_coefs <- function(outcome, burden, label) {
  vars <- c(outcome, burden, "n_drugs", "age", "sex", "race", "education", "income_pir")
  cc <- complete.cases(des$variables[, vars])
  d2 <- des; d2$variables$.cc <- cc; d2 <- subset(d2, .cc)
  fit <- svyglm(as.formula(paste(outcome, "~", burden,
                                 "+ n_drugs + age + sex + race + education + income_pir")),
                design = d2)
  co <- summary(fit)$coefficients
  dfree <- degf(d2); tcrit <- qt(0.975, dfree)
  data.frame(
    model = label, outcome = outcome, term = rownames(co),
    estimate = co[, "Estimate"],
    ci_lower = co[, "Estimate"] - tcrit * co[, "Std. Error"],
    ci_upper = co[, "Estimate"] + tcrit * co[, "Std. Error"],
    p_value  = 2 * pt(-abs(co[, "Estimate"] / co[, "Std. Error"]), df = dfree),
    n_used = sum(cc), row.names = NULL)
}

res <- bind_rows(
  full_coefs("CFDDS",  "acb_burden",  "M4 DSST, Boustani ACB"),
  full_coefs("CFDDS",  "iacb_burden", "M4 DSST, IACB"),
  full_coefs("CFDAST", "acb_burden",  "M4 animal fluency, Boustani ACB"))

write.csv(res, file.path(out_dir, "appendix_full_model_coefficients.csv"), row.names = FALSE)
print(as.data.frame(res %>% mutate(across(where(is.numeric), ~round(.x, 4)))))

# sanity: the focal coefficients must match what the main scripts already reported
# Cross-check against 05's own output rather than a hardcoded number - the scoring rules
# have changed twice now and a pasted constant just goes stale and fails for the wrong
# reason. This way the guard still catches genuine drift between the two scripts.
chk <- res %>% filter(model == "M4 DSST, Boustani ACB", term == "acb_burden")
ref <- read.csv(file.path(out_dir, "models_dsst_primary.csv"), stringsAsFactors = FALSE) %>%
  filter(model == "M4: fully adjusted", term == "acb_burden") %>% pull(estimate)
cat(sprintf("\ncheck - M4 Boustani acb_burden here = %.4f | 05_main_analysis.R = %.4f\n",
            chk$estimate, ref))
if (abs(chk$estimate - ref) > 0.001) stop("focal estimate disagrees with 05_main_analysis.R")
cat("matches.\n")
