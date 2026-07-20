# =============================================================================
# NEOTREE CLEANING PIPELINE -- Master Runner
# =============================================================================
# PURPOSE:
#   Runs all pipeline modules in the correct order.
#   Edit 00_setup/00_setup.R to change COUNTRY, DATASET, file paths before
#   running.
#
# SUPPORTED COMBINATIONS:
#   COUNTRY x DATASET
#   "ZIM"   x "admissions"         (e.g. admissions_202603121319.csv)
#   "ZIM"   x "discharges"         (e.g. discharges_202603121212.csv)
#   "ZIM"   x "maternal_outcomes"  (e.g. maternal_outcomes_202603121116.csv)
#   "MWI"   x "admissions"
#   "MWI"   x "discharges"
#   "MWI"   x "maternal_outcomes"
#
# EXECUTION ORDER:
#   00   Setup & configuration
#   00a  PII detection and removal      <- MUST run on raw data, before cleaning
#   01   Standardise column headers     (drops .parentKey metadata cols)
#   02   Frame shift correction
#   03   Duplicate column merging
#   04   Dictionary-based value cleaning
#   05   Forward fill placeholder values
#   06   Forward fill numeric / datetime values
#   07   Drop redundant label columns
#   08   Drop auto-populated discharge columns
#   09   Data type assignment
#   10   Remove duplicate rows          <- End of first-stage cleaning
#   11   Numeric validation
#   12   Boolean validation
#   13   Categorical / object validation
#   14   Datetime validation
#   14a  Resolve neolab datebct from admissions (neolab only; skips instantly otherwise)
#   15   Final merge and output         <- Produces clean CSV + RDS
#   00b  Rename to harmonised column names (optional post-processing)
#   16   NA reason coding               <- Classifies every NA cell (-6/-7/-8/-9)
#
# USAGE:
#   Rscript run_pipeline.R
#   # or, interactively in RStudio:
#   source("run_pipeline.r")
# =============================================================================

# -----------------------------------------------------------------------------
# Run-from-anywhere: anchor the working directory to the pipeline root (this
# file's own folder) so every relative path below resolves regardless of where
# the script was launched (Rscript, source(), RStudio "Source", R console).
# Idempotent when sourced from run_all.r (which already anchors to the root).
# -----------------------------------------------------------------------------
.nt_get_script_dir <- function() {
  args     <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0)
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
  for (i in seq_len(sys.nframe())) {
    ofile <- sys.frame(i)$ofile
    if (!is.null(ofile) && nchar(ofile) > 0)
      return(dirname(normalizePath(ofile)))
  }
  getwd()
}
setwd(normalizePath(.nt_get_script_dir(), mustWork = FALSE))

pipeline_start <- Sys.time()
cat(sprintf("\n[%s] Neotree Cleaning Pipeline started.\n\n",
            format(pipeline_start, "%Y-%m-%d %H:%M:%S")))

# -- 00  Setup -----------------------------------------------------------------
cat("[ 00 ]  Setup & configuration\n")
source("00_setup/00_setup.r")

# -- 00a  PII removal (FIRST - operates on raw data) --------------------------
cat("[ 00a]  PII detection and removal\n")
source("00a_pii_detection_removal/00a_pii_detection_removal.r")
# df_raw_deidentified is available globally; Module 01 picks it up via df_raw.

# -- 01  Standardise column headers --------------------------------------------
cat("[ 01 ]  Standardise column headers\n")
source("01_standardise_column_headers/01_standardise_column_headers.r")

# -- 02  Frame shift correction ------------------------------------------------
cat("[ 02 ]  Frame shift correction\n")
source("02_frame_shift_correction/02_frame_shift_correction.r")

# -- 03  Duplicate column merging ----------------------------------------------
cat("[ 03 ]  Duplicate column merging\n")
source("03_duplicate_column_merging/03_duplicate_column_merging.r")

# -- 04  Dictionary-based value cleaning ---------------------------------------
cat("[ 04 ]  Dictionary-based value cleaning\n")
source("04_dictionary_value_cleaning/04_dictionary_value_cleaning.r")

# -- 05  Forward fill placeholder values ---------------------------------------
cat("[ 05 ]  Forward fill placeholder values\n")
source("05_forward_fill_placeholders/05_forward_fill_placeholders.r")

# -- 06  Forward fill numeric / datetime values --------------------------------
cat("[ 06 ]  Forward fill numeric and datetime values\n")
source("06_forward_fill_numeric_datetime/06_forward_fill_numeric_datetime.r")

# -- 07  Drop redundant label columns ------------------------------------------
cat("[ 07 ]  Drop redundant label columns\n")
source("07_drop_label_columns/07_drop_label_columns.r")

# -- 08  Drop auto-populated discharge columns ---------------------------------
cat("[ 08 ]  Drop auto-populated discharge columns\n")
source("08_drop_autopopulated_columns/08_drop_autopopulated_columns.r")

