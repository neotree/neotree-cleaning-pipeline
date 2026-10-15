# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 09: Data Type Assignment
# =============================================================================
# PURPOSE:
#   Assigns R types to the columns, which are all character on entry, using
#   the cfg feature lists:
#     - cfg$num  -> numeric
#     - cfg$bool -> logical (TRUE/FALSE/NA)
#     - cfg$cat  -> factor
#     - cfg$obj  -> character
#     - cfg$dt   -> POSIXct
#   Columns not found in any list are kept as character.
#
# METHOD:
#   Values are parsed one by one according to their own shape, using the
#   shared parsers defined in 00_setup.r:
#     - parse_datetime_by_shape(): ISO datetimes (a trailing "Z" or UTC offset
#       is dropped, time kept as written), day-first dates ("25/12/2023",
#       "25-12-2023", "25.12.2023"; two-digit years read as 20yy) and
#       month-name datetimes ("March 2, 2026, 12:33 AM").  Free text and bare
#       digit strings become NA.
#     - parse_numeric_by_shape(): plain numbers, thousands separators
#       ("3,500" -> 3500), decimal commas ("3,5" -> 3.5), and text holding
#       exactly one number ("ANC4" -> 4).  Text holding two or more numbers
#       (a date, a range, exponent notation) becomes NA.
#     - NEOTREE_TRUE_TOKENS / NEOTREE_FALSE_TOKENS for booleans.
#   cfg$data_source is reported but does not change how values are parsed.
#
# INPUTS:
#   df   - data.frame after Module 08
#   cfg  - configuration list from 00_setup.r
#
# OUTPUTS:
#   df      - data.frame with typed columns
#   Report  - cfg$report_dir/09_data_type_assignment_report.txt
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
    s %in% NEOTREE_TRUE_TOKENS  ~ TRUE,
    s %in% NEOTREE_FALSE_TOKENS ~ FALSE,
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
  # Counts only (never values), summed over columns and listed per column.
  num_counts <- c(plain = 0L, thousands = 0L, decimal_comma = 0L, fallback = 0L,
                  multi_number_rejected = 0L, non_numeric = 0L)
  dt_counts  <- c(iso = 0L, day_first = 0L, month_name = 0L, offset_dropped = 0L,
                  month_first_rejected = 0L, unparsed = 0L)
  num_by_col <- list()   # numeric columns with any non-plain value
  dt_by_col  <- list()   # datetime columns with any non-ISO or unparsed value

  for (col in col_names) {
    if (in_list(col, cfg$num)) {
      res <- parse_numeric_by_shape(df[[col]])
      df[[col]] <- res$value
      num_counts <- num_counts + res$counts
      if (any(res$counts[c("thousands", "decimal_comma", "fallback",
                           "multi_number_rejected")] > 0L)) {
        num_by_col[[col]] <- res$counts
      }
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
      parsed <- parse_datetime_by_shape(df[[col]])
      dc <- attr(parsed, "counts")
      attr(parsed, "counts") <- NULL
      df[[col]] <- parsed
      dt_counts <- dt_counts + dc
      if (any(dc[c("day_first", "month_name", "offset_dropped",
                   "month_first_rejected", "unparsed")] > 0L)) {
        dt_by_col[[col]] <- dc
      }
      counts$datetime <- counts$datetime + 1L
      type_map[col] <- "datetime"

    } else {
      df[[col]] <- as.character(df[[col]])
      counts$unchanged <- counts$unchanged + 1L
      type_map[col] <- "unchanged (character)"
    }
  }

  comma_stripped   <- num_counts[["thousands"]]
  digits_recovered <- num_counts[["fallback"]]
  log_info(
    paste("assign_data_types: numeric=%d | boolean=%d | categorical=%d |",
          "object=%d | datetime=%d | unchanged=%d | comma_stripped=%d |",
          "digits_recovered=%d"),
    counts$numeric, counts$boolean, counts$categorical,
    counts$object, counts$datetime, counts$unchanged, comma_stripped,
    digits_recovered
  )
  log_info(
    paste("assign_data_types: decimal_comma=%d | multi_number_rejected=%d |",
          "datetime iso=%d | day_first=%d | month_name=%d | offset_dropped=%d |",
          "month_first_rejected=%d | datetime_unparsed=%d"),
    num_counts[["decimal_comma"]], num_counts[["multi_number_rejected"]],
    dt_counts[["iso"]], dt_counts[["day_first"]], dt_counts[["month_name"]],
    dt_counts[["offset_dropped"]], dt_counts[["month_first_rejected"]],
    dt_counts[["unparsed"]]
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
        sprintf("Thousands separators removed: %d value(s) across numeric columns",
                comma_stripped),
        sprintf(
          paste("Embedded-digit fallback     : %d value(s) recovered from",
                "text holding exactly one number (e.g. \"ANC4\", \"4 ANC visits\")"),
          digits_recovered
        ),
        sprintf("Decimal commas read as point: %d value(s) across numeric columns",
                num_counts[["decimal_comma"]]),
        sprintf(
          paste("Several numbers in one value: %d value(s) set to NA (a date, a",
                "range, exponent notation; no single number to recover)"),
          num_counts[["multi_number_rejected"]]),
        "",
        "Datetime parsing (by shape of each value):",
        sprintf("  ISO                       : %d", dt_counts[["iso"]]),
        sprintf("  Day first (d/m/y, d-m-y, d.m.y; two-digit year = 20yy): %d",
                dt_counts[["day_first"]]),
        sprintf("  Month name                : %d", dt_counts[["month_name"]]),
        sprintf("  Z or UTC offset dropped (time kept as written): %d",
                dt_counts[["offset_dropped"]]),
        sprintf("  Valid only as month/day/year, set to NA: %d",
                dt_counts[["month_first_rejected"]]),
        sprintf("  Other non-empty values set to NA (free text, bare digits): %d",
                dt_counts[["unparsed"]]),
        ""
      )
      if (length(num_by_col) > 0) {
        lines <- c(lines,
                   "=== Numeric columns with values that were not plain numbers (counts) ===",
                   vapply(names(num_by_col), function(cn) {
                     z <- num_by_col[[cn]]
                     sprintf("  %s : thousands=%d | decimal_comma=%d | fallback=%d | several_numbers_NA=%d",
                             cn, z[["thousands"]], z[["decimal_comma"]], z[["fallback"]],
                             z[["multi_number_rejected"]])
                   }, character(1)), "")
      }
      if (length(dt_by_col) > 0) {
        lines <- c(lines,
                   "=== Datetime columns with non-ISO or unparsed values (counts) ===",
                   vapply(names(dt_by_col), function(cn) {
                     z <- dt_by_col[[cn]]
                     sprintf(paste("  %s : iso=%d | day_first=%d | month_name=%d |",
                                   "offset_dropped=%d | month_first_NA=%d | other_NA=%d"),
                             cn, z[["iso"]], z[["day_first"]], z[["month_name"]],
                             z[["offset_dropped"]], z[["month_first_rejected"]],
                             z[["unparsed"]])
                   }, character(1)), "")
      }
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
