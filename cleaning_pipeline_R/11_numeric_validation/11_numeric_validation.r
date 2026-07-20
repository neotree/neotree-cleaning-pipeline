# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 11: Numeric Feature Validation
# =============================================================================
# PURPOSE:
#   Validates all numeric columns in the dataset against clinically plausible
#   ranges defined in the data dictionary (loaded into cfg$range_lookup by
#   Module 00_setup).  Performs four tasks:
#
#   1. INVALID ENTRY REMOVAL - any value that cannot be coerced to numeric is
#      set to NA.
#   2. UNIT STANDARDISATION - weight variables recorded in kilograms are converted
#      to grams for consistency.  The weight column list is derived from
#      the dictionary's weight_unit == "grams" flag (cfg$weight_cols).
#   3. RANGE VALIDATION - values outside the clinically defined range are set
#      to NA.  Ranges come from cfg$range_lookup (a tibble with columns
#      question_key, min, max derived from the v6 dictionary Variables sheet).
#   4. DEDUPLICATION - a final deduplication step is applied to the numeric
#      sub-frame before merging back.
#
# INPUTS:
#   df               - data.frame after Module 10
#   cfg$num          - numeric feature column names
#   cfg$weight_cols  - question_key values to convert kg -> g
#   cfg$range_lookup - tibble: question_key, min, max
#
# OUTPUTS:
#   df_numeric  - validated numeric sub-frame
#
# REPORT:
#   reports/11_numeric_validation_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("11_numeric_validation/11_numeric_validation.r")
# =============================================================================

source("00_setup/00_setup.r")

# -- Helper: strip suffix for range lookup ------------------------------------
base_name <- function(col) {
  col <- sub("\\.valuedischarge$", "", col)
  col <- sub("\\.value$",          "", col)
  return(col)
}

# -- Function ------------------------------------------------------------------

