# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 14a: Resolve Missing neolab datebct from Admissions
# =============================================================================
# PURPOSE:
#   For the neolab (blood culture) dataset, some rows have missing or
#   unparseable DateBCT values (date blood culture taken).  When datebct.value
#   is NA after Module 14's datetime validation, this module attempts to
#   resolve a proxy date by joining to the raw admissions file on uid +
#   facility, using datetimeadmission as the date.
#
#   Blood cultures are typically taken at or shortly after admission, so
#   datetimeadmission is a clinically reasonable proxy.
#
# WHAT THIS MODULE ADDS:
#   datebct_resolved  (POSIXct) - best available blood culture date:
#                                  datebct.value if present, otherwise
#                                  datetimeadmission from admissions;
#                                  NA if neither is available.
#   datebct_source    (character) - provenance flag:
#                                  "original"       datebct.value was present
#                                  "from_admission" resolved from admissions
#                                  NA               no date available
#
# DESIGN NOTES:
#   - datebct.value is never modified; datebct_resolved is a NEW column.
#   - Runs only when cfg$dataset == "neolab" AND
#     cfg$resolve_neolab_datebct == TRUE (default TRUE; set FALSE to skip).
#   - The raw admissions file is derived automatically from cfg$csv_filepath
#     by substituting "neolab" with "admissions" in the filename.
#     If the file is absent, datebct_resolved mirrors datebct.value and a
#     warning is logged.
#   - If the admissions file contains multiple records for the same
#     uid + facility, the record with the earliest non-NA datetimeadmission
#     is used.
#
# INPUTS:
#   df_datetime  - validated datetime sub-frame produced by Module 14
#   cfg          - configuration list ($dataset, $resolve_neolab_datebct,
#                  $csv_filepath, $data_source, $report_dir)
#
# OUTPUTS:
#   df_datetime  - same frame with datebct_resolved and datebct_source appended
#
# USAGE:
#   source("00_setup/00_setup.r")
#   # ... run modules 11-14 first, then:
#   source("14a_resolve_neolab_datebct/14a_resolve_neolab_datebct.r")
# =============================================================================

source("00_setup/00_setup.r")

# -- Function ------------------------------------------------------------------

