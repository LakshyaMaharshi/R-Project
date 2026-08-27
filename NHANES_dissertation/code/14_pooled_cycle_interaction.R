# Pooled 2011-2012 + 2013-2014 analysis with a cycle x burden interaction.
#
# Dr Sami, 21 Aug: "combine 2011-12 and 2013-14 and run the same adjusted model with a
# cycle x burden interaction, separately for Boustani and IACB. That is now the important
# test. We need to know if the apparent difference between cycles is real, rather than
# comparing significance in one cycle with non-significance in another."
#
# That last point is the whole reason for this script. Boustani burden was significant in
# 2013-14 and not in 2011-12, but "significant here, not significant there" is not evidence
# that the two differ - the difference between a significant and a non-significant result
# is not itself significant. The interaction term tests it directly.
#
#   Rscript 14_pooled_cycle_interaction.R
#
# Prerequisite: both cycles must have been run, because the pooled frame is rebuilt from
# each cycle's crosswalk and the script checks itself against the per-cycle estimates.
#
# Writes to outputs/comparison/.

library(haven); library(survey); library(dplyr)
options(survey.lonely.psu = "adjust")

.f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
here <- if (length(.f)) dirname(sub("^--file=", "", .f[1])) else "."
source(file.path(here, "config.R"))

CYCLE_LIST <- c("2013-2014", "2011-2012")   # first is the reference level
REF_CYCLE  <- CYCLE_LIST[1]
dir.create(cmp_dir, showWarnings = FALSE, recursive = TRUE)

## ---------------------------------------------------------------------------
## 1. rebuild the person-level frame for one cycle
## ---------------------------------------------------------------------------
# Same construction as 11_corrected_crosswalk.R, so the pooled model sees exactly the
# variables the per-cycle models saw. Section 5 checks that this held.
norm <- function(x) tolower(trimws(as.character(x)))

build_cycle <- function(cyc) {
  sfx  <- CYCLES[[cyc]]$suffix
  ddir <- file.path(base_dir, "data", cyc)
  tdir <- file.path(base_dir, "outputs", cyc, "tables")
  xp   <- function(stem) file.path(ddir, paste0(stem, sfx, ".xpt"))

  cwp <- file.path(tdir, "crosswalk_corrected.csv")
  if (!file.exists(cwp))
    stop("no crosswalk for ", cyc, " - run 11_corrected_crosswalk.R --cycle=", cyc)

  demo <- read_xpt(xp("DEMO")); rxq <- read_xpt(xp("RXQ_RX")); cfq <- read_xpt(xp("CFQ"))
  cw   <- read.csv(cwp, stringsAsFactors = FALSE)

  expo <- rxq %>% filter(!is.na(RXDDRUG), RXDDRUG != "") %>%
    mutate(drug = norm(RXDDRUG)) %>% left_join(cw, by = "drug") %>%
    group_by(SEQN) %>%
    summarise(n_drugs = n(),
              acb_burden = sum(boustani_score), iacb_burden = sum(iacb_score),
              .groups = "drop")

  demo %>%
    left_join(cfq %>% select(SEQN, CFDDS), by = "SEQN") %>%
    left_join(expo, by = "SEQN") %>%
    mutate(
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
      age60 = age >= 60,
      cycle = cyc) %>%
    select(SEQN, cycle, CFDDS, n_drugs, acb_burden, iacb_burden, med_band,
           age, sex, race, education, income_pir, WTMEC2YR, SDMVPSU, SDMVSTRA, age60)
}

pooled <- bind_rows(lapply(CYCLE_LIST, build_cycle))

## ---------------------------------------------------------------------------
## 2. pooled survey design
## ---------------------------------------------------------------------------
# Two things have to be right here or the standard errors are quietly wrong.
#
# WEIGHTS. Each cycle's WTMEC2YR is a 2-year weight. Pooling k cycles means dividing by k,
# per the NHANES analytic guidelines, otherwise the combined sample is weighted to roughly
# twice the US population and every SE is understated.
#
# STRATA. Design strata must not be shared between cycles. NHANES numbers them
# sequentially (2011-12 uses 90-103, 2013-14 uses 104-118) so they do not collide, but
# that is a property of the data rather than something to assume - if a future cycle reused
# a stratum number, two unrelated strata would silently merge. Checked, not trusted.
k <- length(CYCLE_LIST)
strata_by_cycle <- split(unique(pooled[, c("cycle", "SDMVSTRA")])$SDMVSTRA,
                         unique(pooled[, c("cycle", "SDMVSTRA")])$cycle)
