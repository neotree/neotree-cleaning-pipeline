################################################################################
# Neotree Sample Maker -- modules/subsample_maker_cleaned.R
# PURPOSE: Generic subsample maker for any cleaned Neotree CSV file.
#          Called by run_subsample_maker.R when source_type = "cleaned".
#          Handles admissions, discharges, neolab, and maternal outcome files.
#
# EXPORTED FUNCTIONS:
#   run_subsample_maker_cleaned(df, mandatory_cols, date_col, cfg_global,
#                               cfg_dataset)
#     -> Returns a result list ready for write_subsample_outputs_cleaned().
#
#   write_subsample_outputs_cleaned(result, prefix, type_label, out_dir,
#                                   na_coded_data = NULL)
#     -> Writes one CSV and one text report.  When na_coded_data is a data
#        frame (same dimensions as result data, with sentinel NA codes), also
#        writes a paired *_na_coded.csv file.
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.1  (2026-05)
################################################################################

# ==============================================================================
# INTERNAL HELPERS
# ==============================================================================

#' Apply a single exclusion filter to a data frame.
#' Rows where the filter variable is NA are always KEPT (conservative default).
.apply_one_exclusion <- function(df, filt) {
  var <- filt$variable
  op  <- filt$operator
  val <- filt$value

  if (!var %in% names(df)) {
    cat(sprintf("    [excl] Variable '%s' not found — filter skipped\n", var))
    return(df)
  }

  col <- df[[var]]
  # Build logical mask: TRUE = row to REMOVE
  keep_mask <- switch(op,
    "<"      = !(!is.na(col) & col <  val),
    "<="     = !(!is.na(col) & col <= val),
    ">"      = !(!is.na(col) & col >  val),
    ">="     = !(!is.na(col) & col >= val),
    "=="     = !(!is.na(col) & col == val),
    "!="     = !(!is.na(col) & col != val),
    "in"     = !(!is.na(col) & col %in% val),
    "not_in" = !(!is.na(col) & !col %in% val),
    {
      cat(sprintf("    [excl] Unknown operator '%s' for '%s' — filter skipped\n",
                  op, var))
      rep(TRUE, nrow(df))
    }
  )

  n_removed <- sum(!keep_mask, na.rm = TRUE)
  val_str <- if (length(val) > 3) paste0(paste(val[1:3], collapse = ", "), "…")
             else paste(val, collapse = ", ")
  cat(sprintf("    [excl] %s %s %s  -> %d row(s) removed\n",
              var, op, val_str, n_removed))
  df[keep_mask, , drop = FALSE]
}

#' Build the subsample label from effective filter settings.
.build_label <- function(start_date, end_date, facility_filter,
                         has_exclusions, sub_variables,
                         date_col = NULL) {
  # Date component
  date_part <- if (is.null(date_col)) {
    "ALL"
  } else if (is.null(start_date) && is.null(end_date)) {
    "ALL"
  } else if (is.null(start_date)) {
    paste0("to_", gsub("-", "", end_date))
  } else if (is.null(end_date)) {
    paste0("from_", gsub("-", "", start_date))
  } else {
    paste0(gsub("-", "", start_date), "_to_", gsub("-", "", end_date))
  }

  # Facility component
  fac_part <- if (!is.null(facility_filter) && length(facility_filter) > 0) {
    paste(facility_filter, collapse = "_")
  } else ""

  # Assemble
  parts <- c(date_part, fac_part)
  parts <- parts[nzchar(parts)]
  label <- paste(parts, collapse = "_")

  if (has_exclusions)           label <- paste0(label, "_excl")
  if (!is.null(sub_variables))  label <- paste0(label, "_", length(sub_variables), "vars")

  label
}

