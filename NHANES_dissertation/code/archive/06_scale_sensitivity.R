# NHANES 2013-2014 - Boustani ACB vs IACB head-to-head comparison
#
# Dr Sami asked (email, attaching his own paper) to apply the IACB scores to the data
# and "analyse them in the same way as you have done for the ACB scale ... using the
# same sample, outcome measures/categories and regression models". So this runs the
# FULL M1-M5 + M4+ sequence for BOTH outcomes under BOTH scales, on the same design.
#
# IACB = International Anticholinergic Burden (Fleetwood et al., SSRN preprint 3777231;
# NOT peer reviewed; Dr Sami is senior author). Scores 0-4, vs Boustani 0-3, so IACB
# burden totals are on a wider scale - flagged in the write-up, not silently compared.
# Scores extracted by code/08_extract_iacb.py -> data/iacb_scores.csv.
#
# He also asked to be told which drug names cannot be matched, so this writes an
# unmatched-drug report.
#
# Everything stays associational - cross-sectional design.

library(haven)
library(survey)
library(dplyr)
library(tidyr)

options(survey.lonely.psu = "adjust")

args_full <- commandArgs(trailingOnly = FALSE)
file_arg  <- grep("^--file=", args_full, value = TRUE)
script_dir <- if (length(file_arg) > 0) {
  dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = FALSE))
} else normalizePath(getwd(), winslash = "/", mustWork = FALSE)
base_dir <- file.path(script_dir, "..")
data_dir <- file.path(base_dir, "data")
out_dir  <- file.path(base_dir, "outputs", "v2")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)


## 1. load ---------------------------------------------------------------------
demo <- read_xpt(file.path(data_dir, "DEMO_H.xpt"))
rxq  <- read_xpt(file.path(data_dir, "RXQ_RX_H.xpt"))
cfq  <- read_xpt(file.path(data_dir, "CFQ_H.xpt"))
acb  <- read.csv(file.path(data_dir, "aas_combined.csv"), stringsAsFactors = FALSE)
iacb <- read.csv(file.path(data_dir, "iacb_scores.csv"), stringsAsFactors = FALSE)

norm_name <- function(x) tolower(trimws(as.character(x)))

boustani_lookup <- acb %>%
  transmute(drug_key = norm_name(drug),
            boustani = suppressWarnings(as.numeric(boustani))) %>%
  mutate(boustani = ifelse(is.na(boustani), 0, boustani)) %>%
  filter(drug_key != "") %>% distinct(drug_key, .keep_all = TRUE)

iacb_lookup <- iacb %>%
  transmute(drug_key = norm_name(drug),
            iacb = suppressWarnings(as.numeric(iacb_score))) %>%
  filter(drug_key != "", !is.na(iacb)) %>% distinct(drug_key, .keep_all = TRUE)

cat(sprintf("reference lists: Boustani %d drugs, IACB %d drugs\n",
            nrow(boustani_lookup), nrow(iacb_lookup)))


## 2. score every prescription under both scales -------------------------------
# NOTE: a drug absent from a scale's list scores 0 on that scale (its list only
# enumerates drugs it considers anticholinergic). "matched" is tracked separately so
# we can report coverage honestly rather than conflating "not anticholinergic" with
# "not found".
rx <- rxq %>%
  filter(!is.na(RXDDRUG), RXDDRUG != "") %>%
  mutate(drug_key = norm_name(RXDDRUG)) %>%
  left_join(boustani_lookup, by = "drug_key") %>%
  left_join(iacb_lookup,     by = "drug_key") %>%
  mutate(matched_boustani = !is.na(boustani),
         matched_iacb     = !is.na(iacb),
         boustani = ifelse(is.na(boustani), 0, boustani),
         iacb     = ifelse(is.na(iacb), 0, iacb))

exposure <- rx %>%
  group_by(SEQN) %>%
  summarise(
    n_drugs        = n(),
    acb_burden     = sum(boustani),          # Boustani total (0-3 per drug)
    iacb_burden    = sum(iacb),              # IACB total    (0-4 per drug)
    n_highpot_acb  = sum(boustani == 3),     # top score of each scale
    n_highpot_iacb = sum(iacb == 4),
    .groups = "drop")


