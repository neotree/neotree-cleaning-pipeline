# =============================================================================
# NEOTREE SAMPLE MAKER  (DSH / UCL Artifactory variant)
# install_packages_dsh.r  --  Install the (few) required packages via Artifactory
# =============================================================================
# Use this variant ONLY inside the UCL Data Safe Haven (DSH), where CRAN is not
# directly reachable and packages are mirrored through Artifactory.
# Outside the DSH, use install_packages.r (standard CRAN) instead.
#
# The core sample-maker pipeline runs on base R alone.  Only two optional CRAN
# packages are used (rstudioapi, openxlsx) -- see install_packages.r for detail.
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
  "rstudioapi",  # Interactive script-path detection (optional, RStudio only)
  "openxlsx"     # Write .xlsx workbook (run_subsample_user_dict.R)
)

cat("=============================================================\n")
cat("  Neotree Sample Maker (DSH) -- Package Installer\n")
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

installed    <- rownames(installed.packages())
missing_pkgs <- required_packages[!required_packages %in% installed]

if (length(missing_pkgs) == 0) {
  cat("All", length(required_packages), "packages are already installed.\n\n")
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

# -- Verify ---------------------------------------------------------------------
cat("Verifying packages load without errors...\n\n")

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
  cat("SUCCESS: optional packages installed and loadable.\n")
} else {
  cat("NOTE:", length(failed), "package(s) could not be loaded:\n")
  cat(" ", paste(failed, collapse = ", "), "\n")
}
cat("=============================================================\n")
