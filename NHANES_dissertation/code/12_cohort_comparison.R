# Cross-cohort comparison: NHANES 2013-2014 (dissertation) vs 2011-2012 (validation).
#
# Dr Sami asked for the same pipeline rerun on the earlier cycle as independent validation
# for the September presentation. This script does NOT refit anything - it reads the result
# CSVs both cycles have already written and lines them up. Same discipline as 09_figures.R:
# if the comparison cannot drift away from the tables, it will not.
#
# Run last, once both cycles are complete:
#   Rscript 11_corrected_crosswalk.R  &&  Rscript 11_corrected_crosswalk.R --cycle=2011-2012
#   Rscript 05_main_analysis.R        &&  Rscript 05_main_analysis.R --cycle=2011-2012
#   Rscript 12_cohort_comparison.R
#
# Writes to outputs/comparison/.

library(dplyr); library(ggplot2)

.f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
source(file.path(if (length(.f)) dirname(sub("^--file=", "", .f[1])) else ".", "config.R"))

dir.create(cmp_dir, showWarnings = FALSE, recursive = TRUE)

PRIMARY  <- "2013-2014"    # the dissertation cycle
VALIDATE <- "2011-2012"    # the replication Dr Sami asked for
BOTH     <- c(PRIMARY, VALIDATE)

# Read a result CSV for a named cycle. Fails loudly rather than returning an empty frame:
# a silently missing cohort would leave this whole script comparing one thing to itself.
grab <- function(cycle, file) {
  p <- file.path(base_dir, "outputs", cycle, "tables", file)
  if (!file.exists(p))
    stop("missing ", file, " for ", cycle,
         "\n  run the pipeline for that cycle first:",
         "\n    Rscript 11_corrected_crosswalk.R --cycle=", cycle,
         "\n    Rscript 05_main_analysis.R --cycle=", cycle)
  read.csv(p, stringsAsFactors = FALSE, check.names = FALSE) %>% mutate(cycle = cycle)
}
stack <- function(file) bind_rows(lapply(BOTH, grab, file = file))

fmt <- function(e, lo, hi, p)
  sprintf("%.2f (%.2f, %.2f)%s", e, lo, hi,
          ifelse(p < 0.001, "***", ifelse(p < 0.01, "**", ifelse(p < 0.05, "*", ""))))

wide <- function(df, id_cols, value_col)
  tidyr::pivot_wider(df[, c(id_cols, "cycle", value_col)],
                     names_from = cycle, values_from = all_of(value_col))

## 1. sample sizes -------------------------------------------------------------
flow <- stack("table_sample_flow.csv") %>%
  mutate(step = trimws(step),
         # the first row names its own cycle, which stops the two cohorts lining up
         step = ifelse(grepl("^Full NHANES", step), "Full NHANES sample", step))
flow_w <- wide(flow, "step", "n")
write.csv(flow_w, file.path(cmp_dir, "compare_sample_flow.csv"), row.names = FALSE)
cat("\n================ SAMPLE FLOW, BOTH CYCLES ================\n")
print(as.data.frame(flow_w))

## 2. the DSST model sequence, Boustani ----------------------------------------
dsst <- stack("models_dsst_primary.csv") %>%
  filter(term %in% c("acb_burden", "n_drugs")) %>%
  mutate(what  = ifelse(term == "acb_burden", "ACB burden", "Medication count"),
         value = fmt(estimate, ci_lower, ci_upper, p_value))
write.csv(dsst %>% select(cycle, model, what, term, estimate, ci_lower, ci_upper,
                          p_value, n_used),
          file.path(cmp_dir, "compare_dsst_models.csv"), row.names = FALSE)
cat("\n================ DSST, BOUSTANI ACB - BOTH CYCLES ================\n")
cat("per 1 ACB unit / per medicine; * p<0.05  ** p<0.01  *** p<0.001\n\n")
print(as.data.frame(wide(dsst, c("model", "what"), "value")))

## 3. all three outcomes, fully adjusted ---------------------------------------
outcomes <- bind_rows(
  stack("models_dsst_primary.csv")      %>% mutate(outcome_lab = "DSST (processing speed)"),
  stack("models_fluency_secondary.csv") %>% mutate(outcome_lab = "Animal fluency"),
  stack("models_recall_secondary.csv")  %>% mutate(outcome_lab = "CERAD delayed recall")) %>%
  filter(model == "M4: fully adjusted", term %in% c("acb_burden", "n_drugs")) %>%
  mutate(what  = ifelse(term == "acb_burden", "ACB burden", "Medication count"),
         value = fmt(estimate, ci_lower, ci_upper, p_value))
write.csv(outcomes %>% select(cycle, outcome_lab, what, estimate, ci_lower, ci_upper,
                              p_value, n_used),
          file.path(cmp_dir, "compare_outcomes_m4.csv"), row.names = FALSE)
cat("\n================ M4 ACROSS ALL THREE OUTCOMES ================\n")
cat("CERAD delayed recall is new - Dr Sami asked for it alongside DSST and fluency.\n\n")
print(as.data.frame(wide(outcomes, c("outcome_lab", "what"), "value")))

## 4. standardised head-to-head, both scales -----------------------------------
std <- stack("standardised_m4_comparison.csv") %>%
  mutate(value = fmt(estimate, ci_lower, ci_upper, p_value))
write.csv(std %>% select(cycle, scale, estimate, ci_lower, ci_upper, p_value, dAIC, n_used),
          file.path(cmp_dir, "compare_standardised.csv"), row.names = FALSE)
cat("\n================ STANDARDISED M4 (per 1 SD of burden) ================\n")
print(as.data.frame(wide(std, "scale", "value")))
cat("\nchange in AIC vs a model with medication count but no burden (negative = better fit):\n")
print(as.data.frame(wide(std, "scale", "dAIC")))

