# Corrected drug-to-scale crosswalk + the Boustani-vs-IACB comparison.
#
# This is the redo of 06_scale_sensitivity.R (now archived), which Dr Sami found was
# scoring any drug absent from a scale's list as 0 - so "not on the list" and "the list
# says zero" came out the same. The two lists don't cover the sample equally, so that
# quietly biased the comparison between them. He then set two scoring rules on 14 Aug;
# they're spelled out at section 2 where they actually bind.
#
# Now the canonical scoring for the whole writeup. Run AFTER 08_extract_iacb.py and
# BEFORE 05_main_analysis.R - 05 reads the crosswalk this writes. What comes out:
#   1. crosswalk_corrected.csv - every NHANES drug name, both scales' scores, how it
#      resolved, component counts, max component score.
#   2. coverage: prescriptions positively on each list, and partly-scored combinations.
#   3. the model sequence (M1-M5b, M4+, M4-IPW), both scales, both outcomes, plus a
#      like-for-like coding using only drugs both lists recognise.
#   4. the standardised head-to-head Dr Sami asked for - both burdens at 1 SD, M4 on
#      identical participants, with the change in fit (dAIC + Wald) when each is added.
#   5. the same standardised M4 split by medication count (0-4, 5-9, >=10).
#
# Design, covariates and design-df CIs are identical to 05_main_analysis.R.

library(haven); library(survey); library(dplyr); library(tidyr)
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

demo <- read_xpt(file.path(data_dir, "DEMO_H.xpt"))
rxq  <- read_xpt(file.path(data_dir, "RXQ_RX_H.xpt"))
cfq  <- read_xpt(file.path(data_dir, "CFQ_H.xpt"))
acb  <- read.csv(file.path(data_dir, "aas_combined.csv"), stringsAsFactors = FALSE)
iacb <- read.csv(file.path(data_dir, "iacb_scores.csv"), stringsAsFactors = FALSE)

norm <- function(x) tolower(trimws(as.character(x)))

## 1. reference lists ----------------------------------------------------------
b_lk <- acb %>% transmute(key = norm(drug), score = suppressWarnings(as.numeric(boustani))) %>%
  mutate(score = ifelse(is.na(score), 0, score)) %>%
  filter(key != "") %>% distinct(key, .keep_all = TRUE)
i_lk <- iacb %>% transmute(key = norm(drug), score = suppressWarnings(as.numeric(iacb_score))) %>%
  filter(key != "", !is.na(score)) %>% distinct(key, .keep_all = TRUE)

# Synonym map: list spelling -> NHANES spelling. Recognised brand/INN/salt variants only,
# verified against the names actually present in this sample. Uncertain = left unmatched.
synonyms <- tribble(
  ~list_name,          ~nhanes_name,        ~basis,
  "coumadin",          "warfarin",          "brand name for warfarin",
  "salbutamol",        "albuterol",         "INN vs USAN for the same drug",
  "thyroxin",          "levothyroxine",     "thyroxine = levothyroxine (T4)",
  "potassium",         "potassium chloride","potassium salt as dispensed in NHANES",
  "valproic",          "valproic acid",     "abbreviated in the source list",
  "divalproex",        "divalproex sodium", "salt named in NHANES",
  "lithium carbonate", "lithium",           "salt named in the source list"
)
apply_syn <- function(lk) {
  add <- synonyms %>% inner_join(lk, by = c("list_name" = "key")) %>%
    transmute(key = nhanes_name, score, via_synonym = TRUE)
  bind_rows(lk %>% mutate(via_synonym = FALSE), add) %>% distinct(key, .keep_all = TRUE)
}
b_lk <- apply_syn(b_lk); i_lk <- apply_syn(i_lk)

