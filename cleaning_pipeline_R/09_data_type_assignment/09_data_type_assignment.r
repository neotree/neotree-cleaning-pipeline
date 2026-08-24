# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 09: Data Type Assignment
# =============================================================================
# PURPOSE:
#   After structural cleaning (Modules 01-08), all columns are character.
#   This module assigns correct R types using cfg feature lists:
#     - Numeric    -> as.numeric()
#     - Boolean    -> logical (TRUE/FALSE/NA)
#     - Categorical -> factor
#     - Object     -> character
#     - Datetime   -> POSIXct via lubridate
#   Columns not found in any list are kept as character.
#
# METABASE DATETIME HANDLING:
#   Metabase exports datetime values in a human-readable format such as
#   "March 2, 2026, 12:33 AM" instead of the ISO format used by direct
#   database exports ("2021-10-08 13:51:01").  When cfg$data_source ==
#   "metabase", additional lubridate parse orders covering this format are
#   appended to the standard order list so that Metabase datetime strings
#   are correctly parsed rather than silently coerced to NA.
#
#   This mirrors the reference Jupyter pipeline, which uses
#   pd.to_datetime(errors='coerce') -- a format-agnostic parser that handles
#   both ISO and human-readable strings transparently.
#
# INPUTS:
#   df   - data.frame after Module 08
#   cfg  - configuration list from 00_setup.R
#
# OUTPUTS:
#   df   - data.frame with correct column data types
#
# REPORT:
#   reports/09_data_type_assignment_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("09_data_type_assignment/09_data_type_assignment.r")
# =============================================================================

source("00_setup/00_setup.r")

base_name <- function(col) {
  col <- sub("\\.value$", "", col)
  col <- sub("\\.valuedischarge$", "", col)
  return(col)
}

to_boolean <- function(x) {
  s <- trimws(tolower(as.character(x)))
  dplyr::case_when(
    s %in% c("true",  "yes", "y", "1") ~ TRUE,
    s %in% c("false", "no",  "n", "0") ~ FALSE,
    TRUE                                ~ NA
  )
}

