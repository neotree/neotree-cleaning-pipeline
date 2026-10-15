# =============================================================================
# NEOTREE CLEANING PIPELINE -- Master Runner
# =============================================================================
# PURPOSE:
#   Runs every pipeline module in order for one input file, then combines the
#   module reports into one text file and prints a summary.
#
# METHOD:
#   Sets the working directory to this file's folder and sources each module
#   script in this order:
#     00   Setup and configuration
#     00a  PII detection and removal (on the raw data)
#     01   Standardise column headers
#     02   Frame shift correction
#     03   Duplicate column merging
#     04   Dictionary-based value cleaning
#     05   Forward fill placeholder values
#     06   Forward fill numeric and datetime values
#     07   Drop redundant label columns
#     08   Drop auto-populated discharge columns
#     09   Data type assignment
#     10   Remove duplicate rows (end of first-stage cleaning)
#     11   Numeric validation
#     12   Boolean validation
#     13   Categorical and object validation
#     14   Datetime validation
#     14a  Resolve neolab datebct from admissions (neolab only)
#     15   Final merge and output
#     00b  Rename to harmonised column names
#     16   NA reason coding (only if cfg$neotree_scripts_dir exists)
#
# INPUTS:
#   The settings in 00_setup/00_setup.r (COUNTRY, DATASET, CSV_FILEPATH and
#   the rest), either edited there or set as globals by run_all.r.
#
# OUTPUTS:
#   The files written by the modules (cfg$output_csv, cfg$output_rds, the
#   harmonised CSV, the module reports), plus 00_pipeline_report.txt in
#   cfg$report_dir, which concatenates every .txt report in that folder.
#
# USAGE:
#   Rscript run_pipeline.r
#   # or, interactively:
#   source("run_pipeline.r")
# =============================================================================

# -----------------------------------------------------------------------------
# Set the working directory to this file's own folder so that the relative
# paths below resolve wherever the script is launched from (Rscript, source(),
# R console).
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

# -- 00a  PII removal (on the raw data) ----------------------------------------
cat("[ 00a]  PII detection and removal\n")
source("00a_pii_detection_removal/00a_pii_detection_removal.r")

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
cat("[ 14a]  Resolve missing datebct from admissions (neolab only)\n")
source("14a_resolve_neolab_datebct/14a_resolve_neolab_datebct.r")

# -- 15  Final merge and output ------------------------------------------------
cat("[ 15 ]  Final merge and output\n")
source("15_final_merge_output/15_final_merge_output.r")

# -- 00b  Rename to harmonised column names ------------------------------------
cat("[ 00b]  Rename to harmonised column names\n")
source("00b_rename_harmonised_columns/00b_rename_harmonised_columns.r")

# -- 16  NA reason coding -------------------------------------------------------
# Runs only if cfg$neotree_scripts_dir exists; otherwise a warning is logged.
cat("[ 16 ]  NA reason coding\n")
if (dir.exists(cfg$neotree_scripts_dir)) {
  source("16_na_reason_coding/16_na_reason_coding.r")
} else {
  log_warn(paste(
    "Module 16 skipped: neotree_scripts_dir not found (%s).",
    "Set NEOTREE_SCRIPTS_DIR in 00_setup.r to enable NA reason coding."
  ), cfg$neotree_scripts_dir)
}

# -- Concatenate the .txt module reports into 00_pipeline_report.txt -----------
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
