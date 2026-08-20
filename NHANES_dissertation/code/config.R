# Which NHANES cycle am I running? Everything cycle-specific lives HERE and nowhere else.
#
# Dr Sami asked (15 + 20 Aug) for the whole pipeline rerun on the earlier 2011-2012 cycle
# as independent validation for the September presentation. The obvious way to do that is
# copy the scripts and swap _H for _G. I'm not doing that. The cycle suffix appeared ~50
# times across seven scripts, and the two bugs he already caught were both a string that
# stopped matching after something got renamed - a forked copy is that failure mode with
# a second codebase attached. One pipeline, one place to name a cycle.
#
# Usage:  Rscript 05_main_analysis.R --cycle=2011-2012
#         Rscript 05_main_analysis.R                  (defaults to 2013-2014)
#
# To add a future cycle, add one row to CYCLES below. Nothing else should need editing.

CYCLES <- list(
  # id           file suffix   CDC url year   label used in output
  "2013-2014" = list(suffix = "_H", url_year = "2013", label = "NHANES 2013-2014"),
  "2011-2012" = list(suffix = "_G", url_year = "2011", label = "NHANES 2011-2012")
)

DEFAULT_CYCLE <- "2013-2014"   # the dissertation cycle; leaving this alone keeps 05/11 reproducing the published numbers

## resolve the cycle -----------------------------------------------------------
# order: --cycle= flag, then NHANES_CYCLE env var, then the default.
resolve_cycle <- function() {
  a <- grep("^--cycle=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(a) > 0) return(sub("^--cycle=", "", a[1]))
  e <- Sys.getenv("NHANES_CYCLE", "")
  if (nzchar(e)) return(e)
  DEFAULT_CYCLE
}

CYCLE <- resolve_cycle()
if (!CYCLE %in% names(CYCLES))
  stop("unknown cycle '", CYCLE, "' - known cycles: ", paste(names(CYCLES), collapse = ", "))

SUFFIX       <- CYCLES[[CYCLE]]$suffix
CYCLE_LABEL  <- CYCLES[[CYCLE]]$label
CYCLE_YEAR   <- CYCLES[[CYCLE]]$url_year

## paths ------------------------------------------------------------------------
# Same script-location dance as before: Rscript gives us --file=, an interactive session
# doesn't, in which case you must already be sitting in code/.
.args <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_dir <- if (length(.args) > 0) {
  dirname(normalizePath(sub("^--file=", "", .args[1]), winslash = "/", mustWork = FALSE))
} else normalizePath(getwd(), winslash = "/", mustWork = FALSE)

base_dir   <- file.path(script_dir, "..")
data_dir   <- file.path(base_dir, "data", CYCLE)      # raw .xpt for THIS cycle
scales_dir <- file.path(base_dir, "data", "scales")   # drug lists - not cycle-specific
out_dir    <- file.path(base_dir, "outputs", CYCLE, "tables")
fig_dir    <- file.path(base_dir, "outputs", CYCLE, "figures")
cmp_dir    <- file.path(base_dir, "outputs", "comparison")

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

# NHANES names its files DEMO_H.xpt in 2013-2014 and DEMO_G.xpt in 2011-2012, so ask for
# the stem and let this add the suffix. Every read in the pipeline goes through here,
# which is the whole point - there is no second place for the suffix to go stale.
xpt <- function(stem) file.path(data_dir, paste0(stem, SUFFIX, ".xpt"))

cat(sprintf("[cycle] %s (%s) | data: %s\n", CYCLE, CYCLE_LABEL,
            normalizePath(data_dir, winslash = "/", mustWork = FALSE)))