## 2. crosswalk ----------------------------------------------------------------
# Scoring rules (both set by the supervisor, 14 Aug):
#  (1) COMBINATIONS: keep the score of every component that IS identified. An
#      unidentified component contributes 0 rather than voiding the whole product,
#      and is counted in n_unresolved so it can be reported separately. The earlier
#      "NA if any component is missing" rule discarded real exposure - for example
#      "acetaminophen; oxycodone" lost oxycodone's score entirely.
#  (2) UNLISTED DRUGS: where the drug identity is clear, absence from a scale's final
#      anticholinergic list means no anticholinergic activity, so it contributes 0.
#      This is the scales' own convention. Scores are therefore never NA here; the
#      crosswalk records HOW each name resolved so coverage can still be reported.
score_name <- function(nm, lk) {
  parts <- trimws(strsplit(nm, ";", fixed = TRUE)[[1]])
  hit <- lk$score[match(parts, lk$key)]
  syn <- lk$via_synonym[match(parts, lk$key)]
  found <- !is.na(hit)
  list(n_parts = length(parts), n_found = sum(found),
       n_unresolved = sum(!found),
       any_syn = isTRUE(any(syn[found])),
       score = sum(hit[found]),                              # partial sum, never NA
       # the if() is not decoration - max() on an empty vector gives -Inf plus a warning,
       # which then poisons the high-potency counts downstream. took a while to spot.
       maxsc = if (!any(found)) 0 else max(hit[found]))
}
names_all <- sort(unique(norm(rxq$RXDDRUG[!is.na(rxq$RXDDRUG) & rxq$RXDDRUG != ""])))
cw <- lapply(names_all, function(nm) {
  b <- score_name(nm, b_lk); i <- score_name(nm, i_lk)
  data.frame(drug = nm, is_combination = b$n_parts > 1, n_components = b$n_parts,
             boustani_score = b$score, boustani_max = b$maxsc,
             iacb_score = i$score, iacb_max = i$maxsc,
             b_found = b$n_found, i_found = i$n_found,
             b_unresolved = b$n_unresolved, i_unresolved = i$n_unresolved,
             b_syn = b$any_syn, i_syn = i$any_syn, stringsAsFactors = FALSE)
}) %>% bind_rows()

# Status describes HOW the name resolved. It no longer controls the score: every name
# now carries a numeric score under rule (2). "unlisted" means the drug is identifiable
# but does not appear on that scale's anticholinergic list, so it scores 0 by convention.
classify <- function(found, unresolved, syn, is_comb, score) {
  case_when(
    is_comb & unresolved > 0 & found > 0 ~ "c. combination, partly on list",
    is_comb & found > 0                  ~ "c. combination, all components on list",
    is_comb                              ~ "d. combination, no component on list (scores 0)",
    found == 0                           ~ "d. unlisted, identifiable (scores 0)",
    score == 0                           ~ "a. confirmed score zero",
    syn                                  ~ "b. synonym match",
    TRUE                                 ~ "b. exact match")
}
cw <- cw %>% mutate(
  boustani_status = classify(b_found, b_unresolved, b_syn, is_combination, boustani_score),
  iacb_status     = classify(i_found, i_unresolved, i_syn, is_combination, iacb_score),
  # "on both" now means each scale positively recognised at least one component,
  # which is what makes a like-for-like comparison meaningful
  on_both = b_found > 0 & i_found > 0)
write.csv(cw %>% arrange(desc(is_combination), drug),
          file.path(out_dir, "crosswalk_corrected.csv"), row.names = FALSE)

## 3. match rates + drug-level table (60+ cognitive sample) --------------------
ids60 <- intersect(demo$SEQN[demo$RIDAGEYR >= 60], cfq$SEQN)
rx <- rxq %>% filter(!is.na(RXDDRUG), RXDDRUG != "") %>%
  mutate(drug = norm(RXDDRUG)) %>% left_join(cw, by = "drug")
rx60 <- rx %>% filter(SEQN %in% ids60)

drug_tab <- rx60 %>% group_by(drug) %>%
  summarise(n_users = n_distinct(SEQN), .groups = "drop") %>%
  left_join(cw, by = "drug") %>% arrange(desc(n_users))
write.csv(drug_tab, file.path(out_dir, "drug_level_corrected.csv"), row.names = FALSE)
# Combinations scored from only some of their components - highlighted separately per
# rule (1). Single-ingredient drugs merely absent from a list are excluded: under rule (2)
# those are identifiable drugs that legitimately score 0, not unresolved cases.
write.csv(drug_tab %>% filter(is_combination, (i_unresolved > 0 & i_found > 0) |
                                              (b_unresolved > 0 & b_found > 0)) %>%
            select(drug, n_users, n_components, b_found, b_unresolved, boustani_score,
                   i_found, i_unresolved, iacb_score, boustani_status, iacb_status),
          file.path(out_dir, "unresolved_components.csv"), row.names = FALSE)

