################################################################################
# Neotree Sample Maker -- Module 01: Join Admissions & Discharges
# FILE:    modules/filter_data.R
# PURPOSE: Parse admission dates, compute the "one month in arrears" window
#          automatically when dates are not specified, and apply date/facility
#          filters to admissions.  Discharges are intentionally left unfiltered
#          so that every available discharge record can be used to match the
#          selected admissions.
#
# ONE-MONTH-IN-ARREARS LOGIC
#   Because some babies are still admitted at the time of data extraction,
#   selecting admissions right up to the data cut-off would inflate the
#   "unmatched admissions" count with babies who simply haven't been discharged
#   yet.  The pipeline therefore sets:
#
#     adm_end_date (auto) = latest datetimeadmission in file  -  1 calendar month
#
#   This gives most babies at least one full month to be discharged before the
#   analysis cut.  The user can override this by setting adm_end_date explicitly
#   in config.R.
#
# FUNCTIONS EXPORTED
#   parse_admission_dates(admissions)
#     -> adds adm_date_parsed column; returns updated data frame
#
#   resolve_date_window(admissions, cfg)
#     -> returns list(adm_start, adm_end, dis_end=NULL, auto_mode, label)
#
#   apply_admission_filter(admissions, date_window, cfg)
#     -> returns filtered admissions + list of filter description lines
#
#   apply_variable_filter(admissions, cfg)
#     -> returns filtered admissions (or unchanged if filter disabled)
################################################################################

# ------------------------------------------------------------------------------
# 1. parse_admission_dates()
# Adds the POSIXct column adm_date_parsed to the admissions data frame.
# Handles both datetime ("YYYY-MM-DD HH:MM:SS") and date-only ("YYYY-MM-DD").
# ------------------------------------------------------------------------------
parse_admission_dates <- function(admissions) {

  cat("[filter] Parsing admission dates (datetimeadmission)...\n")

  # Primary parse: full datetime
  admissions$adm_date_parsed <- as.POSIXct(
    admissions$datetimeadmission,
    format = "%Y-%m-%d %H:%M:%S",
    tz = "UTC"
  )

  # Fallback: date-only values that failed primary parse
  na_mask <- is.na(admissions$adm_date_parsed)
  if (any(na_mask)) {
    admissions$adm_date_parsed[na_mask] <- as.POSIXct(
      substr(as.character(admissions$datetimeadmission[na_mask]), 1, 10),
      format = "%Y-%m-%d",
      tz = "UTC"
    )
  }

  n_missing <- sum(is.na(admissions$adm_date_parsed))
  date_range <- range(admissions$adm_date_parsed, na.rm = TRUE)

  if (n_missing > 0) {
    cat(sprintf(
      "[filter]   WARNING: %d record(s) have an unparseable datetimeadmission -- these will be EXCLUDED from date-filtered output.\n",
      n_missing
    ))
  }
  cat(sprintf(
    "[filter]   Date range in file : %s  to  %s\n",
    format(date_range[1], "%Y-%m-%d"),
    format(date_range[2], "%Y-%m-%d")
  ))

  admissions
}

# ------------------------------------------------------------------------------
# 2. resolve_date_window()
# Determines the actual adm_start / adm_end dates to use.
# In auto mode, adm_end = last date in data minus 1 calendar month (base-R).
# ------------------------------------------------------------------------------
resolve_date_window <- function(admissions, cfg) {

  if (cfg$use_advanced_mode) {
    # In advanced mode the date window is per-facility; nothing to resolve here.
    return(list(
      adm_start = NULL,
      adm_end   = NULL,
      auto_mode = FALSE,
      label     = .build_advanced_label(cfg$facility_date_ranges)
    ))
  }

  adm_start <- cfg$adm_start_date
  adm_end   <- cfg$adm_end_date
  auto_mode <- FALSE

  if (is.null(adm_end)) {
    auto_mode     <- TRUE
    max_date_raw  <- max(admissions$adm_date_parsed, na.rm = TRUE)
    max_date      <- as.Date(max_date_raw)
    # Subtract exactly 1 calendar month using seq() -- handles month-end edge cases
    adm_end       <- as.character(
      seq(max_date, by = "-1 month", length.out = 2)[2]
    )
    cat(sprintf(
      "[filter]   AUTO date window : adm_end set to %s (last date in file [%s] - 1 month)\n",
      adm_end, as.character(max_date)
    ))
  }

  list(
    adm_start = adm_start,
    adm_end   = adm_end,
    auto_mode = auto_mode,
    label     = .build_simple_label(adm_start, adm_end, cfg$facility_filter)
  )
}

