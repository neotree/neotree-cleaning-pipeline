# =============================================================================
# NEOTREE CLEANING PIPELINE
# install_packages.r  --  Install all required CRAN packages
# =============================================================================
# Run this script once after a fresh R installation (or R upgrade) to ensure
# every package the pipeline needs is available.
#
# Usage (from the project root):
#   source("install_packages.r")
#   -- OR --
#   Rscript install_packages.r
# =============================================================================

required_packages <- c(
  "jsonlite",   # Read JSON data-key files (00_build_dictionary)
  "readr",      # Fast CSV reading
  "readxl",     # Load Excel dictionary files (.xlsx)
  "writexl",    # Write Excel output files (.xlsx)
  "dplyr",      # Data manipulation (filter, mutate, select, join)
  "tidyr",      # Reshaping helpers (pivot, fill)
  "stringr",    # String operations (str_detect, str_replace)
  "lubridate",  # Datetime parsing and validation
  "purrr",      # Functional helpers (map, walk)
  "logger",     # Structured pipeline logging
  "janitor",    # Column name cleaning (clean_names)
  "tibble"      # Tibble utilities (deframe)
)

cat("=============================================================\n")
cat("  Neotree Pipeline -- Package Installer\n")
cat("  R version:", R.version$major, ".", R.version$minor, "\n", sep = "")
cat("=============================================================\n\n")

# -- Check which packages are missing -----------------------------------------
installed   <- rownames(installed.packages())
missing_pkgs <- required_packages[!required_packages %in% installed]

if (length(missing_pkgs) == 0) {
  cat("All", length(required_packages), "required packages are already installed.\n\n")
} else {
  cat(sprintf(
    "%d of %d packages need to be installed:\n  %s\n\n",
    length(missing_pkgs),
    length(required_packages),
    paste(missing_pkgs, collapse = ", ")
  ))

  cat("Installing...\n")
  install.packages(
    missing_pkgs,
    repos      = "https://cloud.r-project.org",
    dependencies = TRUE,
    quiet      = FALSE
  )
  cat("\nInstallation complete.\n\n")
}

# -- Verify all packages load correctly ----------------------------------------
cat("Verifying all packages load without errors...\n\n")

failed <- character(0)
for (pkg in required_packages) {
  ok <- suppressWarnings(
    tryCatch(
      { library(pkg, character.only = TRUE, quietly = TRUE); TRUE },
      error = function(e) FALSE
    )
  )
  status <- if (ok) sprintf("  [OK]  %s (%s)", pkg, packageVersion(pkg))
            else     sprintf("  [FAIL] %s -- could not be loaded", pkg)
  cat(status, "\n")
  if (!ok) failed <- c(failed, pkg)
}

cat("\n=============================================================\n")
if (length(failed) == 0) {
  cat("SUCCESS: all", length(required_packages), "packages installed and loadable.\n")
  cat("You can now run the pipeline via source('run_pipeline.r').\n")
} else {
  cat("WARNING:", length(failed), "package(s) failed to load:\n")
  cat(" ", paste(failed, collapse = ", "), "\n")
  cat("Try installing them manually with:\n")
  cat('  install.packages(c("', paste(failed, collapse = '", "'), '"))\n', sep = "")
}
cat("=============================================================\n")