## 3. analysis frame + survey design (identical to 05_main_analysis.R) ----------
analysis <- demo %>%
  left_join(cfq %>% select(SEQN, CFDDS, CFDAST), by = "SEQN") %>%
  left_join(exposure, by = "SEQN") %>%
  mutate(across(c(n_drugs, acb_burden, iacb_burden, n_highpot_acb, n_highpot_iacb),
                ~ ifelse(is.na(.x), 0, .x)),
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
    # SAME cut-points for both scales so the categories are directly comparable.
    # IACB's 0-4 range makes its categories effectively stricter - noted in the text.
    acb_cat  = cut(acb_burden,  breaks = c(-Inf, 0, 2, Inf),
                   labels = c("ACB 0", "ACB 1-2", "ACB 3+"), right = TRUE),
    iacb_cat = cut(iacb_burden, breaks = c(-Inf, 0, 2, Inf),
                   labels = c("IACB 0", "IACB 1-2", "IACB 3+"), right = TRUE),
    age60 = age >= 60,
    has_dsst = !is.na(CFDDS))   # must exist before svydesign() for the IPW step

# comorbidities, if the optional files are present (same logic as the main script)
yn <- function(x) ifelse(x == 1, 1L, ifelse(x == 2, 0L, NA_integer_))
como <- tibble(SEQN = demo$SEQN)
if (file.exists(file.path(data_dir, "MCQ_H.xpt"))) {
  mcq <- read_xpt(file.path(data_dir, "MCQ_H.xpt"))
  como <- left_join(como, mcq %>% transmute(SEQN, stroke = yn(MCQ160F),
    cvd = pmax(yn(MCQ160B), yn(MCQ160C), yn(MCQ160D), yn(MCQ160E), na.rm = TRUE)), by = "SEQN")
}
if (file.exists(file.path(data_dir, "DIQ_H.xpt"))) {
  diq <- read_xpt(file.path(data_dir, "DIQ_H.xpt"))
  como <- left_join(como, diq %>% transmute(SEQN, diabetes = yn(DIQ010)), by = "SEQN")
}
if (file.exists(file.path(data_dir, "DPQ_H.xpt"))) {
  dpq <- read_xpt(file.path(data_dir, "DPQ_H.xpt"))
  items <- paste0("DPQ0", c("10","20","30","40","50","60","70","80","90"))
  dd <- dpq %>% select(SEQN, any_of(items))
  dd[items] <- lapply(dd[items], function(x) ifelse(x %in% c(7, 9), NA, x))
  dd$depression <- ifelse(rowSums(dd[items], na.rm = TRUE) >= 10, 1L, 0L)
  como <- left_join(como, dd %>% select(SEQN, depression), by = "SEQN")
}
if (file.exists(file.path(data_dir, "HSQ_H.xpt"))) {
  hsq <- read_xpt(file.path(data_dir, "HSQ_H.xpt"))
  como <- left_join(como, hsq %>% transmute(SEQN,
    srh_fairpoor = ifelse(HSD010 %in% c(4,5), 1L, ifelse(HSD010 %in% c(1,2,3), 0L, NA_integer_))),
    by = "SEQN")
}
analysis <- left_join(analysis, como, by = "SEQN")
health_vars <- intersect(c("stroke","cvd","diabetes","depression","srh_fairpoor"), names(analysis))
health_available <- health_vars[vapply(health_vars,
                      function(v) any(!is.na(analysis[[v]])), logical(1))]

design_full <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC2YR,
                         nest = TRUE, data = analysis)
design_60 <- subset(design_full, age60 & WTMEC2YR > 0)


## 4. drug-level + person-level concordance (for Dr Sami) ----------------------
# restrict to drugs actually taken by the 60+ cognitive sample
ids60 <- demo %>% filter(RIDAGEYR >= 60) %>% pull(SEQN)
ids60 <- intersect(ids60, cfq$SEQN)
rx60  <- rx %>% filter(SEQN %in% ids60)

drug_tab <- rx60 %>%
  group_by(drug_key) %>%
  summarise(n_users = n_distinct(SEQN),
            boustani_score = first(boustani), iacb_score = first(iacb),
            on_boustani_list = first(matched_boustani),
            on_iacb_list = first(matched_iacb), .groups = "drop") %>%
  mutate(match_status = case_when(
    on_boustani_list &  on_iacb_list ~ "both lists",
    on_boustani_list & !on_iacb_list ~ "Boustani only",
   !on_boustani_list &  on_iacb_list ~ "IACB only",
    TRUE                             ~ "neither list")) %>%
  arrange(desc(n_users))
write.csv(drug_tab, file.path(out_dir, "drug_level_scale_comparison.csv"), row.names = FALSE)