#' Resolve Missing neolab datebct Values from Raw Admissions File
#'
#' @param df_datetime     Datetime sub-frame from Module 14.
#' @param cfg             Config list.
#' @param report_filepath Optional path for a text report.
#' @return df_datetime with datebct_resolved and datebct_source columns added.
resolve_neolab_datebct <- function(df_datetime, cfg, report_filepath = NULL) {

  # -- Guard: only runs for neolab, and only when flag is set ------------------
  if (!identical(cfg$dataset, "neolab")) {
    log_info("Module 14a: skipped (dataset = '%s'; only applies to neolab).",
             cfg$dataset)
    return(df_datetime)
  }

  if (!isTRUE(cfg$resolve_neolab_datebct)) {
    log_info("Module 14a: skipped (resolve_neolab_datebct = FALSE in config).")
    return(df_datetime)
  }

  # -- Guard: datebct.value must exist ----------------------------------------
  if (!"datebct.value" %in% names(df_datetime)) {
    log_warn(
      "Module 14a: 'datebct.value' not found in df_datetime. Adding empty resolution columns."
    )
    df_datetime$datebct_resolved <- as.POSIXct(NA)
    df_datetime$datebct_source   <- NA_character_
    return(df_datetime)
  }

  n_total          <- nrow(df_datetime)
  n_missing_before <- sum(is.na(df_datetime[["datebct.value"]]))

  log_info(
    "Module 14a: %d/%d datebct.value values are NA -- attempting resolution from admissions.",
    n_missing_before, n_total
  )

  if (n_missing_before == 0L) {
    log_info("Module 14a: no missing values; adding datebct_resolved = datebct.value for all rows.")
    df_datetime$datebct_resolved <- df_datetime[["datebct.value"]]
    df_datetime$datebct_source   <- "original"
    if (!is.null(report_filepath) && nzchar(report_filepath))
      .write_14a_report(report_filepath, cfg, cfg$csv_filepath,
                        n_missing_before, n_total, n_total, 0L, 0L)
    return(df_datetime)
  }

  # -- Derive admissions file path --------------------------------------------
  # Pattern: replace the "_neolab_" or "_neolab." segment in the filename.
  # Handles both  input/mwi_db_neolab_20260501.csv
  #          and  input/mwi_mb_neolab_2026-05-01.csv
  admissions_path <- sub(
    "(^|[/_])neolab([_./])",
    "\\1admissions\\2",
    cfg$csv_filepath
  )

  if (!file.exists(admissions_path)) {
    log_warn(
      paste(
        "Module 14a: admissions file not found at '%s'.",
        "datebct_resolved will mirror datebct.value for all rows."
      ),
      admissions_path
    )
    df_datetime$datebct_resolved <- df_datetime[["datebct.value"]]
    df_datetime$datebct_source   <- ifelse(
      !is.na(df_datetime[["datebct.value"]]), "original", NA_character_
    )
    if (!is.null(report_filepath) && nzchar(report_filepath))
      .write_14a_report(report_filepath, cfg, admissions_path,
                        n_missing_before, n_total, 0L, n_missing_before, 0L)
    return(df_datetime)
  }

  log_info("Module 14a: admissions lookup file: %s", admissions_path)

  # -- Read header row to locate columns -------------------------------------
  adm_header <- tryCatch(
    readr::read_csv(admissions_path, n_max = 0L,
                    show_col_types = FALSE, col_types = readr::cols()),
    error = function(e) {
      log_warn("Module 14a: could not read admissions file header: %s", e$message)
      NULL
    }
  )

  if (is.null(adm_header)) {
    df_datetime$datebct_resolved <- df_datetime[["datebct.value"]]
    df_datetime$datebct_source   <- ifelse(
      !is.na(df_datetime[["datebct.value"]]), "original", NA_character_
    )
    return(df_datetime)
  }

  # Normalise names: lowercase, strip spaces (mirrors Module 01's clean_names)
  adm_cols_norm <- tolower(gsub("[[:space:]]", "", names(adm_header)))

  find_col <- function(pattern, cols_norm, cols_orig) {
    idx <- grep(pattern, cols_norm)
    if (length(idx) == 0L) return(NULL)
    cols_orig[idx[1L]]
  }

  uid_col      <- find_col("^uid$",                       adm_cols_norm, names(adm_header))
  facility_col <- find_col("^facility$",                  adm_cols_norm, names(adm_header))
  dtadm_col    <- find_col("^datetimeadmission\\.value$", adm_cols_norm, names(adm_header))

  # Fallback: try without .value suffix
  if (is.null(dtadm_col))
    dtadm_col <- find_col("^datetimeadmission$", adm_cols_norm, names(adm_header))

  if (is.null(uid_col) || is.null(facility_col)) {
    log_warn(
      "Module 14a: 'uid' and/or 'facility' columns not found in admissions file. Skipping."
    )
    df_datetime$datebct_resolved <- df_datetime[["datebct.value"]]
    df_datetime$datebct_source   <- ifelse(
      !is.na(df_datetime[["datebct.value"]]), "original", NA_character_
    )
    return(df_datetime)
  }

  if (is.null(dtadm_col)) {
    log_warn(
      "Module 14a: 'DateTimeAdmission.value' column not found in admissions file. Skipping."
    )
    df_datetime$datebct_resolved <- df_datetime[["datebct.value"]]
    df_datetime$datebct_source   <- ifelse(
      !is.na(df_datetime[["datebct.value"]]), "original", NA_character_
    )
    return(df_datetime)
  }

  # -- Read only the three needed columns ------------------------------------
  adm_df <- tryCatch(
    readr::read_csv(
      admissions_path,
      col_select    = dplyr::all_of(c(uid_col, facility_col, dtadm_col)),
      col_types     = readr::cols(.default = readr::col_character()),
      show_col_types = FALSE
    ),
    error = function(e) {
      log_warn("Module 14a: error reading admissions columns: %s", e$message)
      NULL
    }
  )

  if (is.null(adm_df)) {
    df_datetime$datebct_resolved <- df_datetime[["datebct.value"]]
    df_datetime$datebct_source   <- ifelse(
      !is.na(df_datetime[["datebct.value"]]), "original", NA_character_
    )
    return(df_datetime)
  }

  # Normalise column names to lowercase (no spaces)
  names(adm_df) <- tolower(gsub("[[:space:]]", "", names(adm_df)))

  # Rename the admission datetime to a clean internal name
  dtadm_norm <- tolower(gsub("[[:space:]]", "", dtadm_col))
  names(adm_df)[names(adm_df) == dtadm_norm] <- ".adm_datetime_raw"

  # -- Parse datetimeadmission -----------------------------------------------
  parse_orders <- c(
    "ymd HMS", "ymd HM", "ymd H", "ymd",
    "dmy HMS", "dmy HM", "dmy",
    "mdy HMS", "mdy HM", "mdy"
  )
  if (isTRUE(cfg$data_source == "metabase")) {
    parse_orders <- c(parse_orders,
                      "BdY IMp", "BdY HMp",
                      "dBY IMp", "dBY HMp")
  }

  adm_df$.adm_datetime <- suppressWarnings(
    lubridate::parse_date_time(
      trimws(sub("Z$", "", adm_df$.adm_datetime_raw)),
      orders = parse_orders,
      quiet  = TRUE
    )
  )
  adm_df$.adm_datetime_raw <- NULL

  n_adm_parsed <- sum(!is.na(adm_df$.adm_datetime))
  log_info(
    "Module 14a: admissions file read: %d rows, %d with parsed datetimeadmission.",
    nrow(adm_df), n_adm_parsed
  )

  # Deduplicate admissions: keep earliest non-NA datetime per uid + facility.
  # This prevents fan-out in the neolab join if a patient has multiple admission
  # records (e.g. readmissions -- unlikely but defensive).
  adm_df <- adm_df %>%
    dplyr::arrange(uid, facility, is.na(.adm_datetime), .adm_datetime) %>%
    dplyr::distinct(uid, facility, .keep_all = TRUE)

  # -- Left-join admissions datetime into df_datetime ------------------------
  df_datetime <- dplyr::left_join(
    df_datetime,
    adm_df,
    by = c("uid", "facility")
  )

  # -- Populate datebct_resolved and datebct_source --------------------------
  df_datetime$datebct_resolved <- dplyr::if_else(
    !is.na(df_datetime[["datebct.value"]]),
    df_datetime[["datebct.value"]],  # prefer original parsed value
    df_datetime$.adm_datetime        # fall back to admission datetime
  )

  df_datetime$datebct_source <- dplyr::case_when(
    !is.na(df_datetime[["datebct.value"]]) ~ "original",
    !is.na(df_datetime$.adm_datetime)      ~ "from_admission",
    TRUE                                   ~ NA_character_
  )

  # Clean up the join helper column
  df_datetime$.adm_datetime <- NULL

  # -- Summary ---------------------------------------------------------------
  n_original   <- sum(df_datetime$datebct_source == "original",       na.rm = TRUE)
  n_resolved   <- sum(df_datetime$datebct_source == "from_admission",  na.rm = TRUE)
  n_unresolved <- sum(is.na(df_datetime$datebct_source))

  log_info(
    paste(
      "Module 14a: datebct_resolved summary --",
      "original: %d | resolved from admission: %d | still NA: %d"
    ),
    n_original, n_resolved, n_unresolved
  )

  if (n_resolved > 0)
    log_info(
      "Module 14a: %d row(s) with missing datebct resolved using datetimeadmission.",
      n_resolved
    )

  if (n_unresolved > 0)
    log_info(
      paste(
        "Module 14a: %d row(s) remain with no datebct and no matching admission record.",
        "datebct_resolved is NA for these rows."
      ),
      n_unresolved
    )

  # -- Optional report -------------------------------------------------------
  if (!is.null(report_filepath) && nzchar(report_filepath))
    .write_14a_report(report_filepath, cfg, admissions_path,
                      n_missing_before, n_total,
                      n_original, n_resolved, n_unresolved)

  return(df_datetime)
}


