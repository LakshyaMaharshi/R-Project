# Figures for the dissertation.
#
# Reads ONLY the result CSVs already written by 05/06/07 - it never refits a model.
# That is deliberate: the figures cannot drift away from the numbers in the tables,
# because they are drawn from the same files those tables were built from.
#
# Run AFTER 05_main_analysis.R, 06_scale_sensitivity.R and 07_worked_examples.R.
# Writes 300-dpi PNGs to outputs/figures/.

library(ggplot2)
library(dplyr)
library(scales)

args_full <- commandArgs(trailingOnly = FALSE)
file_arg  <- grep("^--file=", args_full, value = TRUE)
script_dir <- if (length(file_arg) > 0) {
  dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = FALSE))
} else normalizePath(getwd(), winslash = "/", mustWork = FALSE)
base_dir <- file.path(script_dir, "..")
in_dir   <- file.path(base_dir, "outputs", "v2")
fig_dir  <- file.path(base_dir, "outputs", "figures")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

need <- function(f) {
  p <- file.path(in_dir, f)
  if (!file.exists(p)) stop("missing input: ", f, " - run 05/06/07 first")
  read.csv(p, stringsAsFactors = FALSE, check.names = FALSE)
}

base_theme <- theme_minimal(base_size = 11, base_family = "sans") +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold", size = 12),
        axis.title = element_text(size = 11),
        strip.text = element_text(face = "bold"))


## Figure 1 - participant flow -------------------------------------------------
flow <- need("table_sample_flow.csv")
lab <- trimws(flow$step); n <- flow$n

boxes <- data.frame(
  y = c(5, 4, 3, 2, 2),
  x = c(1, 1, 1, 0.45, 1.55),
  label = c(
    sprintf("NHANES 2013-2014 participants\nn = %s", comma(n[1])),
    sprintf("Aged 60 and over\nn = %s", comma(n[2])),
    sprintf("Given the cognitive module\nn = %s", comma(n[3])),
    sprintf("Valid DSST\n(primary outcome)\nn = %s", comma(n[4])),
    sprintf("Valid animal fluency\n(secondary outcome)\nn = %s", comma(n[5]))),
  stringsAsFactors = FALSE)

arrows <- data.frame(x = c(1, 1, 1, 1), xend = c(1, 1, 0.45, 1.55),
                     y = c(4.72, 3.72, 2.72, 2.72), yend = c(4.28, 3.28, 2.34, 2.34))

excl <- data.frame(x = 1.62, y = c(4.5, 3.5),
                   label = c(sprintf("excluded: aged under 60 (n = %s)", comma(n[1] - n[2])),
                             sprintf("excluded: no cognitive module (n = %s)", comma(n[2] - n[3]))))

fig1 <- ggplot() +
  geom_segment(data = arrows, aes(x = x, xend = xend, y = y, yend = yend),
               arrow = arrow(length = unit(0.16, "cm"), type = "closed"),
               linewidth = 0.4, colour = "grey30") +
  geom_label(data = boxes, aes(x = x, y = y, label = label),
             fill = "white", colour = "grey20", linewidth = 0.4,
             label.padding = unit(0.4, "lines"), size = 3.3, lineheight = 1.1) +
  geom_text(data = excl, aes(x = x, y = y, label = label),
            hjust = 0, size = 2.9, colour = "grey35", fontface = "italic") +
  scale_x_continuous(limits = c(0.05, 2.75)) +
  scale_y_continuous(limits = c(1.6, 5.4)) +
  labs(title = "Participant flow") +
  theme_void(base_size = 11) +
  theme(plot.title = element_text(face = "bold", size = 12, hjust = 0))

ggsave(file.path(fig_dir, "fig1_sample_flow.png"), fig1,
       width = 7.2, height = 4.2, dpi = 300, bg = "white")


## Figure 2 - dose-response, DSST by ACB category ------------------------------
# The means and SEs are survey-weighted (svyby in 05), but the interval multiplier has to
# match too. This used 1.96, the normal approximation, while every model in the write-up
# uses qt(0.975, design df) on the ~15 df NHANES actually gives - so the bars here were
# narrower than the analysis they sit next to. Read the df from 05 rather than hardcode it.
t1 <- need("table1_by_acb_category.csv")
tcrit <- need("design_df.csv")$t_crit_95[1]
ddf   <- need("design_df.csv")$degf[1]
cat(sprintf("  Fig 2 check: design df = %d, t = %.3f (was using 1.96)\n", ddf, tcrit))

d2 <- data.frame(cat = factor(t1$acb_cat, levels = c("ACB 0", "ACB 1-2", "ACB 3+")),
                 mean = t1$CFDDS, se = t1$se.CFDDS)