cat("\n================ CROSSWALK, 60+ COGNITIVE SAMPLE ================\n")
cat(sprintf("distinct names %d | prescriptions %d | participants with prescriptions %d\n",
            n_distinct(rx60$drug), nrow(rx60), n_distinct(rx60$SEQN)))
for (sc in c("boustani", "iacb")) {
  cat("\n", toupper(sc), " by distinct name:\n", sep = "")
  print(drug_tab %>% count(.data[[paste0(sc, "_status")]], name = "names"))
  fnd <- rx60[[paste0(substr(sc,1,1), "_found")]]
  unr <- rx60[[paste0(substr(sc,1,1), "_unresolved")]]
  cat(sprintf("  prescriptions with the drug positively on the list: %d/%d (%.1f%%)\n",
              sum(fnd > 0), length(fnd), 100 * mean(fnd > 0)))
  # A single-ingredient drug that is simply not on the list is NOT "unresolved" - under
  # rule (2) it is an identifiable drug scoring 0. Only a COMBINATION with some component
  # off the list is worth flagging, per rule (1).
  partial <- rx60$is_combination & unr > 0 & fnd > 0
  cat(sprintf("  combination prescriptions scored from a subset of components: %d (%.1f%%)\n",
              sum(partial), 100 * mean(partial)))
}
pp <- rx60 %>% group_by(SEQN) %>%
  summarise(b = any(is_combination & b_unresolved > 0 & b_found > 0),
            i = any(is_combination & i_unresolved > 0 & i_found > 0), .groups = "drop")
cat(sprintf("\nparticipants with >=1 partly-scored combination: Boustani %d/%d (%.1f%%) | IACB %d/%d (%.1f%%)\n",
            sum(pp$b), nrow(pp), 100*mean(pp$b), sum(pp$i), nrow(pp), 100*mean(pp$i)))
both_single <- cw %>% filter(!is_combination, b_found > 0, i_found > 0,
                             drug %in% drug_tab$drug)
agree <- sum(both_single$boustani_score == both_single$iacb_score)
cat(sprintf("single-ingredient drugs in sample scored by both: %d | exact agreement %d (%.1f%%) | rho=%.2f\n",
            nrow(both_single), agree, 100*agree/nrow(both_single),
            cor(both_single$boustani_score, both_single$iacb_score, method = "spearman")))
# added this after the raw agreement figure looked far worse than the scales deserve:
# the ranges differ (0-3 vs 0-4), so a drug both call maximally anticholinergic scores
# 3 on one and 4 on the other and counts as a disagreement. worth reporting both ways.
top_both <- sum(both_single$boustani_score == 3 & both_single$iacb_score == 4)
cat(sprintf("top-of-scale (Boustani 3 & IACB 4): %d | agreement counting those: %d/%d (%.1f%%)\n",
            top_both, agree + top_both, nrow(both_single), 100*(agree+top_both)/nrow(both_single)))

## 4. person-level exposures ----------------------------------------------------
# Primary exposure under rules (1) and (2): sum of every identified component's score,
# with unlisted drugs and unidentified components contributing 0.
expo <- rx %>% group_by(SEQN) %>% summarise(
  n_drugs        = n(),
  acb_burden     = sum(boustani_score),
  iacb_burden    = sum(iacb_score),
  n_highpot_acb  = sum(boustani_max == 3),
  n_highpot_iacb = sum(iacb_max == 4),
  # how many of this person's prescriptions had an unidentified component
  n_unresolved_b = sum(b_unresolved > 0),
  n_unresolved_i = sum(i_unresolved > 0),
  # like-for-like: only drugs BOTH scales positively recognise
  acb_common     = sum(ifelse(on_both, boustani_score, 0)),
  iacb_common    = sum(ifelse(on_both, iacb_score, 0)),
  .groups = "drop")

