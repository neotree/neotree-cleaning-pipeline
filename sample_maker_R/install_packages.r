# =============================================================================
# NEOTREE SAMPLE MAKER
# install_packages.r  --  Install the (few) required CRAN packages
# =============================================================================
# The core sample-maker pipeline runs on base R alone.  Only two optional CRAN
# packages are used:
#
#   rstudioapi  -- detect the script path when sourcing interactively in
#                  RStudio.  Wrapped in tryCatch; NOT required when running via
#                  Rscript (e.g. `Rscript run_sample_maker.R`).
#   openxlsx    -- write the combined Excel workbook produced by
#                  run_subsample_user_dict.R (user dictionary + data profile).
#
# Inside the UCL Data Safe Haven, use install_packages_dsh.r instead.
#
# Usage (from the sample_maker_R directory):
#   source("install_packages.r")
#   -- OR --
#   Rscript install_packages.r
# =============================================================================

required_packages <- c(
  "rstudioapi",  # Interactive script-path detection (optional, RStudio only)
  "openxlsx"     # Write .xlsx workbook (run_subsample_user_dict.R)
)

cat("=============================================================\n")
cat("  Neotree Sample Maker -- Package Installer\n")
cat("  R version:", R.version$major, ".", R.version$minor, "\n", sep = "")
cat("=============================================================\n\n")

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

  cat("Installing...\n")
  install.packages(
    missing_pkgs,
    repos        = "https://cloud.r-project.org",
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
  cat("The core pipeline still runs on base R; these are only needed for\n")
  cat("interactive RStudio use (rstudioapi) and Excel output (openxlsx).\n")
}
cat("=============================================================\n")