overlap <- Reduce(intersect, strata_by_cycle)
cat("\n[design] strata per cycle:\n")
for (cy in names(strata_by_cycle))
  cat(sprintf("  %s: %d strata (%d-%d)\n", cy, length(strata_by_cycle[[cy]]),
              min(strata_by_cycle[[cy]]), max(strata_by_cycle[[cy]])))
if (length(overlap) > 0)
  stop("SDMVSTRA values are shared between cycles (", paste(overlap, collapse = ", "),
       ") - build a composite stratum before pooling, or the variance is wrong")
cat("  no shared stratum values, so SDMVSTRA can be used directly\n")

pooled <- pooled %>%
  mutate(weight = WTMEC2YR / k,
         cycle  = factor(cycle, levels = CYCLE_LIST))   # reference = the dissertation cycle
cat(sprintf("  weights divided by %d (pooling %d two-year cycles)\n", k, k))

MODEL_VARS <- c("CFDDS", "n_drugs", "age", "sex", "race", "education", "income_pir")
pooled$in_sample <- complete.cases(pooled[, MODEL_VARS]) &
                    pooled$age60 & !is.na(pooled$weight) & pooled$weight > 0

des_all <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~weight,
                     nest = TRUE, data = pooled)
des <- subset(des_all, in_sample)

cat(sprintf("\n[sample] pooled M4 sample n = %d (%s)\n", sum(pooled$in_sample),
            paste(sprintf("%s %d", CYCLE_LIST,
                          sapply(CYCLE_LIST, function(c) sum(pooled$in_sample & pooled$cycle == c))),
                  collapse = " + ")))
cat(sprintf("[sample] pooled design df = %d, t critical = %.4f\n",
            degf(des), qt(0.975, degf(des))))

## ---------------------------------------------------------------------------
## 3. the interaction test
## ---------------------------------------------------------------------------
base_cov <- "age + sex + race + education + income_pir"

# Returns the interaction term plus the burden slope implied for each cycle. The slope for
# the reference cycle is the burden main effect; for the other cycle it is main + interaction,
# whose SE needs the covariance, so it is taken from the model's vcov rather than added by hand.
interaction_test <- function(burden, design, label, scope) {
  f <- as.formula(paste("CFDDS ~", burden, "* cycle + n_drugs +", base_cov))
  m <- svyglm(f, design = design)
  co <- summary(m)$coefficients
  V  <- vcov(m)
  dfree <- degf(design); tc <- qt(0.975, dfree)
  ix <- grep(paste0("^", burden, ":cycle"), rownames(co), value = TRUE)
  stopifnot(length(ix) == 1)

  row <- function(est, se, term, cyc) data.frame(
    scope = scope, scale = label, term = term, cycle = cyc,
    estimate = est, ci_lower = est - tc * se, ci_upper = est + tc * se,
    p_value = 2 * pt(-abs(est / se), df = dfree), row.names = NULL)

  # slope in the reference cycle
  out <- row(co[burden, "Estimate"], co[burden, "Std. Error"],
             "burden slope", REF_CYCLE)
  # slope in the other cycle = main + interaction
  other <- setdiff(CYCLE_LIST, REF_CYCLE)
  est2  <- co[burden, "Estimate"] + co[ix, "Estimate"]
  se2   <- sqrt(V[burden, burden] + V[ix, ix] + 2 * V[burden, ix])
  out <- rbind(out, row(est2, se2, "burden slope", other))
  # the interaction itself - the actual test
  out <- rbind(out, row(co[ix, "Estimate"], co[ix, "Std. Error"],
                        "cycle x burden interaction", "difference"))

  # regTermTest wants the TERM label ("acb_burden:cycle"), not the coefficient name
  # ("acb_burden:cycle2011-2012"). Passing the latter yields a 0-dimensional vcov.
  wald <- regTermTest(m, paste0(burden, ":cycle"), df = dfree)
  attr(out, "wald") <- c(F = as.numeric(wald$Ftest), p = as.numeric(wald$p))
  attr(out, "n")    <- nrow(design$variables)
  out
}

report <- function(res, title) {
  w <- attr(res, "wald")
  cat("\n", strrep("-", 74), "\n", title, "  (n = ", attr(res, "n"), ")\n", sep = "")
  print(res %>% mutate(across(where(is.numeric), ~round(.x, 4))), row.names = FALSE)
  cat(sprintf("Wald test of the interaction: F = %.3f, p = %.4f  -> %s\n", w["F"], w["p"],
      if (w["p"] < 0.05) "the cycles DO differ significantly"
      else "NO significant difference between cycles"))
}

cat("\n\n================ PRIMARY: DSST, whole M4 sample ================")
main <- list(
  interaction_test("acb_burden",  des, "Boustani ACB", "all participants"),
  interaction_test("iacb_burden", des, "IACB",         "all participants"))