## comorbidities (same optional files as 05) ------------------------------------
yn <- function(x) ifelse(x == 1, 1L, ifelse(x == 2, 0L, NA_integer_))
como <- tibble(SEQN = demo$SEQN)
if (file.exists(file.path(data_dir, "MCQ_H.xpt"))) {
  mcq <- read_xpt(file.path(data_dir, "MCQ_H.xpt"))
  como <- left_join(como, mcq %>% transmute(SEQN, stroke = yn(MCQ160F),
    cvd = pmax(yn(MCQ160B), yn(MCQ160C), yn(MCQ160D), yn(MCQ160E), na.rm = TRUE)), by = "SEQN")
}
if (file.exists(file.path(data_dir, "DIQ_H.xpt"))) {
  como <- left_join(como, read_xpt(file.path(data_dir, "DIQ_H.xpt")) %>%
                      transmute(SEQN, diabetes = yn(DIQ010)), by = "SEQN")
}
if (file.exists(file.path(data_dir, "DPQ_H.xpt"))) {
  dpq <- read_xpt(file.path(data_dir, "DPQ_H.xpt"))
  items <- paste0("DPQ0", c("10","20","30","40","50","60","70","80","90"))
  dd <- dpq %>% select(SEQN, any_of(items))
  dd[items] <- lapply(dd[items], function(x) ifelse(x %in% c(7, 9), NA, x))
  # Same PHQ-9 rule as 05_main_analysis.R - see the long comment there. Short version:
  # na.rm = TRUE scored an unanswered item as "not at all", so 527 people who answered
  # none of the nine were all being called not-depressed. Items only add, so decide the
  # two cases that arithmetic settles and leave the rest NA.
  partial <- rowSums(dd[items], na.rm = TRUE)
  n_miss  <- length(items) - rowSums(!is.na(dd[items]))
  dd$depression <- ifelse(partial >= 10, 1L,
                   ifelse(partial + 3 * n_miss < 10, 0L, NA_integer_))
  como <- left_join(como, dd %>% select(SEQN, depression), by = "SEQN")
}
if (file.exists(file.path(data_dir, "HSQ_H.xpt"))) {
  como <- left_join(como, read_xpt(file.path(data_dir, "HSQ_H.xpt")) %>%
    transmute(SEQN, srh_fairpoor = ifelse(HSD010 %in% c(4,5), 1L,
                                   ifelse(HSD010 %in% c(1,2,3), 0L, NA_integer_))), by = "SEQN")
}
health_vars <- intersect(c("stroke","cvd","diabetes","depression","srh_fairpoor"), names(como))
health_available <- health_vars[vapply(health_vars,
                      function(v) any(!is.na(como[[v]])), logical(1))]

analysis <- demo %>%
  left_join(cfq %>% select(SEQN, CFDDS, CFDAST), by = "SEQN") %>%
  left_join(expo, by = "SEQN") %>% left_join(como, by = "SEQN") %>%
  mutate(across(c(n_drugs, acb_burden, iacb_burden, n_highpot_acb, n_highpot_iacb,
                  acb_common, iacb_common, n_unresolved_b, n_unresolved_i),
                ~ ifelse(is.na(.x), 0, .x)),
    age = as.numeric(RIDAGEYR),
    sex = factor(RIAGENDR, levels = c(1,2), labels = c("Male","Female")),
    educ_code = ifelse(DMDEDUC2 %in% c(7,9), NA, DMDEDUC2),
    education = factor(educ_code, levels = 1:5,
      labels = c("<9th grade","9-11th grade","HS grad/GED","Some college/AA","College grad+")),
    race = factor(RIDRETH3, levels = c(3,1,2,4,6,7),
      labels = c("NH White","Mexican American","Other Hispanic","NH Black","NH Asian","Other/Multi")),
    income_pir = as.numeric(INDFMPIR),
    acb_cat  = cut(acb_burden,  breaks = c(-Inf,0,2,Inf),
                   labels = c("ACB 0","ACB 1-2","ACB 3+"), right = TRUE),
    iacb_cat = cut(iacb_burden, breaks = c(-Inf,0,2,Inf),
                   labels = c("IACB 0","IACB 1-2","IACB 3+"), right = TRUE),
    # medication-complexity strata (supervisor request, 14 Aug)
    med_band = cut(n_drugs, breaks = c(-Inf, 4, 9, Inf),
                   labels = c("0-4 medicines", "5-9 medicines", ">=10 medicines")),
    age60 = age >= 60, has_dsst = !is.na(CFDDS))