fig2 <- ggplot(d2, aes(x = cat, y = mean)) +
  geom_errorbar(aes(ymin = mean - tcrit * se, ymax = mean + tcrit * se),
                width = 0.11, linewidth = 0.5, colour = "grey30") +
  geom_point(size = 3.4, colour = "#2b5d8a") +
  geom_text(aes(label = sprintf("%.1f", mean)), vjust = -1.5, hjust = -0.35, size = 3.3) +
  scale_x_discrete(labels = c("ACB 0" = "None\n(ACB 0)",
                              "ACB 1-2" = "Low to moderate\n(ACB 1-2)",
                              "ACB 3+" = "High\n(ACB 3+)")) +
  labs(title = "Processing speed falls as anticholinergic burden rises",
       subtitle = sprintf("Survey-weighted means; 95%% CI on %d design degrees of freedom, as in the models.", ddf),
       x = "Anticholinergic burden category (Boustani)",
       y = "Weighted mean DSST score (95% CI)") +
  base_theme +
  theme(plot.subtitle = element_text(size = 9, colour = "grey30"))

ggsave(file.path(fig_dir, "fig2_dose_response.png"), fig2,
       width = 6.4, height = 4.2, dpi = 300, bg = "white")


## Figure 3 - forest plot, both scales (corrected crosswalk, coding a) ----------
m  <- need("models_corrected_crosswalk.csv")
fp <- m %>% filter(outcome == "CFDDS", startsWith(coding, "(a)"))

# label each row by what the coefficient actually is.
# The burden pattern is "burden$" and NOT "zerofill$". It used to be the latter, back when
# the terms were named acb_zerofill/iacb_zerofill, and when they were renamed to
# acb_burden/iacb_burden this case_when quietly stopped matching them. They then fell to
# the TRUE branch, came out as "M4 - acb_burden", failed the `row_lab %in% ord` filter
# below, and vanished. The figure went out with every burden estimate missing - only the
# medication-count rows left - which Dr Sami spotted. Hence the stopifnot() after the
# filter: dropping a row is now an error, not a silent omission.
fp <- fp %>%
  mutate(what = case_when(
    grepl("^n_drugs$", term)                 ~ "Medication count",
    grepl("burden$", term)                   ~ "Burden",
    grepl("1-2$", term)                      ~ "Burden category 1-2 (vs 0)",
    grepl("3\\+$", term)                     ~ "Burden category 3+ (vs 0)",
    grepl("^n_highpot", term)                ~ "Per high-potency drug",
    TRUE                                     ~ term),
    model_lab = sub(":.*", "", model),
    row_lab = paste0(model_lab, " - ", what),
    scale = factor(scale, levels = c("Boustani ACB (0-3)", "IACB (0-4)")),
    sig = ifelse(p_value < 0.05, "p < 0.05", "not significant"))

ord <- c("M1 - Medication count", "M2 - Burden", "M3 - Burden", "M3 - Medication count",
         "M4 - Burden", "M4 - Medication count", "M4+ - Burden", "M4+ - Medication count",
         "M4-IPW - Burden", "M5a - Burden category 1-2 (vs 0)",
         "M5a - Burden category 3+ (vs 0)", "M5b - Per high-potency drug")

dropped <- setdiff(unique(fp$row_lab), ord)
if (length(dropped) > 0)
  stop("fig 3: these model rows have no label and would be silently dropped: ",
       paste(dropped, collapse = ", "))

fp <- fp %>% filter(row_lab %in% ord) %>%
  mutate(row_lab = factor(row_lab, levels = rev(ord)))

# every scale x model combination that exists in the CSV must reach the plot
cat(sprintf("  Fig 3 check: %d rows plotted (%d Boustani, %d IACB); burden rows = %d\n",
            nrow(fp), sum(fp$scale == "Boustani ACB (0-3)"), sum(fp$scale == "IACB (0-4)"),
            sum(grepl("- Burden$", as.character(fp$row_lab)))))
stopifnot(sum(grepl("- Burden$", as.character(fp$row_lab))) >= 8)

fig3 <- ggplot(fp, aes(x = estimate, y = row_lab, colour = sig)) +
  geom_vline(xintercept = 0, linetype = "22", colour = "grey45") +
  geom_errorbar(aes(xmin = ci_lower, xmax = ci_upper), orientation = "y",
                width = 0.22, linewidth = 0.5) +
  geom_point(size = 2.3) +
  facet_wrap(~ scale) +
  scale_colour_manual(values = c("p < 0.05" = "#1f4e79", "not significant" = "#c0392b"),
                      name = NULL) +
  labs(title = "DSST associations under the two anticholinergic scales",
       subtitle = "Same participants, same models. Coefficients are not comparable in size between scales.",
       x = "Change in DSST score (95% CI)", y = NULL) +
  base_theme +
  theme(legend.position = "bottom",
        plot.subtitle = element_text(size = 9, colour = "grey30"),
        panel.grid.major.y = element_line(linewidth = 0.2, colour = "grey90"))

ggsave(file.path(fig_dir, "fig3_forest_both_scales.png"), fig3,
       width = 8.0, height = 5.4, dpi = 300, bg = "white")


