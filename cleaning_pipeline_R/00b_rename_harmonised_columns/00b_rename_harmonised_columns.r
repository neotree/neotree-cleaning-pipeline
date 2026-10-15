# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 00b: Rename Columns to Harmonised Names
# =============================================================================
# PURPOSE:
#   Renames the columns of the final dataset from pipeline names (lowercase
#   question_key form, e.g. "admissionweight.value") to snake_case harmonised
#   names (e.g. "admission_weight_kg").  Runs after Module 15 and only when
#   cfg$save_harmonised is TRUE.
#
# METHOD:
#   Harmonised names come from the data dictionary's `harmonised_variable_name`
#   column, loaded by 00_setup into `cfg$harmonised_map` (a named character
#   vector: names = question_key, values = harmonised name).
#   For each column:
#     1. Strip the ".valuedischarge" / ".value" suffix to get the question_key.
#     2. Look it up in cfg$harmonised_map.
#     3. If found, rename to the harmonised name; otherwise keep the name.
#
# INPUTS:
#   df_clean           - final dataset from Module 15
#   cfg$harmonised_map - named vector from 00_setup.r
#
# OUTPUTS:
#   df_harmonised  - dataset with harmonised column names
#   CSV + RDS      - Module 15 output paths with a "_harmonised" suffix
#   Report         - cfg$report_dir/00b_harmonised_rename_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   # Run Module 15 first, then:
#   source("00b_rename_harmonised_columns/00b_rename_harmonised_columns.r")
# =============================================================================

source("00_setup/00_setup.r")

# -- Function ------------------------------------------------------------------

#' Rename Columns Using the Harmonised Name Map
#'
#' @param df             A data.frame (clean dataset from Module 15).
#' @param harmonised_map Named character vector: question_key -> harmonised name.
#' @param report_filepath Optional path for a text report.
#' @return               Data.frame with harmonised column names.
rename_harmonised <- function(df, harmonised_map, report_filepath = NULL) {

  original_names <- names(df)
  new_names      <- original_names
  renamed_log    <- character(0)
  unchanged_log  <- character(0)

  for (i in seq_along(original_names)) {
    col   <- original_names[i]

    # Derive base question_key: strip .value / .valuedischarge suffixes
    base  <- sub("\\.valuedischarge$", "", col)
    base  <- sub("\\.value$",          "", base)

    if (base %in% names(harmonised_map)) {
      new_col       <- harmonised_map[[base]]
      new_names[i]  <- new_col
      if (new_col != col)
        renamed_log <- c(renamed_log,
                         sprintf("  %-45s -> %s", col, new_col))
    } else {
      unchanged_log <- c(unchanged_log, col)
    }
  }

  names(df) <- new_names
  n_renamed <- length(renamed_log)

  log_info(
    "rename_harmonised: %d of %d columns renamed to harmonised names | %d unchanged",
    n_renamed, ncol(df), length(unchanged_log)
  )

  # -- Write report ------------------------------------------------------------
  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c(
        "Module 00b - Harmonised Column Rename Report",
        "=============================================",
        sprintf("Run timestamp           : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                 : %s", toupper(cfg$country)),
        sprintf("Dataset                 : %s", cfg$dataset),
        "",
        sprintf("Total columns           : %d", ncol(df)),
        sprintf("Columns renamed         : %d", n_renamed),
        sprintf("Columns unchanged       : %d", length(unchanged_log)),
        ""
      )

      if (n_renamed > 0) {
        lines <- c(lines,
          "=== Renamed Columns (original -> harmonised) ===",
          renamed_log,
          "")
      }

      if (length(unchanged_log) > 0) {
        lines <- c(lines,
          "=== Unchanged Columns (no harmonised name in dictionary) ===",
          paste0("  ", unchanged_log),
          "")
      }

      writeLines(lines, report_filepath)
    }, error = function(e) {
      log_warn("Could not write Module 00b report: %s", e$message)
    })
  }

  return(df)
}

# -- Run -----------------------------------------------------------------------
if (!exists("df_clean"))
  stop("df_clean not found. Run Module 15 (15_final_merge_output) first.")

if (!isTRUE(cfg$save_harmonised)) {
  log_info("Module 00b skipped (SAVE_HARMONISED = FALSE). df_harmonised not produced.")
} else {

  report_path <- if (!is.null(cfg$report_dir))
    file.path(cfg$report_dir, "00b_harmonised_rename_report.txt") else NULL

  df_harmonised <- rename_harmonised(
    df              = df_clean,
    harmonised_map  = cfg$harmonised_map,
    report_filepath = report_path
  )

  # -- Save harmonised outputs -------------------------------------------------
  harm_csv <- sub("\\.csv$", "_harmonised.csv", cfg$output_csv)
  harm_rds <- sub("\\.rds$", "_harmonised.rds", cfg$output_rds)

  # PII guard: checked once for both files below (same object).
  assert_pii_removed(df_harmonised, stage = "00b_harmonised_output")

  tryCatch({
    readr::write_csv(df_harmonised, harm_csv, na = "")
    log_info("Harmonised CSV saved: %s", harm_csv)
  }, error = function(e) log_warn("Could not save harmonised CSV: %s", e$message))

  tryCatch({
    saveRDS(df_harmonised, harm_rds)
    log_info("Harmonised RDS saved: %s", harm_rds)
  }, error = function(e) log_warn("Could not save harmonised RDS: %s", e$message))

  log_info(
    "Module 00b complete. Harmonised dataset: %d rows x %d cols.",
    nrow(df_harmonised), ncol(df_harmonised)
  )

}