## ---- COMMON ANALYTIC SAMPLE -------------------------------------------------
# Both scales must be compared on IDENTICAL participants (supervisor request). The
# analytic set is the complete cases for the fully adjusted model; because both burdens
# are defined for everyone, this set is the same for either scale, but we build it once
# and reuse it so that is guaranteed rather than assumed.
MODEL_VARS <- c("CFDDS", "n_drugs", "age", "sex", "race", "education", "income_pir")
analysis$in_sample <- complete.cases(analysis[, MODEL_VARS]) &
                      analysis$age60 & !is.na(analysis$WTMEC2YR) & analysis$WTMEC2YR > 0

# Standardise each burden to 1 SD so the two scales are directly comparable - otherwise
# you can't read anything into 0-3 vs 0-4 coefficients side by side.
# SD is taken WITHIN in_sample, not the whole 60+ set, or the scaling wouldn't match the
# people actually in the models. Dividing rather than using scale() on purpose: it leaves
# the mean alone, so the intercept and every other coefficient stay on their usual scale.
sd_acb  <- sd(analysis$acb_burden[analysis$in_sample])
sd_iacb <- sd(analysis$iacb_burden[analysis$in_sample])
analysis <- analysis %>% mutate(acb_z = acb_burden / sd_acb, iacb_z = iacb_burden / sd_iacb)

design_full <- svydesign(ids=~SDMVPSU, strata=~SDMVSTRA, weights=~WTMEC2YR,
                         nest=TRUE, data=analysis)
des60 <- subset(design_full, age60 & WTMEC2YR > 0)
des_cs <- subset(design_full, in_sample)          # the common analytic sample

cat("\n================ COMMON ANALYTIC SAMPLE ================\n")
cat(sprintf("n = %d (identical for both scales)\n", sum(analysis$in_sample)))
cat(sprintf("burden SD used for standardisation: Boustani %.3f | IACB %.3f\n", sd_acb, sd_iacb))
cat(sprintf("mean burden: Boustani %.2f (max %g) | IACB %.2f (max %g)\n",
            mean(analysis$acb_burden[analysis$in_sample]), max(analysis$acb_burden[analysis$in_sample]),
            mean(analysis$iacb_burden[analysis$in_sample]), max(analysis$iacb_burden[analysis$in_sample])))
cat("\nmedication bands (common sample):\n")
print(table(analysis$med_band[analysis$in_sample]))

## 5. model machinery ------------------------------------------------------------
tidy_term <- function(fit, term, model, outcome, scale_lab, coding, n, dfree) {
  co <- summary(fit)$coefficients
  hits <- grep(paste0("^", gsub("([][().])", "\\\\\\1", term)), rownames(co), value = TRUE)
  if (length(hits) == 0) return(NULL)
  tcrit <- qt(0.975, dfree)
  do.call(rbind, lapply(hits, function(rn) {
    e <- co[rn,"Estimate"]; s <- co[rn,"Std. Error"]
    data.frame(coding = coding, scale = scale_lab, model = model, outcome = outcome,
               term = rn, estimate = e, ci_lower = e - tcrit*s, ci_upper = e + tcrit*s,
               p_value = 2*pt(-abs(e/s), df = dfree), n_used = n, row.names = NULL)
  }))
}
fit_model <- function(outcome, rhs, vars, model, focal, scale_lab, coding, des = des60) {
  cc <- complete.cases(des$variables[, unique(c(outcome, vars)), drop = FALSE])
  d <- des; d$variables$.cc <- cc; dm <- subset(d, .cc)
  fit <- svyglm(as.formula(paste(outcome, "~", rhs)), design = dm)
  bind_rows(lapply(focal, tidy_term, fit = fit, model = model, outcome = outcome,
                   scale_lab = scale_lab, coding = coding, n = sum(cc), dfree = degf(dm)))
}
base_cov <- "age + sex + race + education + income_pir"