#' Validate Numeric Features
#'
#' @param df              Full data.frame from Module 10.
#' @param cfg             Config list (num, weight_cols, range_lookup).
#' @param report_filepath Optional path for a text report.
#' @return                Validated numeric sub-frame.
validate_numeric <- function(df, cfg, report_filepath = NULL) {

  # Build a named lookup from range_lookup tibble for fast access
  # key: question_key  ->  list(min, max)
  range_map <- list()
  if (!is.null(cfg$range_lookup) && nrow(cfg$range_lookup) > 0) {
    for (i in seq_len(nrow(cfg$range_lookup))) {
      k <- cfg$range_lookup$question_key[i]
      range_map[[k]] <- list(
        min = cfg$range_lookup$min[i],
        max = cfg$range_lookup$max[i]
      )
    }
  }

  # Select columns: primary keys + numeric features present in df
  key_cols  <- c("facility", "uid", "uniquekey")
  num_cols  <- intersect(cfg$num, names(df))
  keep_cols <- unique(c(key_cols, num_cols))
  df_num    <- df[, keep_cols[keep_cols %in% names(df)], drop = FALSE]

  removed_non_numeric    <- 0L
  converted_units        <- 0L
  out_of_range           <- 0L
  range_detail_log       <- character(0)   # per-column range violation counts
  implausible_weight_log <- character(0)   # per-column post-conversion plausibility warnings
  rescued_matageyrs      <- 0L             # matageyrs values rescued from hours to years
  matageyrs_rescue_log   <- character(0)   # per-record rescue detail for report
  mat_age_date_derived   <- 0L             # matagedate values converted hours -> years
  mat_age_date_implaus   <- 0L             # matagedate-derived years set to NA (out of 9-60)
  mat_age_date_log       <- character(0)   # matagedate derivation detail for report

  for (col in setdiff(num_cols, key_cols)) {
    if (!col %in% names(df_num)) next
    base <- base_name(col)

    # -- 1. Remove non-numeric values ------------------------------------------
    original     <- df_num[[col]]
    numeric_vals <- suppressWarnings(as.numeric(as.character(original)))
    n_coerce_fail <- sum(is.na(numeric_vals) & !is.na(original))
    removed_non_numeric <- removed_non_numeric + n_coerce_fail
    df_num[[col]] <- numeric_vals

    # -- 2. Unit standardisation: kilograms -> grams ---------------------------
    if (base %in% cfg$weight_cols) {
      kg_mask <- !is.na(df_num[[col]]) & df_num[[col]] <= 20
      if (any(kg_mask)) {
        df_num[[col]][kg_mask] <- df_num[[col]][kg_mask] * 1000
        converted_units <- converted_units + sum(kg_mask)
        log_info("  validate_numeric: %d value(s) in '%s' converted kg -> g.",
                 sum(kg_mask), col)
      }

      # -- Post-conversion plausibility check (warning only, data unchanged) ---
      implaus_mask <- !is.na(df_num[[col]]) &
                      (df_num[[col]] < 100 | df_num[[col]] > 5000)
      if (any(implaus_mask)) {
        n_low  <- sum(!is.na(df_num[[col]]) & df_num[[col]] < 100)
        n_high <- sum(!is.na(df_num[[col]]) & df_num[[col]] > 5000)
        log_warn(
          "  validate_numeric: '%s' has %d implausible value(s) after conversion (%d < 100 g, %d > 5000 g). Data retained.",
          col, sum(implaus_mask), n_low, n_high
        )
        implausible_weight_log <- c(
          implausible_weight_log,
          sprintf("  %-45s : %d value(s) outside [100, 5000] g  (%d < 100 g, %d > 5000 g)  [data retained]",
                  col, sum(implaus_mask), n_low, n_high)
        )
      }
    }

    # -- 2b. Unit rescue: matageyrs stored in hours -> years --------------------
    # The Neotree app sometimes auto-calculates maternal age from DOB and stores
    # it in hours inside the matageyrs column (which should hold years).
    # Any value > 200 is unambiguously in hours: the oldest confirmed mother is
    # well under 200 years, and 200 hours is only ~8 days old.
    # Divisor is 8766 = 365.25 * 24 (hours per average year), matching the
    # matagedate -> years conversion below so both maternal-age fields agree.
    if (base == "matageyrs") {
      hours_mask <- !is.na(df_num[[col]]) & df_num[[col]] > 200
      if (any(hours_mask)) {
        n_rescued          <- sum(hours_mask)
        df_num[[col]][hours_mask] <- round(df_num[[col]][hours_mask] / 8766, 1)
        rescued_matageyrs  <- rescued_matageyrs + n_rescued
        log_info(
          "  validate_numeric: %d matageyrs value(s) rescued from hours to years (/ 8766).",
          n_rescued
        )
        matageyrs_rescue_log <- c(
          matageyrs_rescue_log,
          sprintf("  %d value(s) > 200 detected as hours and converted to years (/ 8766).",
                  n_rescued)
        )
      }
    }

    # -- 3. Range validation ----------------------------------------------------
    rng <- range_map[[base]]
    if (!is.null(rng)) {
      mask_low  <- !is.na(df_num[[col]]) &
                   !is.na(rng$min)        &
                   df_num[[col]] < rng$min
      mask_high <- !is.na(df_num[[col]]) &
                   !is.na(rng$max)        &
                   df_num[[col]] > rng$max
      mask      <- mask_low | mask_high

      n_oor <- sum(mask)
      if (n_oor > 0) {
        df_num[[col]][mask] <- NA_real_
        out_of_range        <- out_of_range + n_oor
        range_detail_log    <- c(
          range_detail_log,
          sprintf("  %-45s : %d value(s) outside [%s, %s] set to NA",
                  col,
                  n_oor,
                  ifelse(is.na(rng$min), "-Inf", as.character(rng$min)),
                  ifelse(is.na(rng$max), "+Inf", as.character(rng$max)))
        )
      }
    }
  }

  # -- 3b. Maternal age: derive years from auto-calculated matagedate (hours) --
  # `matagedate` is the Neotree app's auto-calculated maternal age (raw_data_type
  # "period"), stored in HOURS -- NOT years. It exists on the KCH/MWI deliveries
  # form only. We add a PARALLEL years column `mat_age_date_years` (raw matagedate
  # is left untouched, still in hours) so Module 15 can coalesce it with
  # `matageyrs` into a single harmonised maternal-age variable.
  #
  # The derived years value is plausibility-filtered on the SAME 9-60 window used
  # for matageyrs, and out-of-range values are set to NA and counted HERE, so all
  # implausible maternal ages are handled and reported in this one module (and are
  # subsequently NA-reason-coded by Module 16 like every other removed value).
  MAT_AGE_MIN    <- 9L
  MAT_AGE_MAX    <- 60L
  HOURS_PER_YEAR <- 8766L   # 365.25 * 24, hours per average year
  mad_candidates <- c("matagedate.value", "matagedate")
  mad_col        <- intersect(mad_candidates, names(df_num))
  if (length(mad_col) >= 1) {
    mad_col   <- mad_col[1]
    mad_hours <- suppressWarnings(as.numeric(as.character(df_num[[mad_col]])))
    mad_years <- round(mad_hours / HOURS_PER_YEAR)

    oor_mask  <- !is.na(mad_years) & (mad_years < MAT_AGE_MIN | mad_years > MAT_AGE_MAX)
    mat_age_date_implaus <- sum(oor_mask)
    mad_years[oor_mask]  <- NA_real_

    df_num[["mat_age_date_years"]] <- mad_years
    mat_age_date_derived <- sum(!is.na(mad_years))

    log_info(
      paste("  validate_numeric: mat_age_date_years derived from '%s' (hours / %d):",
            "%d valid, %d implausible (<%d | >%d yrs) set to NA."),
      mad_col, HOURS_PER_YEAR, mat_age_date_derived, mat_age_date_implaus,
      MAT_AGE_MIN, MAT_AGE_MAX
    )
    mat_age_date_log <- c(
      sprintf("  Source column            : %s  (stored in hours)", mad_col),
      sprintf("  Conversion               : round(value / %d)   [365.25 * 24]", HOURS_PER_YEAR),
      sprintf("  Plausible window         : [%d, %d] years", MAT_AGE_MIN, MAT_AGE_MAX),
      sprintf("  Valid derived values     : %d", mat_age_date_derived),
      sprintf("  Implausible set to NA    : %d", mat_age_date_implaus),
      "  Note: raw 'matagedate' is left unchanged (still hours); the combined",
      "  maternal-age variable is assembled in Module 15."
    )
  }

  # -- 4. Deduplication ------------------------------------------------------
  n_before <- nrow(df_num)
  df_num   <- dplyr::distinct(df_num, uid, facility, .keep_all = TRUE)
  n_dedup  <- n_before - nrow(df_num)

  log_info(
    paste("validate_numeric: %d non-numeric removed | %d units converted (kg->g) |",
          "%d matageyrs rescued (hours->years) | %d matagedate->years derived |",
          "%d out-of-range set to NA | %d duplicates removed"),
    removed_non_numeric, converted_units, rescued_matageyrs, mat_age_date_derived,
    out_of_range, n_dedup
  )

  # -- Write report ------------------------------------------------------------
  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c(
        "Module 11 - Numeric Validation Report",
        "======================================",
        sprintf("Run timestamp               : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                     : %s", toupper(cfg$country)),
        sprintf("Dataset                     : %s", cfg$dataset),
        "",
        sprintf("Numeric columns checked     : %d", length(setdiff(num_cols, key_cols))),
        sprintf("Range lookup entries        : %d", length(range_map)),
        sprintf("Non-numeric values -> NA    : %d", removed_non_numeric),
        sprintf("Values converted kg -> g    : %d", converted_units),
        sprintf("matageyrs rescued (hrs->yrs): %d", rescued_matageyrs),
        sprintf("matagedate->years derived   : %d", mat_age_date_derived),
        sprintf("matagedate implausible ->NA : %d", mat_age_date_implaus),
        sprintf("Out-of-range values -> NA   : %d", out_of_range),
        sprintf("Duplicate rows removed      : %d", n_dedup),
        sprintf("Final numeric rows          : %d", nrow(df_num)),
        sprintf("Final numeric cols          : %d", ncol(df_num)),
        ""
      )

      if (length(range_detail_log) > 0) {
        lines <- c(lines,
                   "=== Per-Column Out-of-Range Violations ===",
                   range_detail_log,
                   "")
      }

      if (length(cfg$weight_cols) > 0) {
        lines <- c(lines,
                   "=== Weight Columns (kg -> g conversion applied) ===",
                   paste0("  ", cfg$weight_cols),
                   "")
      }

      if (length(matageyrs_rescue_log) > 0) {
        lines <- c(lines,
                   "=== matageyrs Unit Rescue (hours -> years) ===",
                   "  Threshold: values > 200 treated as hours (auto-calculated from DOB).",
                   "  Conversion: value / 8766, rounded to 1 decimal place.",
                   "  Source: Neotree app stores maternal age in hours when DOB is entered.",
                   matageyrs_rescue_log,
                   "")
      }

      if (length(mat_age_date_log) > 0) {
        lines <- c(lines,
                   "=== matagedate -> mat_age_date_years (hours -> years) ===",
                   "  matagedate is the auto-calculated maternal age, stored in hours.",
                   "  A parallel years column is derived; raw matagedate is left unchanged.",
                   "  Combined with matageyrs into mat_age_years_combined in Module 15.",
                   mat_age_date_log,
                   "")
      }

      if (length(implausible_weight_log) > 0) {
        lines <- c(lines,
                   "=== Implausible Weight Values After Conversion [WARNING -- data retained] ===",
                   "  Plausible range: 100 g (min) to 5000 g (max).",
                   "  Values outside this range may indicate a unit conversion failure.",
                   implausible_weight_log,
                   "")
      } else if (length(cfg$weight_cols) > 0) {
        lines <- c(lines,
                   "=== Implausible Weight Values After Conversion ===",
                   "  All weight values within plausible range [100, 5000] g.",
                   "")
      }

      writeLines(lines, report_filepath)
    }, error = function(e) {
      log_warn("Could not write Module 11 report: %s", e$message)
    })
  }

  return(df_num)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "11_numeric_validation_report.txt") else NULL

df_numeric <- validate_numeric(df, cfg, report_filepath = report_path)

log_info("Module 11 complete. Numeric sub-frame: %d rows x %d cols.",
         nrow(df_numeric), ncol(df_numeric))
