#!/usr/bin/env Rscript

################################################################################
# Neotree Sample Maker -- Subsample Maker: Neolab Files  (module)
# FILE:    modules/subsample_maker_neolab.R
# PURPOSE: Create analysis-ready subsamples from cleaned Neolab blood culture
#          files (present in both Malawi and Zimbabwe).  These are standalone
#          files -- no joining or matching required.
#
# DATE COLUMNS
#   datebct  (blood culture TAKEN date) -- default filtering column
#   datebcr  (blood culture RESULT date) -- alternative
#   Configured via cfg$sub_date_column; defaults to "datebct".
#
# EXPORTED FUNCTIONS
#   run_subsample_maker_neolab(df, cfg)
#       Applies date/facility filtering, optional exclusion filters, and optional
#       column selection to a Neolab data frame.
#       Returns a list:  subsample, label, report_text.
#
#   write_subsample_outputs_neolab(result, prefix, out_dir)
#       Writes the filtered CSV and text report to out_dir.
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.0  (2026-04)
################################################################################

# ==============================================================================
# INTERNAL: parse a date/datetime string to POSIXct
# Tries multiple formats in order; returns NA for values that cannot be parsed.
# ==============================================================================
.lab_parse_date <- function(x) {
  formats <- c(
    "%Y-%m-%dT%H:%M:%OSZ",
    "%Y-%m-%dT%H:%M:%OS",
    "%Y-%m-%d %H:%M:%OS",
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%d"
  )
  result <- as.POSIXct(rep(NA_real_, length(x)), origin = "1970-01-01", tz = "UTC")
  remaining <- seq_along(x)
  for (fmt in formats) {
    if (length(remaining) == 0) break
    parsed <- suppressWarnings(
      as.POSIXct(x[remaining], format = fmt, tz = "UTC")
    )
    ok <- !is.na(parsed)
    result[remaining[ok]] <- parsed[ok]
    remaining <- remaining[!ok]
  }
  result
}

# ==============================================================================
# INTERNAL: resolve which date column to use
# ==============================================================================
.lab_resolve_date_col <- function(cfg, df_names) {
  col <- if (!is.null(cfg$sub_date_column) &&
              nchar(trimws(cfg$sub_date_column)) > 0) {
    trimws(cfg$sub_date_column)
  } else {
    "datebct"
  }
  if (!col %in% df_names) {
    stop(sprintf(
      "[neolab] Date column '%s' not found in input file.\n  Available columns: %s",
      col, paste(df_names, collapse = ", ")
    ))
  }
  col
}