# cat_var = NULL skips the categorical model. Used for IACB: the 0 / 1-2 / 3+ cut-points
# are Boustani's, and Dr Sami's point is they don't transfer to a 0-4 scale, so running
# them on IACB was comparing categories that don't mean the same thing.
run_full <- function(outcome, burden, cat_var, highpot, scale_lab, coding) {
  out <- list(
    fit_model(outcome, "n_drugs", "n_drugs", "M1: count alone", "n_drugs", scale_lab, coding),
    fit_model(outcome, burden, burden, "M2: burden alone", burden, scale_lab, coding),
    fit_model(outcome, paste(burden, "+ n_drugs"), c(burden, "n_drugs"),
              "M3: burden + count", c(burden, "n_drugs"), scale_lab, coding),
    fit_model(outcome, paste(burden, "+ n_drugs +", base_cov),
              c(burden, "n_drugs", "age","sex","race","education","income_pir"),
              "M4: fully adjusted", c(burden, "n_drugs"), scale_lab, coding),
    if (!is.null(cat_var))
      fit_model(outcome, paste(cat_var, "+ n_drugs +", base_cov),
                c(cat_var, "n_drugs", "age","sex","race","education","income_pir"),
                "M5a: burden category", cat_var, scale_lab, coding),
    fit_model(outcome, paste(highpot, "+ n_drugs +", base_cov),
              c(highpot, "n_drugs", "age","sex","race","education","income_pir"),
              "M5b: high-potency", highpot, scale_lab, coding))
  if (length(health_available) > 0) {
    out[[length(out)+1]] <- fit_model(outcome,
      paste(burden, "+ n_drugs +", base_cov, "+", paste(health_available, collapse=" + ")),
      c(burden, "n_drugs", "age","sex","race","education","income_pir", health_available),
      "M4+: + comorbidities", c(burden, "n_drugs"), scale_lab, coding)
  }
  bind_rows(out)
}

CA <- "(a) primary: unlisted contributes 0"
full <- bind_rows(
  run_full("CFDDS",  "acb_burden",  "acb_cat", "n_highpot_acb",  "Boustani ACB (0-3)", CA),
  run_full("CFDDS",  "iacb_burden", NULL,      "n_highpot_iacb", "IACB (0-4)",         CA),
  run_full("CFDAST", "acb_burden",  "acb_cat", "n_highpot_acb",  "Boustani ACB (0-3)", CA),
  run_full("CFDAST", "iacb_burden", NULL,      "n_highpot_iacb", "IACB (0-4)",         CA))

## IPW (DSST, both scales) --------------------------------------------------------
ipw_df <- des60$variables
need <- c("age","sex","race","education","income_pir","acb_burden","n_drugs")
cc_resp <- complete.cases(ipw_df[, need])
resp_mod <- glm(has_dsst ~ age + sex + race + education + income_pir + acb_burden + n_drugs,
                data = ipw_df[cc_resp, ], family = binomial())
phat <- rep(NA_real_, nrow(ipw_df)); phat[cc_resp] <- predict(resp_mod, type = "response")
ipw_df$ipw_w <- ipw_df$WTMEC2YR * (1/phat)
resp <- ipw_df[ipw_df$has_dsst & cc_resp & is.finite(ipw_df$ipw_w), ]
ipw_design <- svydesign(ids=~SDMVPSU, strata=~SDMVSTRA, weights=~ipw_w, nest=TRUE, data=resp)
full <- bind_rows(full,
  tidy_term(svyglm(as.formula(paste("CFDDS ~ acb_burden + n_drugs +", base_cov)), design = ipw_design),
            "acb_burden", "M4-IPW", "CFDDS", "Boustani ACB (0-3)", CA, nrow(resp), degf(ipw_design)),
  tidy_term(svyglm(as.formula(paste("CFDDS ~ iacb_burden + n_drugs +", base_cov)), design = ipw_design),
            "iacb_burden", "M4-IPW", "CFDDS", "IACB (0-4)", CA, nrow(resp), degf(ipw_design)))

## like-for-like: only drugs BOTH scales positively recognise -----------------------
run_restricted <- function(burden, scale_lab, coding) {
  bind_rows(
    fit_model("CFDDS", paste(burden, "+ n_drugs"), c(burden, "n_drugs"),
              "M3: burden + count", c(burden, "n_drugs"), scale_lab, coding),
    fit_model("CFDDS", paste(burden, "+ n_drugs +", base_cov),
              c(burden, "n_drugs","age","sex","race","education","income_pir"),
              "M4: fully adjusted", c(burden, "n_drugs"), scale_lab, coding))
}
full <- bind_rows(full,
  run_restricted("acb_common",  "Boustani ACB (0-3)", "(b) drugs on both lists only"),
  run_restricted("iacb_common", "IACB (0-4)",         "(b) drugs on both lists only"))

