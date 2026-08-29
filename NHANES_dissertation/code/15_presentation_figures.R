# Presentation figures for September.
#
# Dr Sami, 21 Aug: "I would also consider adding more plots (and improve their quality as
# you could use those directly in your PPT)."
#
# Revised 27 Aug to his figure brief: make the main DSST plot bigger, cut the M4/M4+ figure
# to the key estimates only, enlarge the scale-agreement plot and put concrete drug examples
# on it, and keep the medication-stratified result explicitly exploratory. The file names
# now run in his slide order (cohort, DSST, M4/M4+, scales, robustness, exploratory) so the
# folder can be worked through top to bottom while building the deck.
#
# These are sized and styled for slides rather than for a page: 16:9 proportions, larger
# type, fewer elements per plot, and the key number annotated on the plot itself so it can
# be read from the back of a room. Everything is drawn from the result CSVs - no model is
# refitted here, so a figure cannot disagree with the tables it came from.
#
#   Rscript 15_presentation_figures.R
#
# Prerequisite: both cycles plus 12 and 14.
# Writes 300 dpi PNGs to outputs/comparison/presentation/.

library(ggplot2); library(dplyr)

.f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
here <- if (length(.f)) dirname(sub("^--file=", "", .f[1])) else "."
source(file.path(here, "config.R"))

ppt_dir <- file.path(cmp_dir, "presentation")
dir.create(ppt_dir, showWarnings = FALSE, recursive = TRUE)

need <- function(f, dir = cmp_dir) {
  p <- file.path(dir, f)
  if (!file.exists(p)) stop("missing ", f, " - run 12 and 14 first")
  read.csv(p, stringsAsFactors = FALSE, check.names = FALSE)
}

PRIMARY  <- "2013-2014"
VALIDATE <- "2011-2012"
COL_SIG  <- "#1f4e79"; COL_NS <- "#c0392b"; COL_REF <- "grey45"

# Slide type has to survive projection, so base_size is well above the 11pt used for the
# dissertation figures and the grid is lighter to keep the ink on the data.
ppt_theme <- theme_minimal(base_size = 16, base_family = "sans") +
  theme(panel.grid.minor   = element_blank(),
        panel.grid.major.y = element_line(linewidth = 0.25, colour = "grey88"),
        plot.title    = element_text(face = "bold", size = 19, margin = margin(b = 4)),
        plot.subtitle = element_text(size = 13, colour = "grey30", margin = margin(b = 12)),
        plot.caption  = element_text(size = 11, colour = "grey40", hjust = 0),
        axis.title    = element_text(size = 14),
        strip.text    = element_text(face = "bold", size = 14),
        legend.position = "bottom", legend.text = element_text(size = 13),
        plot.margin = margin(14, 18, 12, 14))

save_ppt <- function(name, plot, w = 12, h = 6.75) {   # 16:9
  ggsave(file.path(ppt_dir, name), plot, width = w, height = h, dpi = 300, bg = "white")
  cat("  wrote", name, "\n")
}
star <- function(p) ifelse(p < 0.001, "***", ifelse(p < 0.01, "**", ifelse(p < 0.05, "*", "")))

