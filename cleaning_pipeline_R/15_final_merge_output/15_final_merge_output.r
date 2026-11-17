# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 15: Final Merge and Output
# =============================================================================
# PURPOSE:
#   Merges the validated sub-frames produced by Modules 11-14 and a passthrough
#   sub-frame of untyped columns into a single clean dataset, adds derived
#   columns and writes the output files.
#
# METHOD:
#   Sub-frames merged (left joins on facility, uid, uniquekey):
#     df_numeric       - validated numeric columns (Module 11)
#     df_boolean       - validated boolean columns (Module 12)
#     df_categorical   - validated categorical/object columns (Module 13)
#     df_datetime      - validated datetime columns (Module 14)
#     df_non_validated - .value / .valuedischarge columns and bare columns that
#                        are not in any type list (cfg$num, bool, cat, obj, dt),
#                        kept as character
#
#   Deduplication:
#     Each sub-frame, and then the merged result, is deduplicated: where
#     several records share the same key, the record with the fewest missing
#     values is kept.  The key is (uid, facility), or (uid, facility,
#     uniquekey) when cfg$skip_dedup_stage2 is TRUE.
#
#   Suffix stripping:
#     After merging, .value and .valuedischarge suffixes are stripped from all
#     column names (e.g. "age", "birthweight", "datetimeadmission").
#
#   Derived weight columns (originals kept):
#       birthweight_g      <- coalesce(birthweight, bwt, bwtdis)  [always]
#       admission_weight_g <- admissionweight                     [if present]
#       discharge_weight_g <- dischweight                         [if present]
#     See derive_weight_columns().
#
#   Derived maternal-age columns (only when a source column is present):
#     mat_age_years_combined <- coalesce(matageyrs, mat_age_date_years)
#     mat_age_source         <- "matageyrs" | "matagedate_derived" | "none"
#     See derive_maternal_age_columns().
#
#   Derived antenatal care category (only when Module 05 wrote
#   antenatalcare_source):
#     antenatalcare_category <- "none" (0 visits) | "1_3" | "ge4" (4 or more)
#     from the final antenatalcare count; a row with no count and source
#     raw_range_label ("More than 4/8 ANC visits") is "ge4".
#     See derive_antenatalcare_columns().
#
#   Datetime format:
#     POSIXct columns are formatted as "YYYY-MM-DD HH:MM:SS" in the CSV.
#
# INPUTS:
#   df_numeric, df_boolean, df_categorical, df_datetime - sub-frames from
#     validation modules 11-14
#   df  - full stage-1 data.frame (after Module 10), used to build the
#         df_non_validated passthrough sub-frame
#   cfg - configuration list (output paths, feature lists)
#
# OUTPUTS:
#   df_clean  - final merged, deduplicated dataset
#   CSV file  - cfg$output_csv
#   RDS file  - cfg$output_rds
#   Reports   - cfg$report_dir/15_final_merge_summary.txt
#               cfg$report_dir/15b_maternal_age_summary.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("15_final_merge_output/15_final_merge_output.r")
# =============================================================================

source("00_setup/00_setup.r")

# -- Helper: base name (strip .value / .valuedischarge suffix) -----------------
base_name_col <- function(col) {
  col <- sub("\\.valuedischarge$", "", col)
  col <- sub("\\.value$",          "", col)
  return(col)
}

# -- Function: smart deduplication on keys ------------------------------------

#' Deduplicate by Primary Keys, Retaining Most Complete Record
#'
#' Where multiple rows share the same primary key combination, retains the
#' record with the fewest missing values across all non-key columns.
#'
#' @param df       A data.frame.
#' @param key_cols Character vector of primary key column names.
#' @return         Deduplicated data.frame.
dedup_keep_most_complete <- function(df, key_cols) {

  key_cols_present <- intersect(key_cols, names(df))
  if (length(key_cols_present) == 0) return(dplyr::distinct(df))

  non_key_cols <- setdiff(names(df), key_cols_present)

  df$.missing_count <- rowSums(is.na(df[, non_key_cols, drop = FALSE]))
  df$.row_index     <- seq_len(nrow(df))

  df_dedup <- df %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(key_cols_present))) %>%
    dplyr::slice_min(.missing_count, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::select(-.missing_count, -.row_index)

  n_removed <- nrow(df) - nrow(df_dedup)
  if (n_removed > 0)
    log_info(
      "  dedup_keep_most_complete: %d near-duplicate record(s) removed.", n_removed
    )

  return(df_dedup)
}

