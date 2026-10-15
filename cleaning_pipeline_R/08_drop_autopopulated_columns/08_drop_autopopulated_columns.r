# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 08: Drop Auto-Populated (Discharge Copy) Columns
# =============================================================================
# PURPOSE:
#   Passes the data through unchanged and writes a report.  DC-suffix columns
#   (e.g. apgar1dc, gestationdc, hivtestresultdc) are treated as independent
#   discharge-form entries and are retained alongside their admission-form
#   counterparts.
#
# INPUTS:
#   df  - data.frame after Module 07
#
# OUTPUTS:
#   df      - data.frame unchanged
#   Report  - cfg$report_dir/08_autopopulated_columns_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("08_drop_autopopulated_columns/08_drop_autopopulated_columns.r")
# =============================================================================

source("00_setup/00_setup.r")

# -- Report --------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "08_autopopulated_columns_report.txt") else NULL

if (!is.null(report_path) && nzchar(report_path)) {
  tryCatch({
    lines <- c(
      "Module 08 - Auto-Populated Column Drop Report",
      "==============================================",
      sprintf("Run timestamp               : %s",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      sprintf("Country                     : %s", toupper(cfg$country)),
      sprintf("Dataset                     : %s", cfg$dataset),
      "",
      sprintf("Columns                     : %d (unchanged)", ncol(df)),
      "Auto-populated cols dropped : 0",
      "",
      "NOTE: DC-suffix columns (e.g. apgar1dc, gestationdc, hivtestresultdc)",
      "are treated as independent discharge-form entries and are retained",
      "alongside their admission-form counterparts."
    )
    writeLines(lines, report_path)
  }, error = function(e) log_warn("Could not write Module 08 report: %s", e$message))
}

log_info("Module 08 complete (no-op -- DC columns retained as independent). Dimensions: %d rows x %d cols.",
         nrow(df), ncol(df))