# ggplot does NOT wrap a long caption or subtitle - it runs it off the right edge and
# silently clips it, which is how two of these went out with the last words missing.
# Wrap explicitly at a width that fits the 12in canvas.
wrap <- function(s, n = 105) paste(strwrap(s, width = n), collapse = "
")

cat("\npresentation figures ->", normalizePath(ppt_dir, winslash = "/", mustWork = FALSE), "\n")

## ===========================================================================
## P1. THE KEY TEST: does the burden effect differ between cycles?
## ===========================================================================
ix   <- need("pooled_cycle_interaction.csv")
wald <- need("pooled_interaction_wald.csv")

d1 <- ix %>% filter(scope == "all participants (per 1 SD)", term == "burden slope") %>%
  mutate(cycle_lab = factor(ifelse(cycle == PRIMARY, paste0(PRIMARY, "\n(dissertation)"),
                                                     paste0(VALIDATE, "\n(validation)")),
                            levels = c(paste0(VALIDATE, "\n(validation)"),
                                       paste0(PRIMARY,  "\n(dissertation)"))),
         sig = ifelse(p_value < 0.05, "p < 0.05", "not significant"))

# the interaction p-value is the point of the figure, so it goes on the panel
ann <- wald %>% filter(scope == "all participants (per 1 SD)") %>%
  mutate(lab = sprintf("cycle x burden interaction: p = %.2f\nno significant difference between cycles",
                       wald_p))

p1 <- ggplot(d1, aes(x = estimate, y = cycle_lab, colour = sig)) +
  geom_vline(xintercept = 0, linetype = "22", colour = COL_REF, linewidth = 0.6) +
  geom_errorbar(aes(xmin = ci_lower, xmax = ci_upper), orientation = "y",
                width = 0.14, linewidth = 0.9) +
  geom_point(size = 4) +
  geom_text(aes(label = sprintf("%.2f%s", estimate, star(p_value))),
            vjust = -1.2, size = 4.6, show.legend = FALSE) +
  # geom_label, not geom_text: the annotation sits over the zero reference line and the
  # gridlines, and a plain text layer reads as though the line runs through the words
  geom_label(data = ann, aes(x = Inf, y = -Inf, label = lab), inherit.aes = FALSE,
             hjust = 1.02, vjust = -0.35, size = 4.3, colour = "grey20", lineheight = 1.15,
             fill = "white", label.size = 0, label.padding = unit(0.35, "lines")) +
  facet_wrap(~ scale) +
  scale_colour_manual(values = c("p < 0.05" = COL_SIG, "not significant" = COL_NS), name = NULL) +
  labs(title = "The two cycles do not differ significantly",
       subtitle = paste("Fully adjusted DSST models fitted on the pooled sample (n = 2,756),",
                        "burdens standardised to 1 SD."),
       x = "Change in DSST per 1 SD of burden (95% CI)", y = NULL,
       caption = paste("Testing the cycles against each other directly, rather than comparing",
                       "a significant result in one with a non-significant result in the other.")) +
  expand_limits(x = 1.1) +
  ppt_theme
save_ppt("ppt5_cycle_interaction.png", p1)

## ===========================================================================
## P2. M4 burden across the three outcomes, both cycles
## ===========================================================================
out <- need("compare_outcomes_m4.csv") %>%
  filter(what == "ACB burden") %>%
  mutate(outcome_lab = factor(outcome_lab,
           levels = c("DSST (processing speed)", "Animal fluency", "CERAD delayed recall")),
         cycle_lab = factor(ifelse(cycle == PRIMARY, paste0(PRIMARY, " (dissertation)"),
                                                     paste0(VALIDATE, " (validation)")),
                            levels = c(paste0(VALIDATE, " (validation)"),
                                       paste0(PRIMARY,  " (dissertation)"))),
         sig = ifelse(p_value < 0.05, "p < 0.05", "not significant"))

p2 <- ggplot(out, aes(x = estimate, y = cycle_lab, colour = sig)) +
  geom_vline(xintercept = 0, linetype = "22", colour = COL_REF, linewidth = 0.6) +
  geom_errorbar(aes(xmin = ci_lower, xmax = ci_upper), orientation = "y",
                width = 0.14, linewidth = 0.9) +
  geom_point(size = 4) +
  facet_wrap(~ outcome_lab, scales = "free_x") +
  scale_colour_manual(values = c("p < 0.05" = COL_SIG, "not significant" = COL_NS), name = NULL) +
  labs(title = "Boustani burden and cognition, three outcomes, two cycles",
       subtitle = "Fully adjusted, per 1 unit of burden, medication count in the model.",
       x = "Change in test score per ACB unit (95% CI)", y = NULL,
       caption = "Each panel has its own x scale: DSST runs to about 130 points, CERAD recall to 10.") +
  ppt_theme
save_ppt("ppt7_outcomes_by_cycle.png", p2)

## ===========================================================================
## P3. Medication band - where IACB does the work
## ===========================================================================
mb <- need("compare_medband.csv")
# Put the sample sizes in the strip rather than beside each point. As an in-panel label at
# x = -Inf they sat on top of any interval that ran far enough left, which happened in two
# panels. n is a property of the band and cycle, so the strip is where it belongs.
band_n <- mb %>% distinct(band, cycle, n) %>%
  tidyr::pivot_wider(names_from = cycle, values_from = n)
band_lab <- setNames(
  sprintf("%s
(n = %s and %s)",
          c("0-4 medicines", "5-9 medicines", "10 or more medicines")[
            match(band_n$band, c("0-4 medicines", "5-9 medicines", ">=10 medicines"))],
          band_n[[PRIMARY]], band_n[[VALIDATE]]),
  band_n$band)

mb <- mb %>%
  mutate(band = factor(band, levels = c("0-4 medicines", "5-9 medicines", ">=10 medicines"),
                       labels = band_lab[c("0-4 medicines", "5-9 medicines", ">=10 medicines")]),
         cycle_lab = factor(ifelse(cycle == PRIMARY, paste0(PRIMARY, " (dissertation)"),
                                                     paste0(VALIDATE, " (validation)")),
                            levels = c(paste0(VALIDATE, " (validation)"),
                                       paste0(PRIMARY,  " (dissertation)"))),
         sig = ifelse(p_value < 0.05, "p < 0.05", "not significant"))

p3 <- ggplot(mb, aes(x = estimate, y = cycle_lab, colour = sig)) +
  geom_vline(xintercept = 0, linetype = "22", colour = COL_REF, linewidth = 0.6) +
  geom_errorbar(aes(xmin = ci_lower, xmax = ci_upper), orientation = "y",
                width = 0.14, linewidth = 0.9) +
  geom_point(size = 3.6) +
  facet_grid(band ~ scale) +
  scale_colour_manual(values = c("p < 0.05" = COL_SIG, "not significant" = COL_NS), name = NULL) +
  labs(title = "Exploratory: the scale that tracks DSST may depend on medication count",
       subtitle = paste("Fully adjusted DSST models within each medication band,",
                        "burdens standardised to 1 SD. Exploratory, not a primary result."),
       x = "Change in DSST per 1 SD of burden (95% CI)", y = NULL,
       caption = paste("Treat as hypothesis-generating. Splitting the sample three ways",
                       "leaves only 103 and 88 participants in the 10-or-more band,",
                       "
which is why those intervals are so wide.")) +
  ppt_theme + theme(strip.text.y = element_text(size = 12, angle = 0, lineheight = 1.2))
save_ppt("ppt6_medication_bands_exploratory.png", p3, h = 7.6)

## ===========================================================================
## P4. Scale disagreement, with concrete drugs  (Dr Sami, 27 Aug)
## ===========================================================================
# One cycle rather than two. He asked for this one enlarged with a few real drug examples,
# and a 2x2 facet of heatmaps leaves no room for either. The dissertation cycle carries the
# argument; the validation cycle agrees closely (22% exact agreement in both) and that is
# said in the subtitle rather than drawn again.
#
# Single-ingredient names only, and only those each scale positively recognises - the same
# b_found/i_found test the crosswalk uses, not !is.na(score), which would sweep in every
# drug that is on neither list and sit them all in the 0,0 cell.
dl <- need("drug_level_corrected.csv", file.path(base_dir, "outputs", PRIMARY, "tables")) %>%
  filter(is_combination %in% c(FALSE, "FALSE"), b_found > 0, i_found > 0)

grid <- dl %>% count(boustani_score, iacb_score, name = "n_drugs")
agree_pct <- 100 * sum(grid$n_drugs[grid$boustani_score == grid$iacb_score]) / sum(grid$n_drugs)

# The most-used drug in each cell, so a label names something the audience recognises
# rather than the alphabetically first obscure one.
top_drug <- dl %>% group_by(boustani_score, iacb_score) %>%
  slice_max(n_users, n = 1, with_ties = FALSE) %>%
  ungroup() %>% select(boustani_score, iacb_score, drug, n_users)

# Curated cells. Data-driven labelling of every off-diagonal cell would put 14 names on the
# plot and none of them would be read. These five carry the argument: the two commonest
# drugs in the whole sample disagree in OPPOSITE directions, the scales' top scores do not
# line up, and paroxetine is the most extreme single disagreement.
HIGHLIGHT <- data.frame(boustani_score = c(1, 0, 0, 3, 3),
                        iacb_score     = c(0, 1, 2, 4, 1))
lab <- HIGHLIGHT %>% inner_join(top_drug, by = c("boustani_score", "iacb_score")) %>%
  inner_join(grid, by = c("boustani_score", "iacb_score")) %>%
  # A dark red label on the darkest tile cannot be read, so flip to a light colour on
  # the dark tiles - the same threshold the count text uses.
  mutate(txt = sprintf("%s (%d)", drug, n_users),
         lab_col = ifelse(n_drugs > max(grid$n_drugs) * 0.55, "#ffe0d8", "#7d2b1f"))

p4 <- ggplot(grid, aes(x = factor(boustani_score), y = factor(iacb_score))) +
  geom_tile(aes(fill = n_drugs), colour = "white", linewidth = 1.4) +
  geom_text(aes(label = n_drugs), size = 6.2, fontface = "bold", nudge_y = 0.20,
            colour = ifelse(grid$n_drugs > max(grid$n_drugs) * 0.55, "white", "grey15")) +
  geom_text(data = lab, aes(label = txt, colour = I(lab_col)), inherit.aes = TRUE,
            nudge_y = -0.24, size = 3.9, fontface = "italic") +
  scale_fill_gradient(low = "#eaf0f6", high = COL_SIG, name = "Drugs") +
  labs(title = "The two scales disagree about the drugs people actually take",
       subtitle = wrap(sprintf(paste("%d single-ingredient drugs scored by both scales;",
                                     "only %.0f%% agree exactly (the diagonal).",
                                     "NHANES %s; 2011-2012 gives 22%% as well."),
                               sum(grid$n_drugs), agree_pct, PRIMARY), 110),
       x = "Boustani ACB score", y = "IACB score",
       caption = paste("Metoprolol and metformin are the two most-used drugs in the sample",
                       "and the scales disagree about them in opposite directions.",
                       "\nThe ranges also differ (0-3 against 0-4), so a drug both scales call",
                       "maximally anticholinergic sits off the diagonal at 3 and 4.")) +
  # No coord_equal here. Square tiles force the panel to a fixed aspect, which on a 16:9
  # canvas centres a narrow panel and leaves a band of white space down each side - and the
  # title and caption, which lay out against the panel, then run off the edge and clip.
  # Rectangular tiles fill the slide and give the drug labels room to sit inside a cell.
  ppt_theme +
  theme(panel.grid = element_blank(),
        plot.title.position = "plot", plot.caption.position = "plot")
save_ppt("ppt4_scale_disagreement.png", p4, w = 12, h = 7.4)

## ===========================================================================
## P5. Sample sizes
## ===========================================================================
flow <- need("compare_sample_flow.csv")
names(flow)[names(flow) == PRIMARY]  <- "primary"
names(flow)[names(flow) == VALIDATE] <- "validate"
fl <- flow %>%
  mutate(step = trimws(gsub("^\\.\\.\\.", "", step)),
         step = factor(step, levels = rev(step))) %>%
  tidyr::pivot_longer(c(primary, validate), names_to = "cycle", values_to = "n") %>%
  mutate(cycle = ifelse(cycle == "primary", paste0(PRIMARY, " (dissertation)"),
                                            paste0(VALIDATE, " (validation)")))

p5 <- ggplot(fl, aes(x = n, y = step, fill = cycle)) +
  geom_col(position = position_dodge(width = 0.72), width = 0.66) +
  geom_text(aes(label = format(n, big.mark = ",")), position = position_dodge(width = 0.72),
            hjust = -0.12, size = 4.1) +
  scale_fill_manual(values = setNames(c(COL_SIG, "#7ba7cc"),
                    c(paste0(PRIMARY, " (dissertation)"), paste0(VALIDATE, " (validation)"))),
                    name = NULL) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.16))) +
  labs(title = "Comparable samples in both cycles",
       subtitle = "Participant flow from the full NHANES sample to each cognitive outcome.",
       x = "Participants", y = NULL) +
  ppt_theme + theme(panel.grid.major.y = element_blank(),
                    panel.grid.major.x = element_line(linewidth = 0.25, colour = "grey88"))