report(main[[1]], "Boustani ACB, cycle x burden")
report(main[[2]], "IACB, cycle x burden")

## ---------------------------------------------------------------------------
## 3b. the same test on standardised burdens
## ---------------------------------------------------------------------------
# Boustani (0-3 per drug) and IACB (0-4) are not comparable in raw units, so for a single
# plot the two need a common scale. Each burden is divided by its SD in the POOLED M4
# sample - pooled, not per cycle, because standardising within cycle would fold any
# difference in exposure spread into the interaction and confound the very thing being
# tested. Dividing rather than centring leaves every other coefficient where it was.
sd_acb  <- sd(des$variables$acb_burden)
sd_iacb <- sd(des$variables$iacb_burden)
des$variables$acb_z  <- des$variables$acb_burden  / sd_acb
des$variables$iacb_z <- des$variables$iacb_burden / sd_iacb
cat(sprintf("
[standardise] pooled SD: Boustani %.3f | IACB %.3f
", sd_acb, sd_iacb))

cat("

================ PRIMARY, STANDARDISED (per 1 SD) ================")
std <- list(
  interaction_test("acb_z",  des, "Boustani ACB", "all participants (per 1 SD)"),
  interaction_test("iacb_z", des, "IACB",         "all participants (per 1 SD)"))
report(std[[1]], "Boustani ACB per 1 SD, cycle x burden")
report(std[[2]], "IACB per 1 SD, cycle x burden")

## ---------------------------------------------------------------------------
## 4. secondary: the >=10 medicines stratum
## ---------------------------------------------------------------------------
# He asked for this too but said to keep it secondary given the numbers: 103 + 88 people.
# Subset the DESIGN, never the data frame - dropping rows before svydesign() discards the
# strata information the variance estimate needs.
cat("\n\n================ SECONDARY: >=10 medicines only ================")
cat("\nSmall stratum - Dr Sami asked to keep this secondary. Read as indicative.\n")
des_hi <- subset(des, med_band == ">=10 medicines")
hi <- interaction_test("iacb_burden", des_hi, "IACB", ">=10 medicines")
report(hi, "IACB at >=10 medicines, cycle x burden")

hi_b <- interaction_test("acb_burden", des_hi, "Boustani ACB", ">=10 medicines")
report(hi_b, "Boustani ACB at >=10 medicines, cycle x burden")

## ---------------------------------------------------------------------------
## 5. write out + sanity check against the per-cycle models
## ---------------------------------------------------------------------------
all_res <- bind_rows(main[[1]], main[[2]], std[[1]], std[[2]], hi, hi_b)
write.csv(all_res, file.path(cmp_dir, "pooled_cycle_interaction.csv"), row.names = FALSE)

wald_tab <- bind_rows(lapply(list(main[[1]], main[[2]], std[[1]], std[[2]], hi, hi_b), function(r) {
  w <- attr(r, "wald")
  data.frame(scope = r$scope[1], scale = r$scale[1], n = attr(r, "n"),
             wald_F = unname(w["F"]), wald_p = unname(w["p"]),
             conclusion = ifelse(w["p"] < 0.05, "cycles differ", "no cycle difference"),
             row.names = NULL)
}))
write.csv(wald_tab, file.path(cmp_dir, "pooled_interaction_wald.csv"), row.names = FALSE)
cat("\n\n================ SUMMARY OF THE INTERACTION TESTS ================\n")
print(wald_tab %>% mutate(across(where(is.numeric), ~round(.x, 4))), row.names = FALSE)

# The pooled per-cycle slopes are fitted on pooled data with shared covariate coefficients,
# so they will not equal the separate per-cycle estimates exactly. They should still be
# close; a large gap means the pooling has gone wrong somewhere.
cat("\n[check] pooled per-cycle burden slopes vs the separate per-cycle models:\n")
for (cy in CYCLE_LIST) {
  sep <- read.csv(file.path(base_dir, "outputs", cy, "tables", "models_dsst_primary.csv"),
                  stringsAsFactors = FALSE) %>%
    filter(model == "M4: fully adjusted", term == "acb_burden") %>% pull(estimate)
  pl <- main[[1]] %>% filter(term == "burden slope", cycle == cy) %>% pull(estimate)
  cat(sprintf("  %s Boustani: pooled %+.4f | separate %+.4f | diff %.4f\n", cy, pl, sep, abs(pl - sep)))
  if (abs(pl - sep) > 0.5)
    warning("pooled and separate estimates differ by more than 0.5 for ", cy)
}

cat("\nwrote pooled_cycle_interaction.csv and pooled_interaction_wald.csv to:\n  ",
    normalizePath(cmp_dir, winslash = "/", mustWork = FALSE), "\n")