# -- Function: build non-validated passthrough sub-frame ----------------------

#' Build Non-Validated Passthrough Sub-Frame
#'
#' Collects two categories of columns from df_full that are not in any typed
#' feature list (cfg$num, bool, cat, obj, dt):
#'
#'   1. .value / .valuedischarge columns.
#'
#'   2. Bare (no-dot) columns -- system/metadata/computed fields without a
#'      .value suffix (e.g. scriptid, scriptversion, transformed, timespent,
#'      agecategory).
#'
#' All collected columns are kept as character.
#'
#' @param df_full  Full stage-1 data.frame (after Module 10).
#' @param cfg      Config list with feature-list vectors.
#' @return         Sub-frame of untyped columns (character), or NULL.
build_non_validated <- function(df_full, cfg) {

  key_cols <- c("facility", "uid", "uniquekey")

  # All columns that ARE typed (in any feature list)
  typed_cols <- unique(c(cfg$num, cfg$bool, cfg$cat, cfg$obj, cfg$dt))

  # Helper: is 'col' already covered by a typed list?
  # Checks the column name itself, its base name, and the base + ".value"
  # so that bare columns whose .value counterpart is typed are excluded.
  in_any_list <- function(col) {
    base <- base_name_col(col)
    col %in% typed_cols ||
    base %in% typed_cols ||
    paste0(base, ".value") %in% typed_cols
  }

  # -- Category 1: untyped .value / .valuedischarge columns -----------------
  value_cols <- grep("\\.value$|\\.valuedischarge$", names(df_full), value = TRUE)
  value_cols <- setdiff(value_cols, key_cols)
  untyped_value_cols <- value_cols[!vapply(value_cols, in_any_list, logical(1))]

  # -- Category 2: bare (no-dot) columns not in any typed list ---------------
  # System / metadata / computed fields (e.g. scriptid, timespent,
  # agecategory) that have no .value suffix.
  bare_cols <- names(df_full)[!grepl("\\.", names(df_full), fixed = TRUE)]
  bare_cols <- setdiff(bare_cols, key_cols)
  bare_untyped_cols <- bare_cols[!vapply(bare_cols, in_any_list, logical(1))]

  untyped_cols <- c(untyped_value_cols, bare_untyped_cols)

  if (length(untyped_cols) == 0) {
    log_info("build_non_validated: no untyped columns found.")
    return(NULL)
  }

  keep_cols <- unique(c(key_cols, untyped_cols))
  keep_cols <- intersect(keep_cols, names(df_full))

  df_nv <- df_full[, keep_cols, drop = FALSE]
  # Ensure all untyped cols are character
  for (col in untyped_cols) {
    if (col %in% names(df_nv))
      df_nv[[col]] <- as.character(df_nv[[col]])
  }

  log_info(
    "build_non_validated: %d untyped column(s) retained as passthrough (%d .value, %d bare).",
    length(untyped_cols), length(untyped_value_cols), length(bare_untyped_cols)
  )
  return(df_nv)
}

# -- Function: format POSIXct columns as character for CSV export -------------

#' Format Datetime Columns for CSV Export
#'
#' Converts all POSIXct/POSIXlt columns in df to character using the format
#' "YYYY-MM-DD HH:MM:SS" (readr's default would be ISO 8601,
#' "YYYY-MM-DDTHH:MM:SSZ").
#'
#' @param df  A data.frame.
#' @return    Data.frame with POSIXct columns replaced by formatted character.
format_datetimes_for_csv <- function(df) {
  for (col in names(df)) {
    if (inherits(df[[col]], c("POSIXct", "POSIXlt"))) {
      df[[col]] <- format(df[[col]], "%Y-%m-%d %H:%M:%S", tz = "UTC")
      df[[col]][df[[col]] == "NA"] <- NA_character_
    }
  }
  return(df)
}