write.csv(full, file.path(out_dir, "models_corrected_crosswalk.csv"), row.names = FALSE)
cat("\n================ MODEL SEQUENCE ================\n")
print(as.data.frame(full %>% mutate(across(where(is.numeric), ~round(.x, 4)))), max = 3000)

## ================================================================================
## 6. STANDARDISED HEAD-TO-HEAD + CHANGE IN MODEL FIT  (supervisor request 3)
## ================================================================================
# Same participants, both burdens on a 1 SD scale, M4 covariates. Model fit is compared
# against a base model containing medication count and the demographics but no burden,
# using AIC (design-corrected) and a design-based Wald test for the added term.
cat("\n================ STANDARDISED M4, COMMON SAMPLE ================\n")

f_base <- as.formula(paste("CFDDS ~ n_drugs +", base_cov))
m_base <- svyglm(f_base, design = des_cs)
dfree  <- degf(des_cs)

std_row <- function(zvar, label) {
  m <- svyglm(as.formula(paste("CFDDS ~", zvar, "+ n_drugs +", base_cov)), design = des_cs)
  co <- summary(m)$coefficients
  e <- co[zvar,"Estimate"]; s <- co[zvar,"Std. Error"]; t <- qt(0.975, dfree)
  wald <- regTermTest(m, zvar, df = dfree)          # design-based test of the added term
  data.frame(scale = label, term = "burden (per 1 SD)",
             estimate = e, ci_lower = e - t*s, ci_upper = e + t*s,
             p_value = 2*pt(-abs(e/s), df = dfree),
             count_estimate = co["n_drugs","Estimate"],
             count_p = 2*pt(-abs(co["n_drugs","Estimate"]/co["n_drugs","Std. Error"]), df = dfree),
             AIC = AIC(m)[["AIC"]], dAIC = AIC(m)[["AIC"]] - AIC(m_base)[["AIC"]],
             wald_F = as.numeric(wald$Ftest), wald_p = as.numeric(wald$p),
             n_used = nrow(des_cs$variables), row.names = NULL)
}
std <- bind_rows(std_row("acb_z", "Boustani ACB"), std_row("iacb_z", "IACB"))
std$base_AIC <- AIC(m_base)[["AIC"]]
std$base_count_estimate <- summary(m_base)$coefficients["n_drugs","Estimate"]
write.csv(std, file.path(out_dir, "standardised_m4_comparison.csv"), row.names = FALSE)
print(as.data.frame(std %>% mutate(across(where(is.numeric), ~round(.x, 4)))))
cat(sprintf("\nbase model (count + demographics, no burden): AIC %.1f, count %.3f\n",
            AIC(m_base)[["AIC"]], summary(m_base)$coefficients["n_drugs","Estimate"]))
cat("negative dAIC = adding that burden score improves fit\n")

## ================================================================================
## 7. STRATIFIED BY MEDICATION COMPLEXITY  (supervisor request 4)
## ================================================================================
cat("\n================ STANDARDISED M4 BY MEDICATION BAND ================\n")
strat <- list()
for (band in levels(analysis$med_band)) {
  d <- subset(des_cs, med_band == band)
  n_band <- nrow(d$variables)
  # 30 is a judgement call, not a rule. NHANES only gives ~15 design df to start with and
  # a thin stratum eats that fast, so below this the CIs stop meaning much. The >=10 band
  # (n=103) is already the one to be careful about when writing this up.
  if (n_band < 30) { cat("  skipping", band, "- n =", n_band, "\n"); next }
  dfb <- degf(d)
  mb <- svyglm(f_base, design = d)
  for (zv in c("acb_z", "iacb_z")) {
    m <- svyglm(as.formula(paste("CFDDS ~", zv, "+ n_drugs +", base_cov)), design = d)
    co <- summary(m)$coefficients; t <- qt(0.975, dfb)
    e <- co[zv,"Estimate"]; s <- co[zv,"Std. Error"]
    strat[[length(strat)+1]] <- data.frame(
      band = band, n = n_band,
      scale = if (zv == "acb_z") "Boustani ACB" else "IACB",
      estimate = e, ci_lower = e - t*s, ci_upper = e + t*s,
      p_value = 2*pt(-abs(e/s), df = dfb),
      dAIC = AIC(m)[["AIC"]] - AIC(mb)[["AIC"]], row.names = NULL)
  }
}
strat <- bind_rows(strat)
write.csv(strat, file.path(out_dir, "standardised_m4_by_medband.csv"), row.names = FALSE)
print(as.data.frame(strat %>% mutate(across(where(is.numeric), ~round(.x, 4)))))