# ==============================================================================
# INTERNAL: build filter description string and output label
# ==============================================================================
.lab_build_filter_info <- function(cfg, date_col) {

  if (isTRUE(cfg$sub_use_advanced_mode)) {
    ranges <- cfg$sub_facility_date_ranges
    if (length(ranges) == 0) {
      return(list(
        desc  = "Advanced mode enabled but no facility date ranges defined -- no filter applied.",
        label = "all"
      ))
    }
    parts <- vapply(ranges, function(r) {
      sprintf("%s: %s to %s", r[1], r[2], r[3])
    }, character(1))
    label_parts <- vapply(ranges, function(r) {
      paste0(
        gsub("[^A-Za-z0-9]", "", r[1]), "_",
        gsub("-", "", r[2]), "_",
        gsub("-", "", r[3])
      )
    }, character(1))
    return(list(
      desc  = sprintf("Advanced mode -- per-facility date ranges: %s",
                      paste(parts, collapse = "; ")),
      label = paste(label_parts, collapse = "_")
    ))
  }

  has_start <- !is.null(cfg$sub_start_date) &&
               nchar(trimws(as.character(cfg$sub_start_date))) > 0
  has_end   <- !is.null(cfg$sub_end_date) &&
               nchar(trimws(as.character(cfg$sub_end_date))) > 0
  has_fac   <- !is.null(cfg$sub_facility_filter) &&
               length(cfg$sub_facility_filter) > 0

  date_label <- if (has_start && has_end) {
    paste0(gsub("-", "", cfg$sub_start_date), "_",
           gsub("-", "", cfg$sub_end_date))
  } else if (has_start) {
    paste0("from_", gsub("-", "", cfg$sub_start_date))
  } else if (has_end) {
    paste0("to_", gsub("-", "", cfg$sub_end_date))
  } else {
    "all_dates"
  }

  fac_label <- if (has_fac) {
    paste0("_", paste(cfg$sub_facility_filter, collapse = "_"))
  } else {
    ""
  }

  desc_parts <- character(0)
  if (!is.null(date_col)) {
    desc_parts <- c(desc_parts, sprintf("date column: %s", date_col))
  }
  if (has_start) desc_parts <- c(desc_parts,
                                  sprintf("from %s", cfg$sub_start_date))
  if (has_end)   desc_parts <- c(desc_parts,
                                  sprintf("to %s",   cfg$sub_end_date))
  if (has_fac)   desc_parts <- c(desc_parts,
                                  sprintf("facilities: %s",
                                    paste(cfg$sub_facility_filter,
                                          collapse = ", ")))
  if (length(desc_parts) == 0) desc_parts <- "no filter (all records)"

  list(
    desc  = paste(desc_parts, collapse = "; "),
    label = paste0(date_label, fac_label)
  )
}

# ==============================================================================
# INTERNAL: apply date/facility filter
# ==============================================================================
.lab_apply_filter <- function(df, cfg) {

  if (isTRUE(cfg$sub_use_advanced_mode)) {
    ranges <- cfg$sub_facility_date_ranges
    if (length(ranges) == 0) {
      cat("  [filter] Advanced mode: no ranges defined -- no filter applied.\n")
      return(df)
    }
    keep <- rep(FALSE, nrow(df))
    for (r in ranges) {
      fac   <- r[1]
      start <- suppressWarnings(
        as.POSIXct(r[2], format = "%Y-%m-%d", tz = "UTC")
      )
      end <- suppressWarnings(
        as.POSIXct(r[3], format = "%Y-%m-%d", tz = "UTC")
      ) + 86400 - 1
      is_fac <- !is.na(df$facility) & df$facility == fac
      in_rng <- !is.na(df$date_parsed) &
                df$date_parsed >= start &
                df$date_parsed <= end
      keep <- keep | (is_fac & in_rng)
    }
    return(df[keep, , drop = FALSE])
  }

  has_start <- !is.null(cfg$sub_start_date) &&
               nchar(trimws(as.character(cfg$sub_start_date))) > 0
  has_end   <- !is.null(cfg$sub_end_date) &&
               nchar(trimws(as.character(cfg$sub_end_date))) > 0
  has_fac   <- !is.null(cfg$sub_facility_filter) &&
               length(cfg$sub_facility_filter) > 0

  mask <- rep(TRUE, nrow(df))

  if (has_start) {
    start <- suppressWarnings(
      as.POSIXct(cfg$sub_start_date, format = "%Y-%m-%d", tz = "UTC")
    )
    mask <- mask & (!is.na(df$date_parsed) & df$date_parsed >= start)
  }
  if (has_end) {
    end  <- suppressWarnings(
      as.POSIXct(cfg$sub_end_date, format = "%Y-%m-%d", tz = "UTC")
    ) + 86400 - 1
    mask <- mask & (!is.na(df$date_parsed) & df$date_parsed <= end)
  }
  if (has_fac) {
    mask <- mask & (!is.na(df$facility) &
                    df$facility %in% cfg$sub_facility_filter)
  }

  df[mask, , drop = FALSE]
}

