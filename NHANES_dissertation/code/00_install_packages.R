# Install the R packages this analysis needs.
# Run once before anything else:   Rscript 00_install_packages.R
#
# Installs into the user library, which avoids needing administrator rights to write
# into the system R library.

lib <- Sys.getenv("R_LIBS_USER")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib, .libPaths()))
cat("installing into:", lib, "\n")
cat("writable:", file.access(lib, mode = 2) == 0, "\n\n")

options(repos = c(CRAN = "https://cloud.r-project.org"))

needed <- c(
  "haven",    # read NHANES .xpt files
  "survey",   # complex-survey design and svyglm - the core of the analysis
  "dplyr",    # data manipulation
  "tidyr",    # data manipulation
  "ggplot2",  # figures (09_figures.R)
  "scales"    # figure axis formatting
)

missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) == 0) {
  cat("all packages already installed\n")
} else {
  cat("installing:", paste(missing, collapse = ", "), "\n")
  # Depends/Imports/LinkingTo only - pulling the full "Suggests" trees takes a very
  # long time and none of it is needed here.
  install.packages(missing, lib = lib,
                   dependencies = c("Depends", "Imports", "LinkingTo"))
}

cat("\nfinal check:\n")
ok <- TRUE
for (p in needed) {
  have <- requireNamespace(p, quietly = TRUE)
  ok <- ok && have
  cat(sprintf("  %-9s %s\n", p, if (have) "OK" else "MISSING"))
}
if (!ok) quit(status = 1)
cat("\n", R.version.string, "\n", sep = "")
cat("ready - next run 05_main_analysis.R (see ../README.md for the full order)\n")
