# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 12: Boolean Feature Validation
# =============================================================================
# PURPOSE:
#   Validates and standardises the boolean columns.
#
# METHOD:
#   Values are trimmed and lowercased, then mapped to TRUE or FALSE using
#   NEOTREE_TRUE_TOKENS / NEOTREE_FALSE_TOKENS.  Values that match neither
#   list are set to NA.  One row per (uid, facility) is kept in the boolean
#   sub-frame.
#
# INPUTS:
#   df   - data.frame after Module 10
#   cfg  - configuration list (bool feature vector)
#
# OUTPUTS:
#   df_boolean  - validated boolean sub-frame (facility, uid, uniquekey + bool cols)
#   Report      - cfg$report_dir/12_boolean_validation_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("12_boolean_validation/12_boolean_validation.r")
# =============================================================================

source("00_setup/00_setup.r")

# -- Constants -----------------------------------------------------------------
# Defined in 00_setup.r and shared with Module 09, so both modules accept the
# same representations.
TRUE_TOKENS  <- NEOTREE_TRUE_TOKENS
FALSE_TOKENS <- NEOTREE_FALSE_TOKENS

# -- Function ------------------------------------------------------------------

#' Validate and Standardise Boolean Features
#'
#' @param df   Full data.frame from Module 10.
#' @param cfg  Config list with $bool feature vector.
#' @param report_filepath Optional path for a text report.
#' @return Validated boolean sub-frame.
validate_boolean <- function(df, cfg, report_filepath = NULL) {

  key_cols   <- c("facility", "uid", "uniquekey")
  bool_cols  <- intersect(cfg$bool, names(df))
  keep_cols  <- unique(c(key_cols, bool_cols))
  df_bool    <- df[, keep_cols[keep_cols %in% names(df)], drop = FALSE]

  invalid_count  <- 0L
  converted_count <- 0L

  for (col in setdiff(bool_cols, key_cols)) {
    if (!col %in% names(df_bool)) next

    raw  <- as.character(df_bool[[col]])
    s    <- trimws(tolower(raw))

    result <- dplyr::case_when(
      s %in% TRUE_TOKENS  ~ TRUE,
      s %in% FALSE_TOKENS ~ FALSE,
      TRUE                ~ NA
    )

    n_invalid   <- sum(is.na(result) & !is.na(raw) & raw != "NA" & raw != "")
    n_converted <- sum(!is.na(result))

    invalid_count   <- invalid_count   + n_invalid
    converted_count <- converted_count + n_converted

    if (n_invalid > 0) {
      # Counts only: values are never written to the log.
      n_distinct <- length(unique(raw[is.na(result) & !is.na(raw) & raw != "NA" & raw != ""]))
      log_info(
        "  validate_boolean: '%s' - %d invalid value(s) set to NA (%d distinct).",
        col, n_invalid, n_distinct
      )
    }

    df_bool[[col]] <- result
  }

  # Deduplication
  n_before  <- nrow(df_bool)
  # Row key: datasets that keep every visit (cfg$skip_dedup_stage2 = TRUE), and
  # admissions and discharges in episode mode (cfg$dedup_episode = TRUE), are
  # keyed on uid + facility + uniquekey, the others on uid + facility.
  dedup_keys <- intersect(if (isTRUE(cfg$skip_dedup_stage2) || isTRUE(cfg$dedup_episode)) c("uid", "facility", "uniquekey") else c("uid", "facility"),
                          names(df_bool))
  df_bool   <- dplyr::distinct(df_bool, dplyr::across(dplyr::all_of(dedup_keys)), .keep_all = TRUE)
  n_dedup   <- n_before - nrow(df_bool)

  log_info(
    "validate_boolean: %d values standardised | %d invalid -> NA | %d duplicates removed.",
    converted_count, invalid_count, n_dedup
  )

  # Optional report
  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c("Boolean Validation Report", "=========================",
        sprintf("Values standardised to TRUE/FALSE : %d", converted_count),
        sprintf("Invalid values set to NA          : %d", invalid_count),
        sprintf("Duplicate rows removed            : %d", n_dedup),
        sprintf("Final boolean rows                : %d", nrow(df_bool))
      )
      writeLines(lines, report_filepath)
    }, error = function(e) {
      log_warn("Could not write boolean validation report: %s", e$message)
    })
  }

  return(df_bool)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "12_boolean_validation_report.txt") else NULL

df_boolean <- validate_boolean(df, cfg, report_filepath = report_path)
log_info("Module 12 complete. Boolean sub-frame: %d rows x %d cols.",
         nrow(df_boolean), ncol(df_boolean))