#' Parse a date column (character or Date) into Date.
#' Returns a Date vector with NA for unparseable values.
.parse_dates <- function(x) {
  if (inherits(x, "Date"))    return(x)
  if (inherits(x, "POSIXct")) return(as.Date(x))
  # Try YYYY-MM-DD first (most common), then YYYYMMDD
  d <- suppressWarnings(as.Date(as.character(x), format = "%Y-%m-%d"))
  na_idx <- is.na(d)
  if (any(na_idx)) {
    d2 <- suppressWarnings(as.Date(as.character(x[na_idx]), format = "%Y%m%d"))
    d[na_idx] <- d2
  }
  # For datetime strings: strip time part
  still_na <- is.na(d)
  if (any(still_na)) {
    stripped <- sub(" .*$", "", as.character(x[still_na]))
    d[still_na] <- suppressWarnings(as.Date(stripped, format = "%Y-%m-%d"))
  }
  d
}

#' Build a tidy facility breakdown data frame (top 20, sorted desc).
.facility_breakdown <- function(df) {
  if (!"facility" %in% names(df)) return(data.frame(facility = character(0), n = integer(0)))
  counts <- sort(table(df$facility), decreasing = TRUE)
  if (length(counts) == 0) return(data.frame(facility = character(0), n = integer(0)))
  head(data.frame(facility = names(counts), n = as.integer(counts),
                  stringsAsFactors = FALSE), 20)
}

#' Build a simple value distribution for a single column (top 10).
.value_dist <- function(df, col) {
  if (!col %in% names(df)) return(NULL)
  v <- df[[col]]
  v <- v[!is.na(v) & nzchar(as.character(v))]
  if (length(v) == 0) return(NULL)
  counts <- sort(table(as.character(v)), decreasing = TRUE)
  head(data.frame(value = names(counts), n = as.integer(counts),
                  stringsAsFactors = FALSE), 10)
}

# ==============================================================================
# MAIN FILTERING FUNCTION
# ==============================================================================