# ==============================================================================
# INTERNAL: apply exclusion filters
# ==============================================================================
.lab_apply_exclusion_filters <- function(df, filters) {
  if (length(filters) == 0) return(df)
  for (f in filters) {
    var <- f$variable
    op  <- f$operator
    val <- f$value
    if (!var %in% names(df)) {
      cat(sprintf(
        "  [excl] WARNING: column '%s' not found in data -- filter skipped.\n",
        var
      ))
      next
    }
    col     <- df[[var]]
    na_mask <- is.na(col)
    num_col <- suppressWarnings(as.numeric(col))
    exclude <- switch(op,
      "<"      = !na_mask & !is.na(num_col) & num_col <  as.numeric(val),
      "<="     = !na_mask & !is.na(num_col) & num_col <= as.numeric(val),
      ">"      = !na_mask & !is.na(num_col) & num_col >  as.numeric(val),
      ">="     = !na_mask & !is.na(num_col) & num_col >= as.numeric(val),
      "=="     = !na_mask & as.character(col) == as.character(val),
      "!="     = !na_mask & as.character(col) != as.character(val),
      "in"     = !na_mask & as.character(col) %in% as.character(val),
      "not_in" = !na_mask & !as.character(col) %in% as.character(val),
      {
        cat(sprintf(
          "  [excl] WARNING: unknown operator '%s' -- filter skipped.\n", op
        ))
        rep(FALSE, nrow(df))
      }
    )
    n_excl <- sum(exclude, na.rm = TRUE)
    cat(sprintf(
      "  [excl] '%s' %s %s: excluded %d rows\n",
      var, op, paste(val, collapse = ", "), n_excl
    ))
    df <- df[!exclude, , drop = FALSE]
  }
  df
}

# ==============================================================================
# INTERNAL: apply column selection
# ==============================================================================
.lab_select_columns <- function(df, sub_variables, date_col) {
  if (is.null(sub_variables) || length(sub_variables) == 0) return(df)
  mandatory <- c("uid", "facility", "uniquekey", date_col)
  # Also keep nuid if it exists (useful lab identifier)
  if ("nuid" %in% names(df)) mandatory <- c(mandatory, "nuid")
  all_keep  <- unique(c(mandatory, sub_variables))
  present   <- all_keep[all_keep %in% names(df)]
  missing_v <- sub_variables[!sub_variables %in% names(df)]
  if (length(missing_v) > 0) {
    cat(sprintf(
      "  [cols] WARNING: %d requested column(s) not found and skipped: %s\n",
      length(missing_v), paste(missing_v, collapse = ", ")
    ))
  }
  df[, present, drop = FALSE]
}

# ==============================================================================
# INTERNAL: facility breakdown table lines
# ==============================================================================
.lab_fac_breakdown <- function(df, label) {
  if (nrow(df) == 0) {
    return(sprintf("  %s: (no records)", label))
  }
  tab   <- sort(table(df$facility), decreasing = TRUE)
  lines <- sprintf("  %s  (n = %d):", label, nrow(df))
  for (i in seq_along(tab)) {
    lines <- c(lines,
               sprintf("    %-22s  %7d", names(tab)[i], as.integer(tab[[i]])))
  }
  paste(lines, collapse = "\n")
}

# ==============================================================================
# INTERNAL: top-value distribution for a single column
# ==============================================================================
.lab_col_dist <- function(df, col_name, label) {
  if (!col_name %in% names(df) || nrow(df) == 0) return(NULL)
  vals <- df[[col_name]]
  vals <- vals[!is.na(vals) & nchar(trimws(as.character(vals))) > 0]
  if (length(vals) == 0) return(NULL)
  tab   <- sort(table(vals), decreasing = TRUE)
  lines <- sprintf("  %s:", label)
  top_n <- min(10L, length(tab))
  for (i in seq_len(top_n)) {
    lines <- c(lines,
               sprintf("    %-30s  %7d", names(tab)[i], as.integer(tab[[i]])))
  }
  if (length(tab) > top_n) {
    lines <- c(lines,
               sprintf("    ... (%d further values)", length(tab) - top_n))
  }
  paste(lines, collapse = "\n")
}

