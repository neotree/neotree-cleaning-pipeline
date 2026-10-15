# =============================================================================
# NEOTREE CLEANING PIPELINE -- Package Installer (internal mirror)
# =============================================================================
# PURPOSE:
#   Installs the CRAN packages the pipeline needs from an internal package
#   mirror that requires a bearer token, and checks that each one loads.
#
# METHOD:
#   Compares `required_packages` with the installed packages, installs the
#   missing ones with their dependencies from MIRROR_REPO, sending MIRROR_TOKEN
#   as a bearer token, then attaches every required package in turn and prints
#   [OK] or [FAIL].
#
# INPUTS:
#   MIRROR_REPO   address of the package mirror
#   MIRROR_TOKEN  personal access token for the mirror
#   Set both below before running.  Do not share a copy of this file that
#   contains a token.
#
# OUTPUTS:
#   Installed packages in the R library, and a status listing on the console.
#
# USAGE (from the pipeline root):
#   Rscript install_packages_mirror.r
# =============================================================================

MIRROR_REPO  <- "YOUR_MIRROR_ADDRESS_HERE"
MIRROR_TOKEN <- "YOUR_TOKEN_HERE"

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
  "tibble",     # Tibble utilities (deframe)
  "openxlsx"    # Read and write .xlsx (dictionary build and validation scripts)
)

cat("=============================================================\n")
cat("  Neotree Cleaning Pipeline -- Package Installer (mirror)\n")
cat("  R version:", R.version$major, ".", R.version$minor, "\n", sep = "")
cat("=============================================================\n\n")

if (MIRROR_REPO == "YOUR_MIRROR_ADDRESS_HERE" || MIRROR_TOKEN == "YOUR_TOKEN_HERE") {
  stop(
    "Mirror address or token not set.\n",
    "  Edit install_packages_mirror.r and set MIRROR_REPO and MIRROR_TOKEN."
  )
}

auth_header  <- c(Authorization = paste("Bearer", MIRROR_TOKEN))
installed    <- rownames(installed.packages())
missing_pkgs <- required_packages[!required_packages %in% installed]

if (length(missing_pkgs) == 0) {
  cat("All", length(required_packages), "required packages are already installed.\n\n")
} else {
  cat(sprintf(
    "%d of %d packages need to be installed:\n  %s\n\n",
    length(missing_pkgs), length(required_packages),
    paste(missing_pkgs, collapse = ", ")
  ))
  install.packages(
    missing_pkgs,
    repos        = MIRROR_REPO,
    headers      = auth_header,
    dependencies = TRUE,
    quiet        = FALSE
  )
  cat("\nInstallation complete.\n\n")
}

cat("Verifying all packages load without errors...\n\n")
failed <- character(0)
for (pkg in required_packages) {
  ok <- suppressWarnings(
    tryCatch(
      { library(pkg, character.only = TRUE, quietly = TRUE); TRUE },
      error = function(e) FALSE
    )
  )
  cat(sprintf("  [%s] %s\n", if (ok) "OK" else "FAIL", pkg))
  if (!ok) failed <- c(failed, pkg)
}

if (length(failed) > 0) {
  stop("These packages could not be loaded: ", paste(failed, collapse = ", "))
}
cat("\nAll packages are installed and load correctly.\n")