## 5. by medication band -------------------------------------------------------
mb <- stack("standardised_m4_by_medband.csv") %>%
  mutate(value = fmt(estimate, ci_lower, ci_upper, p_value))
write.csv(mb %>% select(cycle, band, scale, n, estimate, ci_lower, ci_upper, p_value, dAIC),
          file.path(cmp_dir, "compare_medband.csv"), row.names = FALSE)
cat("\n================ STANDARDISED M4 BY MEDICATION BAND ================\n")
print(as.data.frame(wide(mb, c("band", "scale"), "value")))

## 6. figure - M4 burden, both cycles, all three outcomes ----------------------
fig <- outcomes %>%
  filter(what == "ACB burden") %>%
  mutate(outcome_lab = factor(outcome_lab,
           levels = c("DSST (processing speed)", "Animal fluency", "CERAD delayed recall")),
         # reversed on purpose: the first level of a discrete y axis draws at the BOTTOM,
         # and the dissertation cycle should sit on top
         cycle_lab = factor(ifelse(cycle == PRIMARY, paste0(PRIMARY, " (dissertation)"),
                                                     paste0(VALIDATE, " (validation)")),
                            levels = c(paste0(VALIDATE, " (validation)"),
                                       paste0(PRIMARY,  " (dissertation)"))),
         sig = ifelse(p_value < 0.05, "p < 0.05", "not significant"))

p6 <- ggplot(fig, aes(x = estimate, y = cycle_lab, colour = sig)) +
  geom_vline(xintercept = 0, linetype = "22", colour = "grey45") +
  geom_errorbar(aes(xmin = ci_lower, xmax = ci_upper), orientation = "y",
                width = 0.18, linewidth = 0.5) +
  geom_point(size = 2.6) +
  # free_x because the three tests are on completely different scales - DSST runs to ~130
  # points and CERAD delayed recall to 10, so a shared axis would flatten the recall panel
  facet_wrap(~ outcome_lab, ncol = 1, scales = "free_x") +
  scale_colour_manual(values = c("p < 0.05" = "#1f4e79", "not significant" = "#c0392b"),
                      name = NULL) +
  labs(title = "Fully adjusted ACB burden in two independent NHANES cycles",
       subtitle = paste("Boustani ACB, per 1 unit of burden, medication count in the model.",
                        "Note the differing x scales."),
       x = "Change in test score per ACB unit (95% CI)", y = NULL) +
  theme_minimal(base_size = 11, base_family = "sans") +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(size = 9, colour = "grey30"),
        strip.text = element_text(face = "bold"),
        legend.position = "bottom",
        panel.grid.major.y = element_line(linewidth = 0.2, colour = "grey90"))

ggsave(file.path(cmp_dir, "fig6_cohort_comparison.png"), p6,
       width = 7.4, height = 6.0, dpi = 300, bg = "white")

## 7. what replicated and what did not -----------------------------------------
# Read straight off the tables above rather than typed in by hand, so this summary cannot
# claim something replicated while the CSV next to it says otherwise.
m4  <- outcomes %>% filter(what == "ACB burden", outcome_lab == "DSST (processing speed)")
g   <- function(cyc, col) m4[[col]][m4$cycle == cyc]
top <- mb %>% filter(band == ">=10 medicines", scale == "IACB")
tg  <- function(cyc, col) top[[col]][top$cycle == cyc]

cat("\n================ REPLICATION SUMMARY ================\n")
cat(sprintf("DSST M4, Boustani burden:  %s  %s  (n=%d)\n", PRIMARY,
            fmt(g(PRIMARY,"estimate"), g(PRIMARY,"ci_lower"), g(PRIMARY,"ci_upper"),
                g(PRIMARY,"p_value")), g(PRIMARY,"n_used")))
cat(sprintf("                           %s  %s  (n=%d)\n", VALIDATE,
            fmt(g(VALIDATE,"estimate"), g(VALIDATE,"ci_lower"), g(VALIDATE,"ci_upper"),
                g(VALIDATE,"p_value")), g(VALIDATE,"n_used")))
cat(sprintf("  same direction: %s | in %s it is %s at the 0.05 level\n",
            if (sign(g(PRIMARY,"estimate")) == sign(g(VALIDATE,"estimate"))) "yes" else "NO",
            VALIDATE, if (g(VALIDATE,"p_value") < 0.05) "still significant" else "NOT significant"))
cat(sprintf("  the %s interval %s the %s point estimate\n", VALIDATE,
            if (g(PRIMARY,"estimate") >= g(VALIDATE,"ci_lower") &&
                g(PRIMARY,"estimate") <= g(VALIDATE,"ci_upper")) "CONTAINS" else "excludes",
            PRIMARY))

cat(sprintf("\nIACB at >=10 medicines:    %s  %s  (n=%d)\n", PRIMARY,
            fmt(tg(PRIMARY,"estimate"), tg(PRIMARY,"ci_lower"), tg(PRIMARY,"ci_upper"),
                tg(PRIMARY,"p_value")), tg(PRIMARY,"n")))
cat(sprintf("                           %s  %s  (n=%d)\n", VALIDATE,
            fmt(tg(VALIDATE,"estimate"), tg(VALIDATE,"ci_lower"), tg(VALIDATE,"ci_upper"),
                tg(VALIDATE,"p_value")), tg(VALIDATE,"n")))
cat(sprintf("  significant in both cycles: %s\n",
            if (tg(PRIMARY,"p_value") < 0.05 && tg(VALIDATE,"p_value") < 0.05) "YES" else "no"))

cat("\nwrote comparison tables + fig6 to:", normalizePath(cmp_dir, mustWork = FALSE), "\n")