## Figure 4 - drug-level agreement between the scales --------------------------
# Single-ingredient names in the sample scored by BOTH lists (combinations excluded:
# their summed scores are not on either scale's 0-3 / 0-4 range).
#
# Select on b_found/i_found, NOT on the score being non-NA. Since the 14 Aug rule that an
# unlisted drug contributes 0, every name carries a number, so a !is.na() filter quietly
# swept in all 436 single-ingredient names - 345 of which are on neither list and sit in
# the 0,0 cell. That reported 78% agreement instead of 22%. b_found > 0 is the same test
# 11_corrected_crosswalk.R uses for "positively on this list", so the two now agree.
dl <- need("drug_level_corrected.csv")
both <- dl %>% filter(is_combination %in% c(FALSE, "FALSE"),
                      b_found > 0, i_found > 0)
grid <- both %>% count(boustani_score, iacb_score, name = "n_drugs")

agree <- sum(grid$n_drugs[grid$boustani_score == grid$iacb_score])
tot   <- sum(grid$n_drugs)

fig4 <- ggplot(grid, aes(x = factor(boustani_score), y = factor(iacb_score), fill = n_drugs)) +
  geom_tile(colour = "white", linewidth = 0.9) +
  geom_text(aes(label = n_drugs), size = 3.4,
            colour = ifelse(grid$n_drugs > max(grid$n_drugs) * 0.55, "white", "grey15")) +
  scale_fill_gradient(low = "#eaf0f6", high = "#1f4e79", name = "Drugs") +
  labs(title = "The two scales often score the same drug differently",
       subtitle = sprintf("%d drugs scored by both scales; %d (%.1f%%) agree exactly (the diagonal)",
                          tot, agree, 100 * agree / tot),
       x = "Boustani ACB score", y = "IACB score") +
  coord_equal() +
  base_theme +
  theme(panel.grid = element_blank(),
        plot.subtitle = element_text(size = 9, colour = "grey30"))

ggsave(file.path(fig_dir, "fig4_scale_agreement.png"), fig4,
       width = 6.2, height = 4.6, dpi = 300, bg = "white")

## Figure 5 - standardised burden by medication band ---------------------------
# Both burdens on a 1 SD scale here, so unlike Figure 3 the two scales CAN be read
# against each other. This is the comparison Dr Sami asked for on 14 Aug.
mb <- need("standardised_m4_by_medband.csv")
mb <- mb %>% mutate(
  band = factor(band, levels = c("0-4 medicines", "5-9 medicines", ">=10 medicines"),
                labels = c("0-4 medicines", "5-9 medicines", "10 or more medicines")),
  # reversed on purpose: on a discrete y axis the first level draws at the BOTTOM, and
  # Boustani should sit above IACB to match the reading order everywhere else
  scale = factor(scale, levels = c("IACB", "Boustani ACB")),
  sig = ifelse(p_value < 0.05, "p < 0.05", "not significant"))

nlab <- mb %>% distinct(band, n) %>% mutate(lab = sprintf("n = %d", n))

fig5 <- ggplot(mb, aes(x = estimate, y = scale, colour = sig)) +
  geom_vline(xintercept = 0, linetype = "22", colour = "grey45") +
  geom_errorbar(aes(xmin = ci_lower, xmax = ci_upper), orientation = "y",
                width = 0.16, linewidth = 0.5) +
  geom_point(size = 2.6) +
  geom_text(data = nlab, aes(x = -Inf, y = Inf, label = lab), inherit.aes = FALSE,
            hjust = -0.15, vjust = 1.6, size = 3, colour = "grey35") +
  facet_wrap(~ band, ncol = 1) +
  scale_colour_manual(values = c("p < 0.05" = "#1f4e79", "not significant" = "#c0392b"),
                      name = NULL) +
  labs(title = "Which scale tracks DSST depends on the medication count",
       subtitle = "Fully adjusted models, both burdens standardised to 1 SD, so the scales are directly comparable.",
       x = "Change in DSST score per 1 SD of burden (95% CI)", y = NULL) +
  base_theme +
  theme(legend.position = "bottom",
        plot.subtitle = element_text(size = 9, colour = "grey30"),
        panel.grid.major.y = element_line(linewidth = 0.2, colour = "grey90"))

ggsave(file.path(fig_dir, "fig5_medband_standardised.png"), fig5,
       width = 7.2, height = 5.6, dpi = 300, bg = "white")

cat("wrote 5 figures to:", normalizePath(fig_dir, mustWork = FALSE), "\n")
cat(sprintf("  Fig 4 check: %d/%d drugs agree exactly (%.1f%%)\n", agree, tot, 100*agree/tot))

# The two scales have different ranges (0-3 vs 0-4), so "exact agreement" structurally
# under-counts the top end: a drug both scales regard as maximally anticholinergic scores
# 3 on Boustani and 4 on IACB, which reads as disagreement. Report that cell separately.
top_both <- sum(grid$n_drugs[grid$boustani_score == 3 & grid$iacb_score == 4])
cat(sprintf("  top-of-scale concordance: %d drugs are Boustani 3 AND IACB 4\n", top_both))
cat(sprintf("  agreement counting top-of-scale as concordant: %d/%d (%.1f%%)\n",
            agree + top_both, tot, 100 * (agree + top_both) / tot))