# -- Internal: write report file -----------------------------------------------

.write_14a_report <- function(filepath, cfg, admissions_path,
                               n_missing_before, n_total,
                               n_original, n_resolved, n_unresolved) {
  tryCatch({
    lines <- c(
      "Module 14a - Neolab datebct Resolution Report",
      "===============================================",
      sprintf("Run timestamp                    : %s",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      sprintf("Country                          : %s", toupper(cfg$country)),
      sprintf("Dataset                          : %s", cfg$dataset),
      sprintf("Data source                      : %s", cfg$data_source),
      sprintf("Neolab input file                : %s", cfg$csv_filepath),
      sprintf("Admissions lookup file           : %s", admissions_path),
      "",
      sprintf("Total rows in datetime sub-frame : %d", n_total),
      sprintf("datebct.value missing before     : %d", n_missing_before),
      "",
      "datebct_resolved summary",
      "------------------------",
      sprintf("  'original'      (datebct present)        : %d", n_original),
      sprintf("  'from_admission' (resolved from admissions): %d", n_resolved),
      sprintf("  NA               (no date available)      : %d", n_unresolved),
      "",
      "Columns added to df_datetime",
      "-----------------------------",
      "  datebct_resolved  (POSIXct) -- best available blood culture date",
      "  datebct_source    (character) -- 'original' | 'from_admission' | NA",
      "",
      "Note: datebct.value is unchanged. datebct_resolved is a new derived column."
    )
    writeLines(lines, filepath)
  }, error = function(e) {
    log_warn("Could not write Module 14a report: %s", e$message)
  })
}


# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "14a_resolve_neolab_datebct_report.txt") else NULL

df_datetime <- resolve_neolab_datebct(df_datetime, cfg,
                                       report_filepath = report_path)
log_info("Module 14a complete. df_datetime: %d rows x %d cols.",
         nrow(df_datetime), ncol(df_datetime))
