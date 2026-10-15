# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 14: Datetime Feature Validation
# =============================================================================
# PURPOSE:
#   Validates the datetime columns and derives hepbdate_date.
#
# METHOD:
#   1. Each value is parsed by parse_datetime_by_shape() (00_setup.r), the
#      parser also used by Module 09:
#        ISO          "2023-10-19 22:00:00", "2023-10-19T22:00:00Z" (a "Z" or UTC
#                     offset is dropped; the time is kept as written)
#        day first    "19/10/2023", "19-10-2023", "19.10.2023" (two-digit year =
#                     20yy; not read as month/day/year)
#        month name   "October 19, 2023", "19 October 2023, 10:00 PM", "19-Oct-2023"
#      Values that do not parse (free text, bare digit strings) become NA.
#   2. hepbdate_date: the hepbdate column can hold both Y/N answers and dates,
#      because some scripts use the key for a date question and others for a
#      yes/no question followed by a date.  hepbdate stays categorical (Module
#      13 sets date-shaped values of a categorical column to NA).  The dates
#      are parsed into the datetime column hepbdate_date, created whenever a
#      hepbdate column that is not itself typed datetime is present.
#   3. One row per (uid, facility) is kept in the datetime sub-frame.
#
# INPUTS:
#   df   - data.frame after Module 10
#   cfg  - configuration list ($dt feature vector, $data_source)
#
# OUTPUTS:
#   df_datetime  - validated datetime sub-frame (facility, uid, uniquekey + dt cols)
#   Report       - cfg$report_dir/14_datetime_validation_report.txt
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

  invalid_count    <- 0L
  converted_count  <- 0L

  for (col in setdiff(dt_cols, key_cols)) {
    if (!col %in% names(df_dt)) next

    raw      <- as.character(df_dt[[col]])
    parsed   <- parse_datetime_by_shape(raw)
    attr(parsed, "counts") <- NULL

    n_ok      <- sum(!is.na(parsed))
    n_invalid <- sum(is.na(parsed) & !is.na(raw) & raw != "" & raw != "NA")

    converted_count <- converted_count + n_ok
    invalid_count   <- invalid_count   + n_invalid

    df_dt[[col]] <- parsed

    if (n_invalid > 0) {
      # Counts only: values are never written to the log.
      log_info(
        "  validate_datetime: '%s' - %d invalid value(s) -> NA.",
        col, n_invalid
      )
    }
  }

  # -- Derived column: hepbdate_date ---------------------------------------------
  # Dates held in the mixed Y/N-and-date column hepbdate (see header).
  hepb_src  <- intersect(c("hepbdate.value", "hepbdate"), names(df))
  hepb_src  <- setdiff(hepb_src, dt_cols)
  n_hepb_dt <- NA_integer_
  if (length(hepb_src) > 0 && !"hepbdate_date" %in% names(df_dt)) {
    hepb_parsed <- parse_datetime_by_shape(df[[hepb_src[1]]])
    attr(hepb_parsed, "counts") <- NULL
    df_dt[["hepbdate_date"]] <- hepb_parsed
    n_hepb_dt <- sum(!is.na(hepb_parsed))
    log_info("  validate_datetime: hepbdate_date derived from '%s': %d date(s).",
             hepb_src[1], n_hepb_dt)
  }

  # Deduplication
  n_before <- nrow(df_dt)
  # Row key: datasets that keep every visit (cfg$skip_dedup_stage2 = TRUE) are
  # keyed on uid + facility + uniquekey, the others on uid + facility.
  dedup_keys <- intersect(if (isTRUE(cfg$skip_dedup_stage2)) c("uid", "facility", "uniquekey") else c("uid", "facility"),
                          names(df_dt))
  df_dt    <- dplyr::distinct(df_dt, dplyr::across(dplyr::all_of(dedup_keys)), .keep_all = TRUE)
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
        if (!is.na(n_hepb_dt))
          sprintf("hepbdate_date derived       : %d date(s) taken from the mixed Y/N-and-date column hepbdate",
                  n_hepb_dt),
        "",
        "Datetime parsing            : by shape of each value (ISO, day first, month name); see Module 09 report"
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
