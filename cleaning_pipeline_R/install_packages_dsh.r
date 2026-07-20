# =============================================================================
# NEOTREE CLEANING PIPELINE  (DSH / UCL Artifactory variant)
# install_packages_dsh.r  --  Install all required packages via UCL Artifactory
# =============================================================================
# Use this variant ONLY inside the UCL Data Safe Haven (DSH), where CRAN is not
# directly reachable and packages are mirrored through Artifactory.
# Outside the DSH, use install_packages.r (standard CRAN) instead.
#
# Run this script ONCE after your R environment is set up in the DSH.
#
# Usage (in RStudio -- open this file and click Source, or run in the console):
#   source("install_packages_dsh.r")
#
# BEFORE RUNNING: paste your personal Artifactory Bearer token below.
# Find it in the DSH web portal under your profile / API token.
# NEVER commit a real token to version control.
# =============================================================================

ARTIFACTORY_REPO  <- "https://artifactory.idhs.ucl.ac.uk/artifactory/cran"
ARTIFACTORY_TOKEN <- "YOUR_ARTIFACTORY_TOKEN_HERE"

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
cat("  Neotree Cleaning Pipeline (DSH) -- Package Installer\n")
cat("  R version:", R.version$major, ".", R.version$minor, "\n", sep = "")
cat("  Repository:", ARTIFACTORY_REPO, "\n")
cat("=============================================================\n\n")

if (ARTIFACTORY_TOKEN == "YOUR_ARTIFACTORY_TOKEN_HERE") {
  stop(
    "Token not set.\n",
    "  Edit install_packages_dsh.r and replace YOUR_ARTIFACTORY_TOKEN_HERE ",
    "with your personal Artifactory Bearer token."
  )
}

auth_header <- c(Authorization = paste("Bearer", ARTIFACTORY_TOKEN))

# -- Check which packages are missing -----------------------------------------
installed    <- rownames(installed.packages())
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

  cat("Installing from Artifactory...\n")
  install.packages(
    missing_pkgs,
    repos        = ARTIFACTORY_REPO,
    headers      = auth_header,
    dependencies = TRUE,
    quiet        = FALSE
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
  cat("Try installing them manually:\n")
  cat(sprintf(
    '  install.packages(c("%s"),\n    repos = "%s",\n    headers = c(Authorization = "Bearer YOUR_TOKEN"))\n',
    paste(failed, collapse = '", "'),
    ARTIFACTORY_REPO
  ))
}
cat("=============================================================\n")