# ==============================================================================
# INTERNAL: build full text report
# ==============================================================================
.lab_build_report <- function(df_in, df_out, n_unparsed, cfg,
                               filter_info, date_col) {

  sep_thick <- strrep("=", 72)
  sep_thin  <- strrep("-", 72)
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  has_excl <- !is.null(cfg$sub_exclusion_filters) &&
              length(cfg$sub_exclusion_filters) > 0
  has_cols <- !is.null(cfg$sub_variables) && length(cfg$sub_variables) > 0

  lines <- c(
    sep_thick,
    "  Neotree Sample Maker -- Neolab Subsample Report",
    sep_thick,
    "",
    sprintf("  Generated   : %s", timestamp),
    sprintf("  Filter      : %s", filter_info$desc),
    ""
  )

  # ---- Input summary ----
  lines <- c(lines,
    sep_thin,
    "  INPUT DATASET",
    sep_thin,
    sprintf("  Rows        : %d", nrow(df_in)),
    sprintf("  Columns     : %d", ncol(df_in) - 1L),  # -1 for date_parsed
    sprintf("  Date column : %s", date_col),
    sprintf("  Unparseable : %d rows with missing or unparseable %s",
            n_unparsed, date_col)
  )
  if (nrow(df_in) > 0 && any(!is.na(df_in$date_parsed))) {
    dmin <- min(df_in$date_parsed, na.rm = TRUE)
    dmax <- max(df_in$date_parsed, na.rm = TRUE)
    lines <- c(lines,
      sprintf("  Date range  : %s  to  %s",
              format(dmin, "%Y-%m-%d"), format(dmax, "%Y-%m-%d"))
    )
  }
  lines <- c(lines, "", .lab_fac_breakdown(df_in, "Facilities in input"), "")

  # ---- Subsample summary ----
  pct_kept <- if (nrow(df_in) > 0) {
    100 * nrow(df_out) / nrow(df_in)
  } else { 0 }

  lines <- c(lines,
    sep_thin,
    "  SUBSAMPLE",
    sep_thin,
    sprintf("  Rows kept   : %d  (%.1f%% of input)", nrow(df_out), pct_kept),
    sprintf("  Rows removed: %d", nrow(df_in) - nrow(df_out)),
    sprintf("  Columns     : %d", ncol(df_out))
  )
  if (nrow(df_out) > 0 && "date_parsed" %in% names(df_out) &&
      any(!is.na(df_out$date_parsed))) {
    dmin2 <- min(df_out$date_parsed, na.rm = TRUE)
    dmax2 <- max(df_out$date_parsed, na.rm = TRUE)
    lines <- c(lines,
      sprintf("  Date range  : %s  to  %s",
              format(dmin2, "%Y-%m-%d"), format(dmax2, "%Y-%m-%d"))
    )
  }
  lines <- c(lines, "", .lab_fac_breakdown(df_out, "Facilities in subsample"), "")

  # ---- Key distributions ----
  for (col in c("bcresult", "bctype", "org1", "org2")) {
    dist_txt <- .lab_col_dist(df_out, col, col)
    if (!is.null(dist_txt)) {
      lines <- c(lines, sep_thin, dist_txt, "")
    }
  }

  # ---- Exclusion filters ----
  if (has_excl) {
    lines <- c(lines,
      sep_thin,
      "  EXCLUSION FILTERS APPLIED",
      sep_thin
    )
    for (f in cfg$sub_exclusion_filters) {
      val_str <- paste(f$value, collapse = ", ")
      lines <- c(lines,
        sprintf("  %s %s %s", f$variable, f$operator, val_str)
      )
    }
    lines <- c(lines, "")
  }

  # ---- Column selection ----
  if (has_cols) {
    lines <- c(lines,
      sep_thin,
      "  COLUMN SELECTION",
      sep_thin,
      sprintf("  Requested   : %d variables", length(cfg$sub_variables)),
      sprintf("  In output   : %d columns (mandatory columns always retained)",
              ncol(df_out)),
      ""
    )
  }

  lines <- c(lines,
    sep_thick,
    sprintf("  End of neolab subsample report -- %s", timestamp),
    sep_thick
  )

  lines
}

