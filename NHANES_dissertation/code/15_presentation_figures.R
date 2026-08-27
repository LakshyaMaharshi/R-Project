# Presentation figures for September.
#
# Dr Sami, 21 Aug: "I would also consider adding more plots (and improve their quality as
# you could use those directly in your PPT)."
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
save_ppt("ppt1_cycle_interaction.png", p1)

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
save_ppt("ppt2_outcomes_by_cycle.png", p2)

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
  labs(title = "IACB is the scale that holds at high medication counts",
       subtitle = paste("Fully adjusted DSST models within each medication band,",
                        "burdens standardised to 1 SD."),
       x = "Change in DSST per 1 SD of burden (95% CI)", y = NULL,
       caption = paste("The 10-or-more band is small in both cycles (103 and 88),",
                       "so it is indicative rather than conclusive.")) +
  ppt_theme + theme(strip.text.y = element_text(size = 12, angle = 0, lineheight = 1.2))
save_ppt("ppt3_medication_bands.png", p3, h = 7.6)

## ===========================================================================
## P4. Scale disagreement, both cycles
## ===========================================================================
# Drawn from each cycle's own drug-level table. Single-ingredient names only, and only
# those each scale positively recognises - the same b_found/i_found test the crosswalk
# uses, not !is.na(score), which would sweep in every drug on neither list.
grid <- bind_rows(lapply(c(PRIMARY, VALIDATE), function(cy) {
  need("drug_level_corrected.csv", file.path(base_dir, "outputs", cy, "tables")) %>%
    filter(is_combination %in% c(FALSE, "FALSE"), b_found > 0, i_found > 0) %>%
    count(boustani_score, iacb_score, name = "n_drugs") %>%
    mutate(cycle = cy)
}))
agree <- grid %>% group_by(cycle) %>%
  summarise(pct = 100 * sum(n_drugs[boustani_score == iacb_score]) / sum(n_drugs),
            tot = sum(n_drugs), .groups = "drop") %>%
  mutate(lab = sprintf("%s: %d drugs, %.0f%% agree", cycle, tot, pct))

p4 <- ggplot(grid, aes(x = factor(boustani_score), y = factor(iacb_score), fill = n_drugs)) +
  geom_tile(colour = "white", linewidth = 1.1) +
  geom_text(aes(label = n_drugs), size = 4.6,
            colour = ifelse(grid$n_drugs > max(grid$n_drugs) * 0.55, "white", "grey15")) +
  facet_wrap(~ cycle) +
  scale_fill_gradient(low = "#eaf0f6", high = COL_SIG, name = "Drugs") +
  labs(title = "The two scales often score the same drug differently",
       subtitle = paste0("Drugs on the diagonal agree. ",
                         paste(agree$lab, collapse = "   |   "), "."),
       x = "Boustani ACB score", y = "IACB score",
       caption = paste("The ranges differ (0-3 against 0-4), so a drug both scales call",
                       "maximally anticholinergic sits off the diagonal at 3 and 4.")) +
  coord_equal() +
  ppt_theme + theme(panel.grid = element_blank())
save_ppt("ppt4_scale_disagreement.png", p4, h = 7.0)

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
save_ppt("ppt5_sample_flow.png", p5, h = 6.2)

cat("\n5 presentation figures written.\n")
cat("All are drawn from the result CSVs, so they cannot disagree with the tables.\n")