# -- 09  Data type assignment --------------------------------------------------
cat("[ 09 ]  Data type assignment\n")
source("09_data_type_assignment/09_data_type_assignment.r")

# -- 10  Remove duplicate rows -------------------------------------------------
cat("[ 10 ]  Remove duplicate rows  [end of first-stage cleaning]\n")
source("10_remove_duplicate_rows/10_remove_duplicate_rows.r")

# -- 11  Numeric validation ----------------------------------------------------
cat("[ 11 ]  Numeric validation\n")
source("11_numeric_validation/11_numeric_validation.r")

# -- 12  Boolean validation ----------------------------------------------------
cat("[ 12 ]  Boolean validation\n")
source("12_boolean_validation/12_boolean_validation.r")

# -- 13  Categorical / object validation ---------------------------------------
cat("[ 13 ]  Categorical and object validation\n")
source("13_categorical_object_validation/13_categorical_object_validation.r")

# -- 14  Datetime validation ---------------------------------------------------
cat("[ 14 ]  Datetime validation\n")
source("14_datetime_validation/14_datetime_validation.r")

# -- 14a  Resolve neolab datebct from admissions (neolab only) ----------------
# Adds datebct_resolved (POSIXct) and datebct_source (character) to df_datetime.
# For all other datasets this exits in < 1ms after a single cfg$dataset check.
cat("[ 14a]  Resolve missing datebct from admissions (neolab only)\n")
source("14a_resolve_neolab_datebct/14a_resolve_neolab_datebct.r")

# -- 15  Final merge and output ------------------------------------------------
cat("[ 15 ]  Final merge and output\n")
source("15_final_merge_output/15_final_merge_output.r")

# -- 00b  Rename to harmonised column names (post-processing) ------------------
cat("[ 00b]  Rename to harmonised column names\n")
source("00b_rename_harmonised_columns/00b_rename_harmonised_columns.r")

# -- 16  NA reason coding -------------------------------------------------------
# Classifies every NA cell in the final cleaned dataset as one of:
#   -6 Redacted (PII)   -7 Not applicable (skip logic)
#   -8 Invalid/removed  -9 Unknown
# Requires cfg$neotree_scripts_dir to point to the neotree_scripts/ directory.
# Produces *_na_reasons.csv (wide) and *_na_reasons_long.csv (provenance table).
cat("[ 16 ]  NA reason coding\n")
if (dir.exists(cfg$neotree_scripts_dir)) {
  source("16_na_reason_coding/16_na_reason_coding.r")
} else {
  log_warn(paste(
    "Module 16 skipped: neotree_scripts_dir not found (%s).",
    "Set NEOTREE_SCRIPTS_DIR in 00_setup.r to enable NA reason coding."
  ), cfg$neotree_scripts_dir)
}

# -- Consolidate module reports ------------------------------------------------
if (!is.null(cfg$report_dir) && dir.exists(cfg$report_dir)) {
  txt_files <- sort(list.files(cfg$report_dir, pattern = "\\.txt$", full.names = TRUE))
  if (length(txt_files) > 0) {
    sep_thick <- paste0(strrep("=", 79))
    sep_thin  <- paste0(strrep("-", 79))
    combined  <- c(
      sep_thick,
      "  NEOTREE CLEANING PIPELINE -- CONSOLIDATED REPORT",
      sprintf("  Run      : %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      sprintf("  Country  : %s  |  Dataset : %s  |  Source : %s",
              cfg$country, cfg$dataset, cfg$data_source),
      sprintf("  Input    : %s", basename(cfg$csv_filepath)),
      sep_thick,
      ""
    )
    for (f in txt_files) {
      combined <- c(
        combined,
        sep_thin,
        sprintf("  [ %s ]", basename(f)),
        sep_thin,
        "",
        readLines(f, warn = FALSE),
        ""
      )
    }
    combined_path <- file.path(cfg$report_dir, "00_pipeline_report.txt")
    writeLines(combined, combined_path)
    log_info("Consolidated report written: %s", combined_path)
  }
}

# -- Summary -------------------------------------------------------------------
elapsed <- difftime(Sys.time(), pipeline_start, units = "secs")
cat(sprintf(
  "\n[%s] Pipeline complete in %.1f seconds.\n",
  format(Sys.time(), "%Y-%m-%d %H:%M:%S"), as.numeric(elapsed)
))
cat(sprintf("  Output CSV       : %s\n", cfg$output_csv))
cat(sprintf("  Output RDS       : %s\n", cfg$output_rds))
cat(sprintf("  Final dims       : %d rows x %d cols\n",
            nrow(df_clean), ncol(df_clean)))
cat(sprintf("  Harmonised CSV   : %s\n",
            sub("\\.csv$", "_harmonised.csv", cfg$output_csv)))
if (!is.null(cfg$report_dir)) {
  cat(sprintf("  Reports folder   : %s/\n", cfg$report_dir))
  cat(sprintf("  Consolidated log : %s\n\n",
              file.path(cfg$report_dir, "00_pipeline_report.txt")))
}