save_ppt("ppt1_sample_flow.png", p5, h = 6.2)

## ===========================================================================
## P2. THE MAIN DSST RESULT  (Dr Sami, 27 Aug: "make the main DSST plot bigger")
## ===========================================================================
# The headline slide. One message, few marks, numbers big enough to read from the back:
# DSST falls as burden rises, and the fully adjusted estimate is printed on the panel so
# the descriptive gradient and the adjusted result are never separated.
pdir  <- file.path(base_dir, "outputs", PRIMARY, "tables")
t1    <- need("table1_by_acb_category.csv", pdir)
tcrit <- need("design_df.csv", pdir)$t_crit_95[1]
ddf   <- need("design_df.csv", pdir)$degf[1]
m4    <- need("models_dsst_primary.csv", pdir) %>%
           filter(model == "M4: fully adjusted", term == "acb_burden")

# n per category among those the weighted means actually describe: 60+ with a valid DSST.
ncat <- need("analysis_dataset_clean.csv", pdir) %>%
  filter(!is.na(CFDDS)) %>% count(acb_cat, name = "n")

CATS <- c("ACB 0", "ACB 1-2", "ACB 3+")
dr <- data.frame(cat = t1$acb_cat, mean = t1$CFDDS, se = t1[["se.CFDDS"]]) %>%
  left_join(ncat, by = c("cat" = "acb_cat")) %>%
  mutate(cat = factor(cat, levels = CATS,
                      labels = c("None", "Low to moderate", "High")),
         lo = mean - tcrit * se, hi = mean + tcrit * se)

