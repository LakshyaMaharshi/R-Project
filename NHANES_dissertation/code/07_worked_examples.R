# Concrete, verifiable facts for the write-up, computed from the CORRECTED crosswalk:
#   1. which anticholinergic drugs are actually taken in the 60+ cognitive sample
#   2. drug-matching diagnostics (crosswalk categories, resolution rates)
#   3. the observed burden distribution
#   4. the age coefficient from M4, for the "years of ageing" framing
# Run AFTER 11_corrected_crosswalk.R (needs crosswalk_corrected.csv).

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

demo <- read_xpt(file.path(data_dir, "DEMO_H.xpt"))
rxq  <- read_xpt(file.path(data_dir, "RXQ_RX_H.xpt"))
cfq  <- read_xpt(file.path(data_dir, "CFQ_H.xpt"))
cw   <- read.csv(file.path(out_dir, "crosswalk_corrected.csv"), stringsAsFactors = FALSE)

rx <- rxq %>% filter(!is.na(RXDDRUG), RXDDRUG != "") %>%
  mutate(drug = tolower(trimws(as.character(RXDDRUG)))) %>%
  left_join(cw %>% select(drug, boustani_score, boustani_max, boustani_status,
                          is_combination), by = "drug")
ids60 <- intersect(demo$SEQN[demo$RIDAGEYR >= 60], cfq$SEQN)
rx60  <- rx %>% filter(SEQN %in% ids60)

cat("\n===== 1. ANTICHOLINERGIC DRUGS ACTUALLY USED (60+ cognitive sample) =====\n")
cat("participants:", length(ids60), "| prescriptions:", nrow(rx60),
    "| distinct names:", n_distinct(rx60$drug), "\n\n")
top_ac <- rx60 %>% filter(coalesce(boustani_score, 0) > 0) %>%
  group_by(drug, boustani_score, is_combination) %>%
  summarise(n_users = n_distinct(SEQN), .groups = "drop") %>%
  mutate(pct_of_sample = round(100 * n_users / length(ids60), 1)) %>%
  arrange(desc(n_users))
cat("--- top 20 by users (Boustani, corrected crosswalk) ---\n")
print(as.data.frame(head(top_ac, 20)))
cat("\n--- all names containing a top-score (3) component ---\n")
hp <- rx60 %>% filter(coalesce(boustani_max, 0) == 3) %>%
  group_by(drug, boustani_score) %>%
  summarise(n_users = n_distinct(SEQN), .groups = "drop") %>%
  mutate(pct_of_sample = round(100 * n_users / length(ids60), 1)) %>%
  arrange(desc(n_users))
print(as.data.frame(hp))

write.csv(head(top_ac, 20), file.path(out_dir, "top_anticholinergic_drugs.csv"), row.names = FALSE)
write.csv(hp, file.path(out_dir, "highpotency_drugs_used.csv"), row.names = FALSE)

cat("\n===== 2. MATCHING DIAGNOSTICS (crosswalk categories) =====\n")
print(rx60 %>% distinct(drug, .keep_all = TRUE) %>% count(boustani_status, name = "names"))
cat(sprintf("prescriptions resolved: %d/%d (%.1f%%)\n",
            sum(!is.na(rx60$boustani_score)), nrow(rx60),
            100 * mean(!is.na(rx60$boustani_score))))
un <- rx60 %>% filter(is.na(boustani_score)) %>% count(drug, sort = TRUE)
cat("\n--- 10 most common unresolved names ---\n"); print(head(as.data.frame(un), 10))

cat("\n===== 3. BURDEN DISTRIBUTION (60+ cognitive sample) =====\n")
burden <- rx60 %>% group_by(SEQN) %>%
  summarise(b = sum(coalesce(boustani_score, 0)), .groups = "drop")
allb <- c(burden$b, rep(0, length(ids60) - nrow(burden)))   # no prescriptions = 0
cat("range:", min(allb), "to", max(allb), "\n"); print(table(allb))

cat("\n===== 4. AGE COEFFICIENT FROM M4 (age-equivalence framing) =====\n")
exposure <- rx %>% group_by(SEQN) %>%
  summarise(n_drugs = n(), acb_burden = sum(coalesce(boustani_score, 0)), .groups = "drop")
analysis <- demo %>%
  left_join(cfq %>% select(SEQN, CFDDS), by = "SEQN") %>%
  left_join(exposure, by = "SEQN") %>%
  mutate(n_drugs = ifelse(is.na(n_drugs), 0, n_drugs),
    acb_burden = ifelse(is.na(acb_burden), 0, acb_burden),
    age = as.numeric(RIDAGEYR),
    sex = factor(RIAGENDR, levels = c(1,2), labels = c("Male","Female")),
    educ_code = ifelse(DMDEDUC2 %in% c(7,9), NA, DMDEDUC2),
    education = factor(educ_code, levels = 1:5,
      labels = c("<9th grade","9-11th grade","HS grad/GED","Some college/AA","College grad+")),
    race = factor(RIDRETH3, levels = c(3,1,2,4,6,7),
      labels = c("NH White","Mexican American","Other Hispanic","NH Black","NH Asian","Other/Multi")),
    income_pir = as.numeric(INDFMPIR), age60 = age >= 60)
des <- subset(svydesign(ids=~SDMVPSU, strata=~SDMVSTRA, weights=~WTMEC2YR, nest=TRUE,
                        data=analysis), age60 & WTMEC2YR > 0)
vars <- c("CFDDS","acb_burden","n_drugs","age","sex","race","education","income_pir")
cc <- complete.cases(des$variables[, vars]); des$variables$.cc <- cc
fit <- svyglm(CFDDS ~ acb_burden + n_drugs + age + sex + race + education + income_pir,
              design = subset(des, .cc))
co <- summary(fit)$coefficients
print(round(co[c("acb_burden","n_drugs","age"), ], 4))
b <- co["acb_burden","Estimate"]; a <- co["age","Estimate"]
cat(sprintf("\n1 ACB unit ~ %.2f years of ageing | ACB 3+ coefficient / age = see 05 output\n", b/a))
cat("n used:", sum(cc), "\n")