# ------------------------------------------------------------------------------
# 3. apply_admission_filter()
# Filters admissions by date window and/or facility.
# Discharges are NOT filtered -- all records are retained for matching.
# ------------------------------------------------------------------------------
apply_admission_filter <- function(admissions, date_window, cfg) {

  n_before <- nrow(admissions)

  if (!cfg$use_advanced_mode) {

    # --- SIMPLE MODE ---
    mask <- rep(TRUE, nrow(admissions))

    if (!is.null(date_window$adm_start)) {
      start_dt <- as.POSIXct(date_window$adm_start, format = "%Y-%m-%d", tz = "UTC")
      mask <- mask & !is.na(admissions$adm_date_parsed) &
              admissions$adm_date_parsed >= start_dt
    }
    if (!is.null(date_window$adm_end)) {
      end_dt <- as.POSIXct(
        paste(date_window$adm_end, "23:59:59"),
        format = "%Y-%m-%d %H:%M:%S", tz = "UTC"
      )
      mask <- mask & !is.na(admissions$adm_date_parsed) &
              admissions$adm_date_parsed <= end_dt
    }
    if (!is.null(cfg$facility_filter)) {
      mask <- mask & admissions$facility %in% cfg$facility_filter
    }

    admissions_filtered <- admissions[mask, ]

    filter_desc <- c(
      "  Mode         : Simple",
      sprintf("  adm_start    : %s%s",
        ifelse(is.null(date_window$adm_start), "(none -- no lower bound)", date_window$adm_start),
        ifelse(date_window$auto_mode, "", "")),
      sprintf("  adm_end      : %s%s",
        ifelse(is.null(date_window$adm_end), "(none)", date_window$adm_end),
        ifelse(date_window$auto_mode, "  [AUTO: last date in file - 1 month]", "")),
      sprintf("  Facilities   : %s",
        ifelse(is.null(cfg$facility_filter), "All",
               paste(cfg$facility_filter, collapse = ", ")))
    )

  } else {

    # --- ADVANCED MODE ---
    if (length(cfg$facility_date_ranges) == 0) {
      stop("[filter] use_advanced_mode is TRUE but facility_date_ranges is empty. Add at least one entry to config.R.")
    }
    for (i in seq_along(cfg$facility_date_ranges)) {
      entry <- cfg$facility_date_ranges[[i]]
      if (length(entry) != 3) {
        stop(sprintf(
          "[filter] facility_date_ranges entry %d must have 3 elements: c('FACILITY', 'start_date', 'end_date'). Found %d.",
          i, length(entry)
        ))
      }
    }

    chunks <- lapply(cfg$facility_date_ranges, function(r) {
      fac      <- r[1]
      start_dt <- as.POSIXct(r[2], format = "%Y-%m-%d", tz = "UTC")
      end_dt   <- as.POSIXct(paste(r[3], "23:59:59"), format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
      subset(
        admissions,
        facility == fac &
          !is.na(adm_date_parsed) &
          adm_date_parsed >= start_dt &
          adm_date_parsed <= end_dt
      )
    })

    admissions_filtered <- do.call(rbind, chunks)
    # Safety dedup in case facility_date_ranges entries overlap
    admissions_filtered <- admissions_filtered[
      !duplicated(paste(admissions_filtered$uid, admissions_filtered$facility)),
    ]

    filter_desc <- c(
      "  Mode         : Advanced (per-facility date ranges)",
      sapply(cfg$facility_date_ranges, function(r) {
        sprintf("    %-12s  %s  to  %s", r[1], r[2], r[3])
      })
    )
  }

  n_after    <- nrow(admissions_filtered)
  n_excluded <- n_before - n_after

  cat(sprintf("[filter]   Admissions before filter : %d\n", n_before))
  cat(sprintf("[filter]   Admissions after  filter : %d  (%d excluded)\n\n",
              n_after, n_excluded))

  if (n_after == 0) {
    avail_dates <- range(admissions$adm_date_parsed, na.rm = TRUE)
    avail_facs  <- paste(sort(unique(admissions$facility)), collapse = ", ")
    stop(sprintf(
      "[filter] No admissions remain after filtering.\n  Available date range : %s  to  %s\n  Available facilities : %s\n  Check adm_start_date / adm_end_date / facility_filter in config.R.",
      format(avail_dates[1], "%Y-%m-%d"),
      format(avail_dates[2], "%Y-%m-%d"),
      avail_facs
    ))
  }

  list(
    admissions      = admissions_filtered,
    n_before        = n_before,
    n_after         = n_after,
    n_excluded      = n_excluded,
    filter_desc     = filter_desc,
    filter_label    = date_window$label
  )
}

# ------------------------------------------------------------------------------
# 4. apply_variable_filter()
# Optional: retain only admissions where a given column matches target values.
# Applied after the date/facility filter.
# ------------------------------------------------------------------------------
apply_variable_filter <- function(admissions, cfg, filter_result) {

  if (is.null(cfg$variable_filter_col) || is.null(cfg$variable_filter_values)) {
    return(list(
      admissions         = admissions,
      n_excluded_varfilt = 0L,
      var_filter_desc    = NULL
    ))
  }

  col <- cfg$variable_filter_col
  vals <- cfg$variable_filter_values

  if (!col %in% names(admissions)) {
    stop(sprintf(
      "[filter] Variable filter column '%s' not found in admissions.\n  Available columns (first 30): %s",
      col, paste(head(names(admissions), 30), collapse = ", ")
    ))
  }

  n_before <- nrow(admissions)
  admissions <- admissions[admissions[[col]] %in% vals, ]
  n_after  <- nrow(admissions)
  n_excl   <- n_before - n_after

  cat(sprintf(
    "[filter]   Variable filter (%s IN {%s}) : %d kept, %d excluded\n\n",
    col, paste(vals, collapse = ", "), n_after, n_excl
  ))

  if (n_after == 0) {
    all_vals <- paste(head(sort(unique(
      filter_result$admissions[[col]])), 20), collapse = ", ")
    stop(sprintf(
      "[filter] No admissions remain after variable filter.\n  Column '%s' values present (first 20): %s",
      col, all_vals
    ))
  }

  desc <- sprintf("  Variable filter: %s IN {%s}", col, paste(vals, collapse = ", "))

  list(
    admissions         = admissions,
    n_excluded_varfilt = n_excl,
    var_filter_desc    = desc
  )
}

# ------------------------------------------------------------------------------
# Internal label builders
# ------------------------------------------------------------------------------
.build_simple_label <- function(start, end, facilities) {
  # Build a compact, human-readable date part:
  #   both provided  -> "20220101_to_20260228"
  #   end only       -> "to_20260228"
  #   start only     -> "from_20220101"
  #   neither        -> (no date component)
  date_part <- if (!is.null(start) && !is.null(end)) {
    paste0(gsub("-", "", start), "_to_", gsub("-", "", end))
  } else if (!is.null(end)) {
    paste0("to_", gsub("-", "", end))
  } else if (!is.null(start)) {
    paste0("from_", gsub("-", "", start))
  } else {
    NULL
  }
  fac_part <- if (!is.null(facilities)) paste(facilities, collapse = "_") else NULL
  parts <- c(date_part, fac_part)
  if (length(parts) > 0) paste(parts, collapse = "_") else "ALL"
}

.build_advanced_label <- function(ranges) {
  facs  <- sapply(ranges, `[`, 1)
  start <- min(sapply(ranges, `[`, 2))
  end   <- max(sapply(ranges, `[`, 3))
  paste0(
    gsub("-", "", start), "_to_", gsub("-", "", end),
    "_", paste(facs, collapse = "_")
  )
}