cat("\n=== DRUG-LEVEL COVERAGE (60+ cognitive sample) ===\n")
print(drug_tab %>% count(match_status, name = "n_distinct_drugs"))
cat("distinct drug names in sample:", n_distinct(rx60$drug_key), "\n")

unmatched_iacb <- drug_tab %>% filter(!on_iacb_list) %>%
  select(drug_key, n_users, boustani_score, on_boustani_list) %>% arrange(desc(n_users))
write.csv(unmatched_iacb, file.path(out_dir, "unmatched_drugs_iacb.csv"), row.names = FALSE)
cat("\ndrugs NOT on the IACB list:", nrow(unmatched_iacb),
    "(top 10 by users)\n"); print(head(unmatched_iacb, 10))

# agreement among drugs on BOTH lists
both <- drug_tab %>% filter(on_boustani_list, on_iacb_list)
exact <- sum(both$boustani_score == both$iacb_score)
rho_drug <- if (nrow(both) > 2) cor(both$boustani_score, both$iacb_score, method = "spearman") else NA
cat(sprintf("\ndrugs on both lists: %d | exact score agreement: %d (%.1f%%) | Spearman rho=%.3f\n",
            nrow(both), exact, 100*exact/nrow(both), rho_drug))

p60 <- analysis %>% filter(age60, SEQN %in% ids60)
rho_person <- cor(p60$acb_burden, p60$iacb_burden, method = "spearman")
cat(sprintf("person-level burden correlation (n=%d): Spearman rho=%.3f\n",
            nrow(p60), rho_person))
cat(sprintf("mean burden: Boustani %.2f (range %d-%d) | IACB %.2f (range %d-%d)\n",
            mean(p60$acb_burden), min(p60$acb_burden), max(p60$acb_burden),
            mean(p60$iacb_burden), min(p60$iacb_burden), max(p60$iacb_burden)))

write.csv(data.frame(
  drugs_on_both_lists = nrow(both), exact_agreement_n = exact,
  exact_agreement_pct = round(100*exact/nrow(both), 1),
  drug_level_spearman = round(rho_drug, 3),
  person_level_n = nrow(p60), person_level_spearman = round(rho_person, 3),
  mean_boustani = round(mean(p60$acb_burden), 3), max_boustani = max(p60$acb_burden),
  mean_iacb = round(mean(p60$iacb_burden), 3), max_iacb = max(p60$iacb_burden),
  n_distinct_drugs_sample = n_distinct(rx60$drug_key),
  n_unmatched_iacb = nrow(unmatched_iacb)),
  file.path(out_dir, "scale_concordance_summary.csv"), row.names = FALSE)

cat("\nIACB category counts (60+):\n"); print(table(p60$iacb_cat, useNA = "ifany"))
cat("Boustani category counts (60+):\n"); print(table(p60$acb_cat, useNA = "ifany"))


## 5. model machinery (identical to 05_main_analysis.R) ------------------------
tidy_term <- function(fit, term, model_name, outcome, scale_lab, n_used, dfree) {
  co  <- summary(fit)$coefficients
  est <- co[, "Estimate"]; se <- co[, "Std. Error"]
  tcrit <- qt(0.975, dfree)
  hits <- grep(paste0("^", gsub("([][().])", "\\\\\\1", term)), rownames(co), value = TRUE)
  if (length(hits) == 0) return(NULL)
  do.call(rbind, lapply(hits, function(rn) {
    data.frame(scale = scale_lab, model = model_name, outcome = outcome, term = rn,
               estimate = unname(est[rn]),
               ci_lower = unname(est[rn] - tcrit * se[rn]),
               ci_upper = unname(est[rn] + tcrit * se[rn]),
               p_value  = unname(2 * pt(-abs(est[rn] / se[rn]), df = dfree)),
               n_used = n_used, row.names = NULL)
  }))
}

fit_model <- function(outcome, rhs, vars, model_name, focal_terms, scale_lab) {
  needed  <- unique(c(outcome, vars))
  cc_flag <- complete.cases(design_60$variables[, needed, drop = FALSE])
  des <- design_60; des$variables$.cc <- cc_flag
  des_m <- subset(des, .cc)
  fit <- svyglm(as.formula(paste(outcome, "~", rhs)), design = des_m)
  bind_rows(lapply(focal_terms, tidy_term, fit = fit, model_name = model_name,
                   outcome = outcome, scale_lab = scale_lab,
                   n_used = sum(cc_flag), dfree = degf(des_m)))
}