#' Assign Data Types to All Columns
#'
#' @param df              A data.frame.
#' @param cfg             Configuration list.
#' @param report_filepath Optional path for a text report.
#' @return                Data.frame with correctly typed columns.
assign_data_types <- function(df, cfg, report_filepath = NULL) {

  col_names <- names(df)

  in_list <- function(col, lst) {
    if (col %in% c("facility", "uid", "uniquekey")) return(FALSE)
    col %in% lst ||
    base_name(col) %in% lst ||
    paste0(base_name(col), ".value") %in% lst
  }

  counts <- list(numeric = 0L, boolean = 0L, categorical = 0L,
                 object = 0L, datetime = 0L, unchanged = 0L)
  type_map  <- character(length(col_names))
  names(type_map) <- col_names
  comma_stripped <- 0L   # values whose comma thousands-separator was removed
  digits_recovered <- 0L # values recovered by the embedded-digit fallback below

  # -- Build datetime parse orders ---------------------------------------------
  # Standard ISO / numeric formats (cover direct database exports)
  dt_orders <- c(
    "ymd HMS", "ymd HM", "ymd H", "ymd",
    "dmy HMS", "dmy HM", "dmy",
    "mdy HMS", "mdy HM", "mdy",
    "Ymd HMS"
  )

  # Metabase exports datetimes in human-readable form, e.g.:
  #   "March 2, 2026, 12:33 AM"   ->  order "BdYIMp"
  #   "March 2, 2026"             ->  order "BdY"   (date-only fallback)
  #   "2 March 2026, 12:33 AM"    ->  order "dBYIMp"
  #   "2 March 2026"              ->  order "dBY"   (date-only fallback)
  # These are appended after the ISO patterns so ISO remains preferred for
  # database exports.  lubridate handles separators (commas, spaces) flexibly.
  if (isTRUE(cfg$data_source == "metabase")) {
    dt_orders <- c(dt_orders,
                   "BdY IMp",   # "March 2, 2026, 12:33 AM"
                   "BdY HMp",   # alternative 24-h fallback
                   "BdY",       # "March 2, 2026" (date only)
                   "dBY IMp",   # "2 March 2026, 12:33 AM"
                   "dBY HMp",
                   "dBY")       # "2 March 2026"
  }

  for (col in col_names) {
    if (in_list(col, cfg$num)) {
      raw_chr <- as.character(df[[col]])
      # Metabase exports format numbers with thousands-separator commas ("3,500").
      # Strip them before coercion so values like "3,500" parse to 3500, not NA.
      if (isTRUE(cfg$data_source == "metabase")) {
        has_comma <- grepl(",", raw_chr, fixed = TRUE) & !is.na(raw_chr)
        raw_chr[has_comma] <- gsub(",", "", raw_chr[has_comma], fixed = TRUE)
        comma_stripped <- comma_stripped + sum(has_comma)
      }
      parsed <- suppressWarnings(as.numeric(raw_chr))
      # Fallback: some fields mix bare numbers with coded/free-text variants of
      # the same value (e.g. "ANC4", "4 ANC visits" alongside plain "4" for
      # antenatalcare). A direct as.numeric() on those returns NA even though
      # the intended count is unambiguous. Recover it by extracting the first
      # embedded digit run -- this only ever fills in values that already
      # failed to parse; it can never overwrite a value that parsed cleanly.
      needs_fallback <- is.na(parsed) & !is.na(raw_chr) & raw_chr != ""
      if (any(needs_fallback)) {
        extracted <- stringr::str_extract(raw_chr[needs_fallback], "[0-9]+")
        recovered_vals <- suppressWarnings(as.numeric(extracted))
        parsed[needs_fallback] <- recovered_vals
        digits_recovered <- digits_recovered + sum(!is.na(recovered_vals))
      }
      df[[col]] <- parsed
      counts$numeric <- counts$numeric + 1L
      type_map[col] <- "numeric"

    } else if (in_list(col, cfg$bool)) {
      df[[col]] <- to_boolean(df[[col]])
      counts$boolean <- counts$boolean + 1L
      type_map[col] <- "boolean"

    } else if (in_list(col, cfg$cat)) {
      df[[col]] <- as.factor(df[[col]])
      counts$categorical <- counts$categorical + 1L
      type_map[col] <- "categorical"

    } else if (in_list(col, cfg$obj)) {
      df[[col]] <- as.character(df[[col]])
      counts$object <- counts$object + 1L
      type_map[col] <- "object"

    } else if (in_list(col, cfg$dt)) {
      df[[col]] <- suppressWarnings(
        lubridate::parse_date_time(
          as.character(df[[col]]),
          orders = dt_orders,
          quiet  = TRUE
        )
      )
      counts$datetime <- counts$datetime + 1L
      type_map[col] <- "datetime"

    } else {
      df[[col]] <- as.character(df[[col]])
      counts$unchanged <- counts$unchanged + 1L
      type_map[col] <- "unchanged (character)"
    }
  }

  log_info(
    paste("assign_data_types: numeric=%d | boolean=%d | categorical=%d |",
          "object=%d | datetime=%d | unchanged=%d | comma_stripped=%d |",
          "digits_recovered=%d"),
    counts$numeric, counts$boolean, counts$categorical,
    counts$object, counts$datetime, counts$unchanged, comma_stripped,
    digits_recovered
  )

  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c(
        "Module 09 - Data Type Assignment Report",
        "========================================",
        sprintf("Run timestamp               : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                     : %s", toupper(cfg$country)),
        sprintf("Dataset                     : %s", cfg$dataset),
        sprintf("Data source                 : %s", cfg$data_source),
        "",
        sprintf("Total columns processed     : %d", length(col_names)),
        sprintf("  -> numeric                : %d", counts$numeric),
        sprintf("  -> boolean                : %d", counts$boolean),
        sprintf("  -> categorical (factor)   : %d", counts$categorical),
        sprintf("  -> object (character)     : %d", counts$object),
        sprintf("  -> datetime (POSIXct)     : %d", counts$datetime),
        sprintf("  -> unchanged (character)  : %d", counts$unchanged),
        "",
        if (cfg$data_source == "metabase")
          sprintf("Metabase comma-stripping    : %d value(s) cleaned across numeric columns",
                  comma_stripped)
        else
          "Metabase comma-stripping    : not applied (database source)",
        sprintf(
          paste("Embedded-digit fallback     : %d value(s) recovered from",
                "coded/free-text numeric strings (e.g. \"ANC4\", \"4 ANC visits\")",
                "that plain as.numeric() would have dropped as NA"),
          digits_recovered
        ),
        if (cfg$data_source == "metabase")
          "Metabase datetime orders    : BdYIMp, BdYHMp, BdY, dBYIMp, dBYHMp, dBY added"
        else
          "Metabase datetime orders    : not added (database source)",
        ""
      )
      # List unclassified columns
      unch <- names(type_map[type_map == "unchanged (character)"])
      if (length(unch) > 0) {
        lines <- c(lines,
                   "=== Unclassified Columns (kept as character) ===",
                   paste0("  ", unch))
      }
      writeLines(lines, report_filepath)
    }, error = function(e) log_warn("Could not write Module 09 report: %s", e$message))
  }

  return(df)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "09_data_type_assignment_report.txt") else NULL

df <- assign_data_types(df, cfg, report_filepath = report_path)
log_info("Module 09 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