# -- Function: derive canonical weight columns --------------------------------

#' Derive canonical, concept-grouped weight columns
#'
#' Derive canonical, concept-grouped weight columns
#'
#' Adds up to three derived columns while leaving all original weight columns
#' unchanged:
#'   birthweight_g      <- coalesce(birthweight, bwt, bwtdis)  [always emitted]
#'   admission_weight_g <- admissionweight                     [if source present]
#'   discharge_weight_g <- dischweight                         [if source present]
#'
#' birthweight, bwt and bwtdis are three names for the same concept (birth
#' weight in grams) used by different form/script versions.  Admission weight
#' and discharge/last-recorded weight are different concepts and are not
#' folded into birth weight.
#'
#' birthweight_g is emitted in every dataset (NA-filled where no source column
#' is present).  admission_weight_g and discharge_weight_g are emitted only
#' where their source column is present.
#'
#' Disagreement guard: logs a warning if, on any row, two birth-weight source
#' columns are both present and differ by more than DISAGREE_TOL_G grams.
#'
#' Unit guard: any source value > 0 and <= KG_THRESHOLD is treated as
#' kilograms and multiplied by 1000.  Module 11 does the same conversion on
#' dictionary-flagged weight columns only; repeating it here covers source
#' columns that are not flagged, so the derived column is always in grams.
#'
#' @param df   Final merged data.frame (bare column names, weights in grams).
#' @param cfg  Config list (unused; kept for interface consistency).
#' @return     df with the derived weight column(s) appended.
derive_weight_columns <- function(df, cfg) {

  DISAGREE_TOL_G <- 1    # grams; sources expected identical where they overlap
  KG_THRESHOLD   <- 20   # values <= this are kilograms -> convert to grams

  n <- nrow(df)

  weight_num <- function(col) {
    if (!(col %in% names(df))) return(NULL)
    x  <- suppressWarnings(as.numeric(df[[col]]))
    kg <- !is.na(x) & x > 0 & x <= KG_THRESHOLD
    if (any(kg)) x[kg] <- x[kg] * 1000
    x
  }

  # ---- Birth weight: birthweight / bwt / bwtdis (same concept) -------------
  bw_order   <- c("birthweight", "bwt", "bwtdis")   # coalesce priority order
  bw_present <- bw_order[bw_order %in% names(df)]
  bw_vals    <- lapply(bw_present, weight_num)

  if (length(bw_vals) == 0) {
    df$birthweight_g <- NA_real_                     # emitted even with no source
  } else {
    df$birthweight_g <- Reduce(function(a, b) ifelse(is.na(a), b, a), bw_vals)

    if (length(bw_vals) >= 2) {
      m   <- do.call(cbind, bw_vals)
      rng <- apply(m, 1, function(r) {
        v <- r[!is.na(r)]
        if (length(v) < 2) 0 else max(v) - min(v)
      })
      n_disagree <- sum(rng > DISAGREE_TOL_G, na.rm = TRUE)
      if (n_disagree > 0) {
        log_warn(
          paste0("derive_weight_columns: %d row(s) have disagreeing birth-weight ",
                 "sources (> %g g) among {%s}; birthweight_g used the first ",
                 "non-NA source in priority order. Review these rows."),
          n_disagree, DISAGREE_TOL_G, paste(bw_present, collapse = ", "))
      } else {
        log_info(
          "derive_weight_columns: birth-weight sources {%s} agree on all overlapping rows.",
          paste(bw_present, collapse = ", "))
      }
    }
  }
  log_info(
    "derive_weight_columns: birthweight_g non-missing = %d / %d (sources: %s).",
    sum(!is.na(df$birthweight_g)), n,
    if (length(bw_present)) paste(bw_present, collapse = ", ") else "none")

  # ---- Admission weight (distinct concept; emitted only if captured) -------
  if ("admissionweight" %in% names(df)) {
    df$admission_weight_g <- weight_num("admissionweight")
    log_info("derive_weight_columns: admission_weight_g non-missing = %d / %d.",
             sum(!is.na(df$admission_weight_g)), n)
  }

  # ---- Discharge / last-recorded weight (distinct concept) -----------------
  if ("dischweight" %in% names(df)) {
    df$discharge_weight_g <- weight_num("dischweight")
    log_info("derive_weight_columns: discharge_weight_g non-missing = %d / %d.",
             sum(!is.na(df$discharge_weight_g)), n)
  }

  return(df)
}

