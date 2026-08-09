# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 14: Datetime Feature Validation
# =============================================================================
# PURPOSE:
#   Validates all datetime columns by:
#
#   1. STANDARDISATION - converts all datetime values to a consistent POSIXct
#      format, trying multiple common date/datetime patterns.
#   2. INVALID ENTRY REMOVAL - any string that cannot be parsed as a valid
#      datetime is set to NA (NaT equivalent in R).
#   3. DEDUPLICATION - applied to the validated datetime sub-frame.
#
# SUPPORTED INPUT FORMATS:
#   "2023-10-19 22:00:00", "2023-10-19T22:00:00Z",
#   "19/10/2023", "October 19, 2023", "19-Oct-2023", etc.
#
# METABASE DATETIME HANDLING:
#   Metabase exports datetime values in a human-readable format such as
#   "March 2, 2026, 12:33 AM" instead of the ISO format used by direct
#   database exports ("2021-10-08 13:51:01").  When cfg$data_source ==
#   "metabase", additional lubridate parse orders covering this format are
#   appended so that Metabase datetime strings are correctly parsed rather
#   than silently coerced to NA.
#
# INPUTS:
#   df   - data.frame after Module 10
#   cfg  - configuration list ($dt feature vector, $data_source)
#
# OUTPUTS:
#   df_datetime  - validated datetime sub-frame (facility, uid, uniquekey + dt cols)
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("14_datetime_validation/14_datetime_validation.r")
# =============================================================================

source("00_setup/00_setup.r")

# -- Function ------------------------------------------------------------------

#' Validate Datetime Features
#'
#' @param df   Full data.frame from Module 10.
#' @param cfg  Config list with $dt feature vector and $data_source.
#' @param report_filepath Optional path for a text report.
#' @return Validated datetime sub-frame.
validate_datetime <- function(df, cfg, report_filepath = NULL) {

  key_cols <- c("facility", "uid", "uniquekey")
  dt_cols  <- intersect(cfg$dt, names(df))
  keep_cols <- unique(c(key_cols, dt_cols))
  df_dt    <- df[, keep_cols[keep_cols %in% names(df)], drop = FALSE]

  # -- Build datetime parse orders ---------------------------------------------
  # Standard ISO / numeric formats (cover direct database exports)
  parse_orders <- c(
    "ymd HMS", "ymd HM", "ymd H", "ymd",
    "dmy HMS", "dmy HM", "dmy",
    "mdy HMS", "mdy HM", "mdy",
    "Ymd HMS", "dmY HMS",
    "BdY",     # "October 19, 2023"
    "dBY"      # "19 October 2023"
  )

  # Metabase exports datetimes in human-readable form, e.g.:
  #   "March 2, 2026, 12:33 AM"   ->  order "BdY IMp"
  #   "March 2, 2026"             ->  order "BdY"   (already covered above)
  #   "2 March 2026, 12:33 AM"    ->  order "dBY IMp"
  #   "2 March 2026"              ->  order "dBY"   (already covered above)
  # These are appended after the ISO patterns so ISO remains preferred for
  # database exports.  lubridate handles separators (commas, spaces) flexibly.
  if (isTRUE(cfg$data_source == "metabase")) {
    parse_orders <- c(parse_orders,
                      "BdY IMp",   # "March 2, 2026, 12:33 AM"
                      "BdY HMp",   # alternative 24-h fallback
                      "dBY IMp",   # "2 March 2026, 12:33 AM"
                      "dBY HMp")
  }

  invalid_count    <- 0L
  converted_count  <- 0L

  for (col in setdiff(dt_cols, key_cols)) {
    if (!col %in% names(df_dt)) next

    raw      <- as.character(df_dt[[col]])
    # Remove trailing "Z" timezone indicator for easier parsing
    cleaned  <- trimws(sub("Z$", "", raw))

    parsed   <- suppressWarnings(
      lubridate::parse_date_time(cleaned, orders = parse_orders, quiet = TRUE)
    )

    n_ok      <- sum(!is.na(parsed))
    n_invalid <- sum(is.na(parsed) & !is.na(raw) & raw != "" & raw != "NA")

    converted_count <- converted_count + n_ok
    invalid_count   <- invalid_count   + n_invalid

    df_dt[[col]] <- parsed

    if (n_invalid > 0) {
      bad_examples <- unique(raw[is.na(parsed) & !is.na(raw) & raw != ""])
      log_info(
        "  validate_datetime: '%s' - %d invalid value(s) -> NA. Examples: [%s]",
        col, n_invalid,
        paste(head(bad_examples, 3), collapse = " | ")
      )
    }
  }

  # Deduplication
  n_before <- nrow(df_dt)
  df_dt    <- dplyr::distinct(df_dt, uid, facility, .keep_all = TRUE)
  n_dedup  <- n_before - nrow(df_dt)

  log_info(
    "validate_datetime: %d parsed successfully | %d invalid -> NA | %d duplicates removed.",
    converted_count, invalid_count, n_dedup
  )

  # Optional report
  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c(
        "Module 14 - Datetime Validation Report",
        "=======================================",
        sprintf("Run timestamp               : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                     : %s", toupper(cfg$country)),
        sprintf("Dataset                     : %s", cfg$dataset),
        sprintf("Data source                 : %s", cfg$data_source),
        "",
        sprintf("Datetime columns checked    : %d", length(setdiff(dt_cols, key_cols))),
        sprintf("Values successfully parsed  : %d", converted_count),
        sprintf("Invalid values set to NA    : %d", invalid_count),
        sprintf("Duplicate rows removed      : %d", n_dedup),
        sprintf("Final datetime rows         : %d", nrow(df_dt)),
        "",
        if (isTRUE(cfg$data_source == "metabase"))
          "Metabase datetime orders    : BdY IMp, BdY HMp, dBY IMp, dBY HMp added"
        else
          "Metabase datetime orders    : not added (database source)"
      )
      writeLines(lines, report_filepath)
    }, error = function(e) {
      log_warn("Could not write datetime validation report: %s", e$message)
    })
  }

  return(df_dt)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "14_datetime_validation_report.txt") else NULL

df_datetime <- validate_datetime(df, cfg, report_filepath = report_path)
log_info("Module 14 complete. Datetime sub-frame: %d rows x %d cols.",
         nrow(df_datetime), ncol(df_datetime))