## ================================================================================
## 8. M4 vs M4+ ON THE SAME PARTICIPANTS  (supervisor request, 14 Aug)
## ================================================================================
# The earlier M4/M4+ contrast was not a fair one: M4 ran on 1468 people and M4+ on the
# 1355 with complete comorbidity data, so "medication count lost significance" could
# have been the 113 dropped participants rather than the comorbidities. Refit BOTH on
# the M4+ complete-case set so the only thing that changes is the covariates.
cat("\n================ M4 vs M4+ ON IDENTICAL PARTICIPANTS ================\n")

m4plus_vars <- c("CFDDS", "n_drugs", "age", "sex", "race", "education", "income_pir",
                 health_available)
analysis$in_m4plus <- complete.cases(analysis[, m4plus_vars]) &
                      analysis$age60 & !is.na(analysis$WTMEC2YR) & analysis$WTMEC2YR > 0
# has to go onto the design object too - subset() looks inside design_full$variables,
# not the analysis frame, so adding the column after svydesign() isn't enough
design_full$variables$in_m4plus <- analysis$in_m4plus
des_m4p <- subset(design_full, in_m4plus)
n_m4p   <- sum(analysis$in_m4plus)
df_m4p  <- degf(des_m4p)
cat(sprintf("common M4/M4+ sample: n = %d (was M4 n=%d vs M4+ n=%d)\n\n",
            n_m4p, sum(analysis$in_sample), n_m4p))

# restandardise within THIS sample so the 1 SD unit matches the people being modelled
sd_acb_p  <- sd(analysis$acb_burden[analysis$in_m4plus])
sd_iacb_p <- sd(analysis$iacb_burden[analysis$in_m4plus])
des_m4p$variables$acb_zp  <- des_m4p$variables$acb_burden  / sd_acb_p
des_m4p$variables$iacb_zp <- des_m4p$variables$iacb_burden / sd_iacb_p

pair_row <- function(zvar, label, with_como) {
  rhs <- paste(zvar, "+ n_drugs +", base_cov)
  if (with_como) rhs <- paste(rhs, "+", paste(health_available, collapse = " + "))
  m  <- svyglm(as.formula(paste("CFDDS ~", rhs)), design = des_m4p)
  co <- summary(m)$coefficients; t <- qt(0.975, df_m4p)
  gt <- function(v) {
    e <- co[v,"Estimate"]; s <- co[v,"Std. Error"]
    c(e, e - t*s, e + t*s, 2*pt(-abs(e/s), df = df_m4p))
  }
  b <- gt(zvar); d <- gt("n_drugs")
  data.frame(scale = label, model = if (with_como) "M4+ (with comorbidities)" else "M4 (same sample)",
             burden = b[1], burden_lo = b[2], burden_hi = b[3], burden_p = b[4],
             count = d[1], count_lo = d[2], count_hi = d[3], count_p = d[4],
             AIC = AIC(m)[["AIC"]], n = n_m4p, row.names = NULL)
}
m4pair <- bind_rows(
  pair_row("acb_zp",  "Boustani ACB", FALSE), pair_row("acb_zp",  "Boustani ACB", TRUE),
  pair_row("iacb_zp", "IACB",         FALSE), pair_row("iacb_zp", "IACB",         TRUE))
write.csv(m4pair, file.path(out_dir, "m4_vs_m4plus_same_sample.csv"), row.names = FALSE)
print(as.data.frame(m4pair %>% mutate(across(where(is.numeric), ~round(.x, 4)))))
cat("\nburden/count are per 1 SD and per medicine; both models use the same",
    n_m4p, "participants,\nso any difference between the rows is the comorbidities, not the sample.\n")

cat("\ncategory counts, Boustani only (60+):\n")
p60 <- analysis %>% filter(age60, SEQN %in% ids60)
print(table(p60$acb_cat))
cat("IACB categorical comparison dropped - the 0/1-2/3+ cut-points are Boustani's.\n")
cat("\ndone.\n")