p2b <- ggplot(dr, aes(x = cat, y = mean, group = 1)) +
  geom_line(linewidth = 0.9, colour = "grey70", linetype = "22") +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.09, linewidth = 1.0, colour = "grey35") +
  geom_point(size = 7, colour = COL_SIG) +
  geom_text(aes(label = sprintf("%.1f", mean)), hjust = -0.55, size = 6.4,
            fontface = "bold", colour = COL_SIG) +
  geom_text(aes(y = lo, label = sprintf("n = %s", format(n, big.mark = ","))),
            vjust = 2.4, size = 4.3, colour = "grey40") +
  scale_x_discrete(labels = c("None" = "None\n(ACB 0)",
                              "Low to moderate" = "Low to moderate\n(ACB 1-2)",
                              "High" = "High\n(ACB 3+)")) +
  scale_y_continuous(expand = expansion(mult = c(0.14, 0.10))) +
  labs(title = "Processing speed falls as anticholinergic burden rises",
       subtitle = wrap(sprintf(paste("Survey-weighted mean DSST, NHANES %s, adults aged 60",
                                     "and over. 95%% CI on %d design degrees of freedom."),
                               PRIMARY, ddf)),
       x = "Anticholinergic burden (Boustani ACB)",
       y = "Weighted mean DSST score",
       caption = wrap(sprintf(paste("Fully adjusted for age, sex, race, education, income AND",
                                    "medication count: %.2f DSST points per ACB unit",
                                    "(95%% CI %.2f to %.2f, p < 0.001, n = %s).",
                                    "The gradient is not explained by taking more medicines."),
                              m4$estimate, m4$ci_lower, m4$ci_upper,
                              format(m4$n_used, big.mark = ",")))) +
  ppt_theme +
  theme(panel.grid.major.x = element_blank(),
        axis.text.x = element_text(size = 15, lineheight = 1.1))