base_cov <- "age + sex + race + education + income_pir"

# run the identical model sequence for one scale
run_scale <- function(outcome, burden, cat_var, highpot, scale_lab) {
  out <- list(
    fit_model(outcome, "n_drugs", "n_drugs", "M1: count alone", "n_drugs", scale_lab),
    fit_model(outcome, burden, burden, "M2: burden alone", burden, scale_lab),
    fit_model(outcome, paste(burden, "+ n_drugs"), c(burden, "n_drugs"),
              "M3: burden + count", c(burden, "n_drugs"), scale_lab),
    fit_model(outcome, paste(burden, "+ n_drugs +", base_cov),
              c(burden, "n_drugs", "age", "sex", "race", "education", "income_pir"),
              "M4: fully adjusted", c(burden, "n_drugs"), scale_lab),
    fit_model(outcome, paste(cat_var, "+ n_drugs +", base_cov),
              c(cat_var, "n_drugs", "age", "sex", "race", "education", "income_pir"),
              "M5a: burden category", cat_var, scale_lab),
    fit_model(outcome, paste(highpot, "+ n_drugs +", base_cov),
              c(highpot, "n_drugs", "age", "sex", "race", "education", "income_pir"),
              "M5b: high-potency", highpot, scale_lab))
  if (length(health_available) > 0) {
    out[[length(out)+1]] <- fit_model(outcome,
      paste(burden, "+ n_drugs +", base_cov, "+", paste(health_available, collapse = " + ")),
      c(burden, "n_drugs", "age", "sex", "race", "education", "income_pir", health_available),
      "M4+: + comorbidities", c(burden, "n_drugs"), scale_lab)
  }
  bind_rows(out)
}

results <- bind_rows(
  run_scale("CFDDS",  "acb_burden",  "acb_cat",  "n_highpot_acb",  "Boustani ACB (0-3)"),
  run_scale("CFDDS",  "iacb_burden", "iacb_cat", "n_highpot_iacb", "IACB (0-4)"),
  run_scale("CFDAST", "acb_burden",  "acb_cat",  "n_highpot_acb",  "Boustani ACB (0-3)"),
  run_scale("CFDAST", "iacb_burden", "iacb_cat", "n_highpot_iacb", "IACB (0-4)"))

write.csv(results, file.path(out_dir, "models_scale_comparison.csv"), row.names = FALSE)
cat("\n=== MODEL SEQUENCE, BOTH SCALES, BOTH OUTCOMES ===\n")
print(as.data.frame(results %>% mutate(across(where(is.numeric), ~round(.x, 4)))))


## 6. IPW sensitivity for both scales (primary outcome) ------------------------
ipw_df <- design_60$variables
need <- c("age","sex","race","education","income_pir","acb_burden","iacb_burden","n_drugs")
cc_resp <- complete.cases(ipw_df[, need])
resp_mod <- glm(has_dsst ~ age + sex + race + education + income_pir + acb_burden + n_drugs,
                data = ipw_df[cc_resp, ], family = binomial())
phat <- rep(NA_real_, nrow(ipw_df)); phat[cc_resp] <- predict(resp_mod, type = "response")
ipw_df$ipw_w <- ipw_df$WTMEC2YR * (1/phat)
resp <- ipw_df[ipw_df$has_dsst & cc_resp & is.finite(ipw_df$ipw_w), ]
ipw_design <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~ipw_w,
                        nest = TRUE, data = resp)
ipw_res <- bind_rows(
  tidy_term(svyglm(as.formula(paste("CFDDS ~ acb_burden + n_drugs +", base_cov)), design = ipw_design),
            "acb_burden", "M4-IPW", "CFDDS", "Boustani ACB (0-3)", nrow(resp), degf(ipw_design)),
  tidy_term(svyglm(as.formula(paste("CFDDS ~ iacb_burden + n_drugs +", base_cov)), design = ipw_design),
            "iacb_burden", "M4-IPW", "CFDDS", "IACB (0-4)", nrow(resp), degf(ipw_design)))
write.csv(ipw_res, file.path(out_dir, "models_ipw_scale_comparison.csv"), row.names = FALSE)
cat("\n=== IPW (primary outcome, both scales) ===\n")
print(as.data.frame(ipw_res %>% mutate(across(where(is.numeric), ~round(.x, 4)))))

cat("\ndone. outputs in:", normalizePath(out_dir, mustWork = FALSE), "\n")