#' Run subsample filtering on a single cleaned CSV data frame.
#'
#' @param df            Data frame loaded from the cleaned CSV.
#' @param mandatory_cols Character vector of column names always kept (regardless
#'                       of sub_variables).
#' @param date_col      Name of the date column to use for filtering, or NULL
#'                      for no date filter.
#' @param cfg_global    The top-level SUBSAMPLE_CONFIG list (provides
#'                      sub_start_date, sub_end_date, sub_facility_filter,
#'                      sub_use_advanced_mode, sub_facility_date_ranges).
#' @param cfg_dataset   The per-dataset config entry (provides sub_variables
#'                      and sub_exclusion_filters that override global values;
#'                      NULL to use global values only).
#'
#' @return Named list with:
#'   $data           Filtered data frame
#'   $label          Output label string
#'   $n_raw          Rows before any filter
#'   $n_after_date   Rows after date/facility filter
#'   $n_after_excl   Rows after exclusion filters
#'   $n_final        Final row count
#'   $cols_selected  Column names in output (or NULL if all kept)
#'   $cols_not_found Column names requested but not found
#'   $date_col       Date column used (or NULL)
#'   $facility_breakdown  data.frame of facility counts
#'   $mandatory_cols Mandatory columns retained
#'   $start_date, $end_date, $facility_filter  Effective filter settings
run_subsample_maker_cleaned <- function(df, mandatory_cols, date_col,
                                        cfg_global, cfg_dataset = NULL) {

  # -- Resolve effective settings (per-dataset overrides global) ---------------
  start_date      <- cfg_global$sub_start_date
  end_date        <- cfg_global$sub_end_date
  facility_filter <- cfg_global$sub_facility_filter
  use_adv         <- isTRUE(cfg_global$sub_use_advanced_mode)
  adv_ranges      <- cfg_global$sub_facility_date_ranges

  # Per-dataset date window overrides (take precedence over global dates).
  # Use [[ ]] (not $) to avoid R's partial matching: cfg_dataset$sub_end_date
  # would otherwise partially match sub_end_date_offset_months.
  if (!is.null(cfg_dataset) && !is.null(cfg_dataset[["sub_start_date"]]))
    start_date <- cfg_dataset[["sub_start_date"]]
  if (!is.null(cfg_dataset) && !is.null(cfg_dataset[["sub_end_date"]]))
    end_date <- cfg_dataset[["sub_end_date"]]

  # Per-dataset end-date offset in months.
  # sub_end_date_offset_months = 1 extends the effective end date by 1 calendar month,
  # regardless of the month's length.  Typical use: set to 1 for the discharges dataset
  # when filtering by datetimedischarge, so that babies admitted in the last month of the
  # global window who are still in the NNU at the nominal end date are still captured.
  # The offset is applied AFTER any explicit sub_end_date override above.
  end_date_offset_months <- if (!is.null(cfg_dataset) &&
                                !is.null(cfg_dataset$sub_end_date_offset_months))
                              as.integer(cfg_dataset$sub_end_date_offset_months)
                            else 0L

  end_date_original <- end_date   # keep for note auto-generation below

  if (end_date_offset_months != 0L && !is.null(end_date) &&
      nchar(trimws(as.character(end_date))) > 0) {
    end_dt   <- suppressWarnings(as.Date(end_date))
    if (!is.na(end_dt)) {
      end_date <- format(
        seq(end_dt, by = paste(end_date_offset_months, "months"), length.out = 2)[2],
        "%Y-%m-%d"
      )
      cat(sprintf("[sub_cleaned] end_date extended by %d month(s): %s -> %s\n",
                  end_date_offset_months, end_date_original, end_date))
    }
  }

  # Optional free-text note explaining a non-standard date window.
  # Auto-generated when sub_end_date_offset_months is used and no explicit note is given.
  date_window_note <- if (!is.null(cfg_dataset) &&
                          !is.null(cfg_dataset$date_window_note) &&
                          nchar(trimws(cfg_dataset$date_window_note)) > 0)
                        cfg_dataset$date_window_note
                      else if (end_date_offset_months != 0L && !is.null(end_date_original))
                        sprintf(
                          paste0("End date extended by %d month(s) from %s to %s ",
                                 "(sub_end_date_offset_months = %d). ",
                                 "Captures records whose date falls after the global ",
                                 "end date but within the offset window."),
                          end_date_offset_months, end_date_original, end_date,
                          end_date_offset_months
                        )
                      else NULL

  # Per-dataset override: sub_variables and sub_exclusion_filters
  sub_vars <- if (!is.null(cfg_dataset) && !is.null(cfg_dataset$sub_variables))
                cfg_dataset$sub_variables
              else cfg_global$sub_variables

  excl_filters <- if (!is.null(cfg_dataset) &&
                      length(cfg_dataset$sub_exclusion_filters) > 0)
                    cfg_dataset$sub_exclusion_filters
                  else if (length(cfg_global$sub_exclusion_filters) > 0)
                    cfg_global$sub_exclusion_filters
                  else list()

  n_raw <- nrow(df)
  cat(sprintf("[sub_cleaned] Input: %d rows x %d columns\n", n_raw, ncol(df)))

  # -- Date / facility filtering -----------------------------------------------
  if (!is.null(date_col) && date_col %in% names(df)) {

    # Parse dates
    parsed <- .parse_dates(df[[date_col]])
    n_unparseable <- sum(is.na(parsed) & !is.na(df[[date_col]]))
    if (n_unparseable > 0)
      cat(sprintf("[sub_cleaned] Warning: %d unparseable date(s) in '%s' (treated as NA)\n",
                  n_unparseable, date_col))

    if (use_adv && length(adv_ranges) > 0) {
      # ADVANCED MODE: per-facility date ranges
      cat("[sub_cleaned] Advanced mode: applying per-facility date ranges\n")
      keep <- rep(FALSE, nrow(df))
      for (entry in adv_ranges) {
        fac   <- entry[1]
        fac_s <- suppressWarnings(as.Date(entry[2]))
        fac_e <- suppressWarnings(as.Date(entry[3]))
        fac_rows <- if (!is.null(df$facility)) df$facility == fac else rep(FALSE, nrow(df))
        date_ok <- (is.na(fac_s) | (!is.na(parsed) & parsed >= fac_s)) &
                   (is.na(fac_e) | (!is.na(parsed) & parsed <= fac_e))
        keep <- keep | (fac_rows & date_ok)
        cat(sprintf("  %s: %s to %s\n",
                    fac,
                    if (is.na(fac_s)) "(open)" else as.character(fac_s),
                    if (is.na(fac_e)) "(open)" else as.character(fac_e)))
      }
      df <- df[keep, , drop = FALSE]

    } else {
      # SIMPLE MODE: global date window
      s_date <- suppressWarnings(as.Date(start_date))
      e_date <- suppressWarnings(as.Date(end_date))

      if (!is.na(s_date)) {
        n_before <- nrow(df)
        df <- df[is.na(parsed[seq_len(n_raw)]) | parsed[seq_len(n_raw)] >= s_date, , drop = FALSE]
        parsed <- parsed[seq_len(nrow(df))]   # sync; re-parse safely below
        parsed <- .parse_dates(df[[date_col]])
        cat(sprintf("[sub_cleaned] start_date >= %s: %d -> %d rows\n",
                    start_date, n_before, nrow(df)))
      }
      if (!is.na(e_date)) {
        n_before <- nrow(df)
        parsed2  <- .parse_dates(df[[date_col]])
        df <- df[is.na(parsed2) | parsed2 <= e_date, , drop = FALSE]
        cat(sprintf("[sub_cleaned] end_date   <= %s: %d -> %d rows\n",
                    end_date, n_before, nrow(df)))
      }

      # Simple facility filter (only in simple mode)
      if (!is.null(facility_filter) && length(facility_filter) > 0 &&
          "facility" %in% names(df)) {
        n_before <- nrow(df)
        df <- df[df$facility %in% facility_filter, , drop = FALSE]
        cat(sprintf("[sub_cleaned] facility filter {%s}: %d -> %d rows\n",
                    paste(facility_filter, collapse = ", "), n_before, nrow(df)))
      }
    }

  } else if (!is.null(date_col)) {
    cat(sprintf("[sub_cleaned] Date column '%s' not found — date filter skipped\n", date_col))
    date_col <- NULL

  } else {
    # No date filter — apply facility filter only if set
    if (!is.null(facility_filter) && length(facility_filter) > 0 &&
        "facility" %in% names(df)) {
      n_before <- nrow(df)
      df <- df[df$facility %in% facility_filter, , drop = FALSE]
      cat(sprintf("[sub_cleaned] facility filter {%s}: %d -> %d rows\n",
                  paste(facility_filter, collapse = ", "), n_before, nrow(df)))
    }
  }

  n_after_date <- nrow(df)

  # -- Exclusion filters -------------------------------------------------------
  if (length(excl_filters) > 0) {
    cat("[sub_cleaned] Applying exclusion filters:\n")
    for (filt in excl_filters) {
      df <- .apply_one_exclusion(df, filt)
    }
  }
  n_after_excl <- nrow(df)

  # -- Column selection --------------------------------------------------------
  cols_not_found <- character(0)
  cols_selected  <- NULL

  if (!is.null(sub_vars) && length(sub_vars) > 0) {
    all_mandatory <- intersect(c(mandatory_cols, date_col), names(df))
    all_mandatory <- all_mandatory[!is.na(all_mandatory)]

    requested <- unique(c(all_mandatory, sub_vars))
    found     <- intersect(requested, names(df))
    not_found <- setdiff(sub_vars, names(df))

    if (length(not_found) > 0)
      cat(sprintf("[sub_cleaned] Column(s) not found (skipped): %s\n",
                  paste(not_found, collapse = ", ")))

    df             <- df[, found, drop = FALSE]
    cols_selected  <- found
    cols_not_found <- not_found
  }

  n_final <- nrow(df)

  # -- Build label -------------------------------------------------------------
  label <- .build_label(
    start_date      = start_date,
    end_date        = end_date,
    facility_filter = if (use_adv) NULL else facility_filter,
    has_exclusions  = length(excl_filters) > 0,
    sub_variables   = sub_vars,
    date_col        = date_col
  )

  cat(sprintf("[sub_cleaned] Final: %d rows x %d columns  [label: %s]\n\n",
              n_final, ncol(df), label))

  list(
    data             = df,
    label            = label,
    n_raw            = n_raw,
    n_after_date     = n_after_date,
    n_after_excl     = n_after_excl,
    n_final          = n_final,
    cols_selected    = cols_selected,
    cols_not_found   = cols_not_found,
    date_col         = date_col,
    start_date       = start_date,
    end_date         = end_date,
    date_window_note = date_window_note,
    facility_filter  = facility_filter,
    use_adv          = use_adv,
    adv_ranges       = adv_ranges,
    excl_filters     = excl_filters,
    sub_vars         = sub_vars,
    mandatory_cols   = mandatory_cols,
    facility_breakdown = .facility_breakdown(df)
  )
}