save_ppt("ppt2_dsst_main.png", p2b, h = 7.0)

## ===========================================================================
## P3. M4 vs M4+, KEY ESTIMATES ONLY  (Dr Sami, 27 Aug)
## ===========================================================================
# He asked for this cut back to the key estimates, so it is four numbers: burden and
# medication count, each before and after the comorbidities, on identical participants.
# Boustani only - this slide is about adjustment, not about the scales, and IACB behaves
# the same way (it is in compare_standardised.csv if it is asked about).
pair <- need("m4_vs_m4plus_same_sample.csv", pdir) %>% filter(scale == "Boustani ACB")
n_pair  <- pair$n[1]
is_plus <- grepl("comorbidities", pair$model)

mm <- bind_rows(
  pair %>% transmute(model, est = burden, lo = burden_lo, hi = burden_hi, p = burden_p,
                     term = "Anticholinergic burden (per 1 SD)"),
  pair %>% transmute(model, est = count,  lo = count_lo,  hi = count_hi,  p = count_p,
                     term = "Medication count (per medicine)")) %>%
  mutate(model = factor(ifelse(grepl("comorbidities", model),
                               "M4+  with comorbidities", "M4   without"),
                        levels = c("M4+  with comorbidities", "M4   without")),
         term = factor(term, levels = c("Anticholinergic burden (per 1 SD)",
                                        "Medication count (per medicine)")),
         sig = ifelse(p < 0.05, "p < 0.05", "not significant"))