# -- Function: derive canonical maternal-age column ---------------------------

#' Derive a single harmonised maternal-age variable
#'
#' Derive a single harmonised maternal-age variable
#'
#' Adds two columns while leaving all source columns unchanged:
#'   mat_age_years_combined <- coalesce(matageyrs, mat_age_date_years)  [numeric]
#'   mat_age_source         <- "matageyrs" | "matagedate_derived" | "none"
#'
#' Maternal age has two sources:
#'   * matageyrs           - manually entered whole years, range-validated in
#'                           Module 11.
#'   * mat_age_date_years  - derived in Module 11 from matagedate (a calculated
#'                           age stored in hours), with a 9-60 year filter.
#' Both inputs are in years and range-validated on entry to this function.
#'
#' Priority: matageyrs is used when both are present.
#'
#' Disagreement guard: rows where both sources are present and differ by more
#' than DISAGREE_TOL_YRS are counted and logged.  matageyrs is still the value
#' used.
#'
#' The columns are emitted only when at least one source column is present, so
#' datasets without maternal-age fields are not given empty columns.
#'
#' @param df   Final merged data.frame (bare column names, ages in years).
#' @param cfg  Config list (country, dataset, report_dir).
#' @return     df with mat_age_years_combined and mat_age_source appended.
derive_maternal_age_columns <- function(df, cfg) {

  DISAGREE_TOL_YRS <- 1   # years; sources treated as agreeing within +/- 1 yr

  yrs_col <- intersect(c("matageyrs", "matageyrs.value"),        names(df))
  mad_col <- intersect(c("mat_age_date_years"),                  names(df))

  if (length(yrs_col) == 0 && length(mad_col) == 0) {
    log_info("derive_maternal_age_columns: no maternal-age source columns; skipped.")
    return(df)
  }

  n   <- nrow(df)
  yrs <- if (length(yrs_col)) suppressWarnings(as.numeric(df[[yrs_col[1]]])) else rep(NA_real_, n)
  mad <- if (length(mad_col)) suppressWarnings(as.numeric(df[[mad_col[1]]])) else rep(NA_real_, n)

  combined <- ifelse(!is.na(yrs), yrs, mad)
  source   <- ifelse(!is.na(yrs), "matageyrs",
              ifelse(!is.na(mad), "matagedate_derived", "none"))

  df$mat_age_years_combined <- combined
  df$mat_age_source         <- source

  n_yrs  <- sum(source == "matageyrs")
  n_mad  <- sum(source == "matagedate_derived")
  n_none <- sum(source == "none")

  both       <- !is.na(yrs) & !is.na(mad)
  n_both     <- sum(both)
  n_disagree <- sum(both & abs(yrs - mad) > DISAGREE_TOL_YRS)
  disagree_pct <- if (n_both > 0) 100 * n_disagree / n_both else 0

  log_info(
    paste0("derive_maternal_age_columns: combined non-missing = %d / %d ",
           "(matageyrs=%d, matagedate_derived=%d, none=%d)."),
    sum(!is.na(combined)), n, n_yrs, n_mad, n_none)

  if (n_both > 0) {
    if (n_disagree > 0) {
      log_warn(
        paste0("derive_maternal_age_columns: %d of %d row(s) with BOTH maternal-age ",
               "sources disagree by > %g year(s) (%.1f%%); matageyrs was kept. ",
               "Review these rows."),
        n_disagree, n_both, DISAGREE_TOL_YRS, disagree_pct)
    } else {
      log_info(
        "derive_maternal_age_columns: all %d overlapping row(s) agree within %g year(s).",
        n_both, DISAGREE_TOL_YRS)
    }
  }

  # -- Dedicated report ------------------------------------------------------
  report_path <- if (!is.null(cfg$report_dir))
    file.path(cfg$report_dir, "15b_maternal_age_summary.txt") else NULL
  if (!is.null(report_path)) {
    tryCatch({
      srcs_present <- paste(c(
        if (length(yrs_col)) "matageyrs",
        if (length(mad_col)) "mat_age_date_years"
      ), collapse = ", ")
      writeLines(c(
        "Module 15 - Maternal Age Harmonisation Summary",
        "==============================================",
        sprintf("Country                       : %s", toupper(cfg$country)),
        sprintf("Dataset                       : %s", cfg$dataset),
        sprintf("Rows                          : %d", n),
        sprintf("Source columns present        : %s", srcs_present),
        "",
        sprintf("mat_age_years_combined non-NA : %d (%.1f%%)",
                sum(!is.na(combined)), 100 * mean(!is.na(combined))),
        "",
        "mat_age_source breakdown:",
        sprintf("  matageyrs                   : %d", n_yrs),
        sprintf("  matagedate_derived          : %d", n_mad),
        sprintf("  none                        : %d", n_none),
        "",
        sprintf("Rows with BOTH sources        : %d", n_both),
        sprintf("  disagree > %g year(s)        : %d (%.1f%% of overlap)",
                DISAGREE_TOL_YRS, n_disagree, disagree_pct),
        "",
        "Priority: matageyrs (manual) over matagedate_derived (auto-calculated).",
        "Disagreements are counted, never silently overwritten.",
        sprintf("Run timestamp                 : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      ), report_path)
    }, error = function(e)
      log_warn("Could not write maternal age summary report: %s", e$message))
  }

  return(df)
}

# -- Function: derive antenatal care category ---------------------------------

#' Derive the antenatal care visit category
#'
#' antenatalcare_category is "none" for 0 visits, "1_3" for 1 to 3 and "ge4"
#' for 4 or more, taken from the final antenatalcare count.  Where the count
#' is missing and antenatalcare_source is "raw_range_label", the category is
#' "ge4".  The count itself is never imputed.
#'
#' @param df   Final merged data.frame (bare column names).
#' @param cfg  Config list (unused; kept for interface consistency).
#' @return     df with antenatalcare_category appended, or df unchanged when
#'             antenatalcare or antenatalcare_source is absent.
derive_antenatalcare_columns <- function(df, cfg) {
  if (!all(c("antenatalcare", "antenatalcare_source") %in% names(df))) {
    return(df)
  }
  n <- suppressWarnings(as.numeric(df$antenatalcare))
  n[!is.finite(n) | n < 0 | n != floor(n)] <- NA_real_
  category <- ifelse(is.na(n), NA_character_,
              ifelse(n == 0, "none", ifelse(n <= 3, "1_3", "ge4")))
  range_only <- is.na(n) & !is.na(df$antenatalcare_source) &
                df$antenatalcare_source == "raw_range_label"
  category[range_only] <- "ge4"
  df$antenatalcare_category <- category

  log_info(
    paste0("derive_antenatalcare_columns: category none=%d, 1_3=%d, ge4=%d ",
           "(of which from a range label=%d), missing=%d."),
    sum(category == "none", na.rm = TRUE), sum(category == "1_3", na.rm = TRUE),
    sum(category == "ge4",  na.rm = TRUE), sum(range_only), sum(is.na(category))
  )
  df
}

# -- Function: merge validated sub-frames -------------------------------------

#' Merge Validated Sub-Frames into Final Clean Dataset
#'
#' @param df_numeric      Numeric sub-frame (Module 11).
#' @param df_boolean      Boolean sub-frame (Module 12).
#' @param df_categorical  Categorical sub-frame (Module 13).
#' @param df_datetime     Datetime sub-frame (Module 14).
#' @param df_full         Full stage-1 data.frame for passthrough construction.
#' @param cfg             Config list (output paths, feature lists).
#' @return                Final merged, deduplicated data.frame.
merge_and_output <- function(df_numeric, df_boolean, df_categorical,
                             df_datetime, df_full, cfg) {

  key_cols <- c("facility", "uid", "uniquekey")

  # -- Deduplication key: patient-level vs. visit-level ----------------------
  # When Stage 2 patient-level dedup is disabled (cfg$skip_dedup_stage2 = TRUE),
  # sub-frame and final dedup use all three primary keys (uid + facility +
  # uniquekey), so that each distinct visit record is preserved while rows with
  # the same uid/facility/uniquekey are still collapsed.
  # Otherwise the (uid, facility) patient-level key applies.
  dedup_keys <- if (isTRUE(cfg$skip_dedup_stage2))
    c("uid", "facility", "uniquekey")
  else
    c("uid", "facility")

  # -- Build non-validated passthrough sub-frame -----------------------------
  df_non_validated <- build_non_validated(df_full, cfg)

  # -- Apply smart deduplication to each sub-frame before merging ------------
  log_info("Deduplicating sub-frames before merge...")
  df_numeric     <- dedup_keep_most_complete(df_numeric,     dedup_keys)
  df_boolean     <- dedup_keep_most_complete(df_boolean,     dedup_keys)
  df_categorical <- dedup_keep_most_complete(df_categorical, dedup_keys)
  df_datetime    <- dedup_keep_most_complete(df_datetime,    dedup_keys)
  if (!is.null(df_non_validated))
    df_non_validated <- dedup_keep_most_complete(df_non_validated, dedup_keys)

  # -- Merge all sub-frames on primary keys ----------------------------------
  log_info("Merging sub-frames...")

  # Start with numeric
  df_clean <- df_numeric

  # Join boolean
  bool_extra <- setdiff(names(df_boolean), names(df_clean))
  if (length(bool_extra) > 0) {
    df_clean <- dplyr::left_join(
      df_clean,
      df_boolean[, c(key_cols, bool_extra), drop = FALSE],
      by = key_cols
    )
  }

  # Join categorical
  cat_extra <- setdiff(names(df_categorical), names(df_clean))
  if (length(cat_extra) > 0) {
    df_clean <- dplyr::left_join(
      df_clean,
      df_categorical[, c(key_cols, cat_extra), drop = FALSE],
      by = key_cols
    )
  }

  # Join datetime
  dt_extra <- setdiff(names(df_datetime), names(df_clean))
  if (length(dt_extra) > 0) {
    df_clean <- dplyr::left_join(
      df_clean,
      df_datetime[, c(key_cols, dt_extra), drop = FALSE],
      by = key_cols
    )
  }

  # Join non-validated passthrough
  if (!is.null(df_non_validated)) {
    nv_extra <- setdiff(names(df_non_validated), names(df_clean))
    if (length(nv_extra) > 0) {
      df_clean <- dplyr::left_join(
        df_clean,
        df_non_validated[, c(key_cols, nv_extra), drop = FALSE],
        by = key_cols
      )
      log_info("Joined %d non-validated passthrough column(s).", length(nv_extra))
    }
  }

  # -- Final deduplication ---------------------------------------------------
  log_info("Applying final deduplication on merged dataset...")
  df_clean <- dedup_keep_most_complete(df_clean, dedup_keys)

  # -- Strip .value / .valuedischarge suffixes from column names -------------
  # Applied here, after all validation modules have finished, because those
  # modules match column names against cfg$num / cfg$bool / etc., which use
  # the suffixed form (e.g. "age.value").
  original_col_names <- names(df_clean)
  names(df_clean) <- sub("\\.valuedischarge$", "", names(df_clean))
  names(df_clean) <- sub("\\.value$",          "", names(df_clean))
  n_stripped <- sum(names(df_clean) != original_col_names)
  log_info("Stripped .value/.valuedischarge suffixes: %d column(s) renamed.", n_stripped)

  # -- Derive canonical weight columns (concept-grouped coalesce) ------------
  # Runs after suffix stripping so it can address bare names (birthweight, bwt,
  # bwtdis, admissionweight, dischweight) and before output so the derived
  # columns are written to CSV/RDS and picked up by Module 16 NA coding.
  df_clean <- derive_weight_columns(df_clean, cfg)

  # -- Derive harmonised maternal-age column (coalesce matageyrs + matagedate) --
  # Runs after suffix stripping (so matageyrs.value -> matageyrs) and before
  # output so mat_age_years_combined / mat_age_source are written to CSV/RDS
  # and NA-reason-coded by Module 16.  Does nothing when no source column is
  # present.
  df_clean <- derive_maternal_age_columns(df_clean, cfg)

  # -- Derive antenatal care category (needs antenatalcare_source from Module 05)
  df_clean <- derive_antenatalcare_columns(df_clean, cfg)

  log_info(
    "Final merged dataset: %d rows x %d columns.", nrow(df_clean), ncol(df_clean)
  )

  # -- Save outputs ----------------------------------------------------------
  # Format POSIXct as "YYYY-MM-DD HH:MM:SS" before writing the CSV.
  df_clean_csv <- format_datetimes_for_csv(df_clean)

  # Strip a trailing ".000" millisecond suffix from every character column, so
  # that datetimes held as character also read "YYYY-MM-DD HH:MM:SS".
  df_clean_csv <- as.data.frame(lapply(df_clean_csv, function(x) {
    if (is.character(x)) gsub("\\.000$", "", x) else x
  }), stringsAsFactors = FALSE, check.names = FALSE)

  # PII guard: stops before anything is written if the 00a marker is missing
  # or stale, or if any PII column or value is present.  Called outside the
  # tryCatch below so that a failure stops the run instead of being logged as
  # a warning.  The RDS written next holds the same content as this CSV.
  assert_pii_removed(df_clean_csv, stage = "15_cleaned_output")

  tryCatch({
    readr::write_csv(df_clean_csv, cfg$output_csv, na = "")
    log_info("CSV saved: %s", cfg$output_csv)
  }, error = function(e) log_warn("Could not save CSV: %s", e$message))

  tryCatch({
    saveRDS(df_clean, cfg$output_rds)
    log_info("RDS saved: %s", cfg$output_rds)
  }, error = function(e) log_warn("Could not save RDS: %s", e$message))

  # -- Summary report --------------------------------------------------------
  report_path <- if (!is.null(cfg$report_dir))
    file.path(cfg$report_dir, "15_final_merge_summary.txt") else NULL

  if (!is.null(report_path)) {
    tryCatch({
      lines <- c(
        "Final Merge & Output Summary",
        "============================",
        sprintf("Country              : %s", toupper(cfg$country)),
        sprintf("Dataset              : %s", cfg$dataset),
        sprintf("Data source          : %s", cfg$data_source),
        sprintf("Input CSV            : %s", cfg$csv_filepath),
        sprintf("Output CSV           : %s", cfg$output_csv),
        sprintf("Output RDS           : %s", cfg$output_rds),
        sprintf("Final rows           : %d", nrow(df_clean)),
        sprintf("Final columns        : %d", ncol(df_clean)),
        sprintf("Non-validated cols   : %d",
                if (!is.null(df_non_validated))
                  length(setdiff(names(df_non_validated), key_cols))
                else 0L),
        sprintf("Run timestamp        : %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      )
      writeLines(lines, report_path)
    }, error = function(e) {
      log_warn("Could not write final summary report: %s", e$message)
    })
  }

  return(df_clean)
}

# -- Run -----------------------------------------------------------------------
df_clean <- merge_and_output(
  df_numeric     = df_numeric,
  df_boolean     = df_boolean,
  df_categorical = df_categorical,
  df_datetime    = df_datetime,
  df_full        = df,
  cfg            = cfg
)

log_info("Module 15 complete - Pipeline finished successfully.")
log_info("Total runtime: %.1f seconds.", as.numeric(difftime(Sys.time(),
         get0("pipeline_start", envir = .GlobalEnv, ifnotfound = Sys.time()),
         units = "secs")))