# ==============================================================================
# OUTPUT WRITER
# ==============================================================================

#' Write subsample CSV and text report for one cleaned dataset.
#'
#' @param result        Output from run_subsample_maker_cleaned().
#' @param prefix        File prefix string, e.g. "ZIM_db".
#' @param type_label    Dataset type string, e.g. "admissions", "neolab".
#' @param out_dir       Output directory path.
#' @param na_coded_data Optional data.frame: the same rows as result$data but
#'                      from the *_cleaned_na_coded.csv source (NA values
#'                      represented as numeric sentinel codes -7/-9 etc.).
#'                      When non-NULL a paired *_na_coded.csv is written
#'                      alongside the standard blank-NA CSV.
#'
#' @return Named character vector of written file paths (invisible).
write_subsample_outputs_cleaned <- function(result, prefix, type_label, out_dir,
                                            na_coded_data = NULL) {

  label    <- result$label
  stem     <- sprintf("%s_subsample_%s_%s", prefix, type_label, label)

  csv_path    <- file.path(out_dir, paste0(stem, ".csv"))
  report_path <- file.path(out_dir, paste0(stem, "_report.txt"))

  # Write blank-NA CSV (standard output)
  write.csv(result$data, csv_path, row.names = FALSE)
  cat(sprintf("[write] %s  (%d rows)\n", basename(csv_path), nrow(result$data)))

  # Write NA-coded CSV if provided
  csv_na_coded_path <- NULL
  if (!is.null(na_coded_data)) {
    csv_na_coded_path <- file.path(out_dir, paste0(stem, "_na_coded.csv"))
    write.csv(na_coded_data, csv_na_coded_path, row.names = FALSE)
    cat(sprintf("[write] %s  (%d rows)\n", basename(csv_na_coded_path), nrow(na_coded_data)))
  }

  # Write report
  lines <- c(
    "================================================================",
    sprintf("  Neotree Subsample Report -- %s", type_label),
    "================================================================",
    sprintf("  Generated : %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    sprintf("  Label     : %s", label),
    "",
    "FILTER SUMMARY",
    "--------------",
    sprintf("  Rows in input file          : %d", result$n_raw),
    sprintf("  Date column used            : %s",
            if (is.null(result$date_col)) "(none)" else result$date_col)
  )

  if (!is.null(result$date_col)) {
    lines <- c(lines,
      sprintf("  Date window start           : %s",
              if (is.null(result$start_date)) "(no lower bound)" else result$start_date),
      sprintf("  Date window end             : %s",
              if (is.null(result$end_date)) "(no upper bound)" else result$end_date)
    )
    if (!is.null(result$date_window_note) &&
        nchar(trimws(result$date_window_note)) > 0) {
      lines <- c(lines,
        sprintf("  Date window note            : %s", trimws(result$date_window_note))
      )
    }
  }

  if (isTRUE(result$use_adv) && length(result$adv_ranges) > 0) {
    lines <- c(lines, "  Advanced mode               : TRUE")
    for (entry in result$adv_ranges) {
      lines <- c(lines,
        sprintf("    %s : %s to %s", entry[1],
                if (is.na(as.Date(entry[2]))) "(open)" else entry[2],
                if (is.na(as.Date(entry[3]))) "(open)" else entry[3]))
    }
  } else if (!is.null(result$facility_filter) && length(result$facility_filter) > 0) {
    lines <- c(lines,
      sprintf("  Facility filter             : %s",
              paste(result$facility_filter, collapse = ", "))
    )
  } else {
    lines <- c(lines, "  Facility filter             : (all facilities)")
  }

  lines <- c(lines,
    sprintf("  Rows after date/fac filter  : %d", result$n_after_date)
  )

  if (length(result$excl_filters) > 0) {
    lines <- c(lines, "",
      sprintf("  Exclusion filters applied   : %d", length(result$excl_filters)))
    for (f in result$excl_filters) {
      val_str <- if (length(f$value) > 3)
                   paste0(paste(f$value[1:3], collapse = ", "), "…")
                 else paste(f$value, collapse = ", ")
      lines <- c(lines,
        sprintf("    %s %s %s", f$variable, f$operator, val_str))
    }
    lines <- c(lines, sprintf("  Rows after exclusion filters: %d", result$n_after_excl))
  }

  lines <- c(lines, "",
    sprintf("  FINAL row count             : %d", result$n_final),
    sprintf("  FINAL column count          : %d", ncol(result$data))
  )

  if (!is.null(result$cols_selected)) {
    lines <- c(lines,
      sprintf("  Column selection            : %d variable(s) (+ mandatory set)",
              length(result$sub_vars)),
      sprintf("  Columns retained            : %d",  ncol(result$data))
    )
    if (length(result$cols_not_found) > 0) {
      lines <- c(lines,
        sprintf("  Columns not found (skipped) : %s",
                paste(result$cols_not_found, collapse = ", "))
      )
    }
    lines <- c(lines,
      sprintf("  Mandatory columns           : %s",
              paste(result$mandatory_cols[result$mandatory_cols %in% names(result$data)],
                    collapse = ", "))
    )
  } else {
    lines <- c(lines, "  Column selection            : (all columns retained)")
  }

  # Facility breakdown
  if (nrow(result$facility_breakdown) > 0) {
    lines <- c(lines, "",
      "FACILITY BREAKDOWN",
      "------------------"
    )
    for (i in seq_len(nrow(result$facility_breakdown))) {
      lines <- c(lines,
        sprintf("  %-20s : %d", result$facility_breakdown$facility[i],
                result$facility_breakdown$n[i])
      )
    }
  }

  # Key column distributions (a selection of commonly useful columns)
  key_cols <- c("bcresult", "bctype", "org1",           # neolab
                "neotreeoutcome", "matoutcome",           # maternal
                "modedelivery", "typebirth",              # admissions/maternal
                "gender")                                 # admissions

  found_key <- intersect(key_cols, names(result$data))
  if (length(found_key) > 0) {
    lines <- c(lines, "", "KEY VARIABLE DISTRIBUTIONS", "--------------------------")
    for (col in found_key) {
      dist <- .value_dist(result$data, col)
      if (!is.null(dist) && nrow(dist) > 0) {
        lines <- c(lines, sprintf("  %s:", col))
        for (j in seq_len(nrow(dist))) {
          lines <- c(lines, sprintf("    %-30s : %d", dist$value[j], dist$n[j]))
        }
      }
    }
  }

  lines <- c(lines, "",
    "OUTPUT FILES",
    "------------",
    sprintf("  %s", basename(csv_path))
  )
  if (!is.null(csv_na_coded_path)) {
    lines <- c(lines,
      sprintf("  %s  [NA-coded variant: -7/-9 sentinel values]",
              basename(csv_na_coded_path))
    )
  }
  lines <- c(lines,
    sprintf("  %s", basename(report_path)),
    "",
    "================================================================"
  )

  writeLines(lines, report_path)
  cat(sprintf("[write] %s\n", basename(report_path)))

  out_paths <- c(csv = csv_path, report = report_path)
  if (!is.null(csv_na_coded_path))
    out_paths <- c(out_paths, csv_na_coded = csv_na_coded_path)
  invisible(out_paths)
}