# ==============================================================================
# MAIN FUNCTION: run_subsample_maker_neolab
# ==============================================================================

run_subsample_maker_neolab <- function(df, cfg) {

  # Resolve date column
  date_col <- .lab_resolve_date_col(cfg, names(df))
  cat(sprintf("  Input: %d rows x %d columns\n", nrow(df), ncol(df)))
  cat(sprintf("  Using date column: '%s'\n", date_col))

  # Parse dates
  df$date_parsed <- .lab_parse_date(df[[date_col]])

  n_unparsed <- sum(is.na(df$date_parsed))
  if (n_unparsed > 0) {
    cat(sprintf(
      "  WARNING: %d rows with unparseable/missing '%s' -- excluded by any date filter.\n",
      n_unparsed, date_col
    ))
  }

  # Report input date range
  if (any(!is.na(df$date_parsed))) {
    dmin <- format(min(df$date_parsed, na.rm = TRUE), "%Y-%m-%d")
    dmax <- format(max(df$date_parsed, na.rm = TRUE), "%Y-%m-%d")
    cat(sprintf("  Date range in input: %s to %s\n", dmin, dmax))
  }

  # Build filter description
  filter_info <- .lab_build_filter_info(cfg, date_col)
  cat(sprintf("  Filter: %s\n", filter_info$desc))

  # Apply date/facility filter
  n_before     <- nrow(df)
  df_filtered  <- .lab_apply_filter(df, cfg)
  n_after_date <- nrow(df_filtered)
  cat(sprintf("  After date/facility filter: %d rows (removed %d)\n",
              n_after_date, n_before - n_after_date))

  # Apply exclusion filters
  has_excl <- !is.null(cfg$sub_exclusion_filters) &&
              length(cfg$sub_exclusion_filters) > 0
  if (has_excl) {
    df_filtered <- .lab_apply_exclusion_filters(
      df_filtered, cfg$sub_exclusion_filters
    )
    cat(sprintf("  After exclusion filters: %d rows\n", nrow(df_filtered)))
  }

  # Build output label
  excl_suffix <- if (has_excl) "_excl" else ""
  out_label   <- paste0(filter_info$label, excl_suffix)

  # Apply column selection
  df_out <- .lab_select_columns(df_filtered, cfg$sub_variables, date_col)

  # Build report (while date_parsed is still present)
  report <- .lab_build_report(
    df_in      = df,
    df_out     = df_out,
    n_unparsed = n_unparsed,
    cfg        = cfg,
    filter_info = filter_info,
    date_col   = date_col
  )

  # Drop internal date_parsed column
  df_out$date_parsed <- NULL

  cat(sprintf("  Output: %d rows x %d columns\n", nrow(df_out), ncol(df_out)))

  list(
    subsample   = df_out,
    label       = out_label,
    report_text = report
  )
}

# ==============================================================================
# WRITE OUTPUTS: write_subsample_outputs_neolab
# ==============================================================================

write_subsample_outputs_neolab <- function(result, prefix, out_dir,
                                           stem = "subsample_neolab") {

  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  label   <- result$label
  csv_out <- file.path(
    out_dir, sprintf("%s_%s_%s.csv", prefix, stem, label)
  )
  txt_out <- file.path(
    out_dir, sprintf("%s_%s_%s_report.txt", prefix, stem, label)
  )

  write.csv(result$subsample, csv_out, row.names = FALSE, na = "")
  cat(sprintf("[output] CSV    : %s\n", basename(csv_out)))

  writeLines(result$report_text, txt_out)
  cat(sprintf("[output] Report : %s\n", basename(txt_out)))

  invisible(list(csv = csv_out, txt = txt_out))
}