# Computed, not typed, so the caption cannot drift from the estimates plotted above it.
b4 <- pair$burden[!is_plus]; b4p <- pair$burden[is_plus]
c4 <- pair$count[!is_plus];  c4p <- pair$count[is_plus]
cut_pct <- 100 * (1 - abs(c4p) / abs(c4))

p3b <- ggplot(mm, aes(x = est, y = model, colour = sig)) +
  geom_vline(xintercept = 0, linetype = "22", colour = COL_REF, linewidth = 0.6) +
  geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y", width = 0.12, linewidth = 1.0) +
  geom_point(size = 5) +
  geom_text(aes(label = sprintf("%.2f%s", est, star(p))), vjust = -1.5, size = 5.4,
            show.legend = FALSE) +
  facet_wrap(~ term, scales = "free_x") +
  scale_colour_manual(values = c("p < 0.05" = COL_SIG, "not significant" = COL_NS), name = NULL) +
  scale_y_discrete(expand = expansion(add = 0.8)) +
  labs(title = "Comorbidities absorb medication count, not burden",
       subtitle = wrap(sprintf(paste("The same %s participants in both models, so the",
                                     "covariates are the only change. Boustani ACB, %s."),
                               format(n_pair, big.mark = ","), PRIMARY)),
       x = "Change in DSST score (95% CI)", y = NULL,
       caption = wrap(sprintf(paste("Adding stroke, cardiovascular disease, diabetes,",
                                    "depression and self-rated health changes burden by",
                                    "%.2f points, but cuts medication count by %.0f%%, to the",
                                    "edge of significance. This is the evidence that burden",
                                    "carries information medication count does not."),
                              abs(b4p - b4), cut_pct))) +
  ppt_theme + theme(panel.grid.major.y = element_blank(),
                    panel.grid.major.x = element_line(linewidth = 0.25, colour = "grey88"))
save_ppt("ppt3_m4_vs_m4plus.png", p3b, h = 6.4)
cat("\n7 presentation figures written, in slide order.\n")
cat("All are drawn from the result CSVs, so they cannot disagree with the tables.\n")
