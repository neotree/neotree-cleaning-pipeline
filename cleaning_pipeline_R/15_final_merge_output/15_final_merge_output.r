# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 15: Final Merge and Output
# =============================================================================
# PURPOSE:
#   Merges the five validated sub-frames produced by Modules 11-14 plus a
#   passthrough sub-frame of untyped columns into a single clean dataset.
#
#   SUB-FRAMES MERGED:
#     df_numeric      - validated numeric columns (Module 11)
#     df_boolean      - validated boolean columns (Module 12)
#     df_categorical  - validated categorical/object columns (Module 13)
#     df_datetime     - validated datetime columns (Module 14)
#     df_non_validated - passthrough for all .value / .valuedischarge columns
#                        that were NOT assigned to any type list (cfg$num, bool,
#                        cat, obj, dt).  Mirrors the Jupyter pipeline's
#                        df_non_validated sub-frame, which ensures no raw
#                        .value column is silently dropped from the output.
#
#   SMART DEDUPLICATION:
#     Before merging, each sub-frame is deduplicated: where multiple records
#     share the same (uid, facility) pair, only the record with the fewest
#     missing values is retained (most-complete-record strategy).
#     A final deduplication is applied to the merged result.
#
#   SUFFIX STRIPPING:
#     After merging, .value and .valuedischarge suffixes are stripped from all
#     column names so the output uses plain variable names (e.g. "age",
#     "birthweight", "datetimeadmission").  This mirrors the Jupyter pipeline's
#     remove_suffixes() step and is applied last so intermediate modules can
#     still match column names against cfg$num / cfg$bool / etc.
#
#   DERIVED WEIGHT COLUMNS:
#     After suffix stripping, three concept-grouped weight columns are added
#     (originals kept untouched):
#       birthweight_g      <- coalesce(birthweight, bwt, bwtdis)  [always]
#       admission_weight_g <- admissionweight                     [if present]
#       discharge_weight_g <- dischweight                         [if present]
#     birthweight, bwt and bwtdis are the same concept (birth weight in grams)
#     across form versions; admission and discharge weight are distinct concepts
#     and are never folded in.  See derive_weight_columns() for the disagreement
#     and unit guards.
#
#   DERIVED MATERNAL-AGE COLUMNS (deliveries / maternal-outcomes files only):
#     mat_age_years_combined <- coalesce(matageyrs, mat_age_date_years)
#     mat_age_source         <- "matageyrs" | "matagedate_derived" | "none"
#     matageyrs is the manual whole-years field (range-validated 9-60 in Module
#     11); mat_age_date_years is the auto-calculated maternal age that Module 11
#     converted from hours to years (same 9-60 filter). matageyrs takes priority;
#     rows where both are present and differ by > 1 year are counted and logged
#     (never overwritten). Emitted only when a source column is present, so ZIM
#     (matageyrs only) and MWI (both) share one combined schema. Reported in
#     15b_maternal_age_summary.txt. See derive_maternal_age_columns().
#
#   DATETIME FORMAT:
#     POSIXct columns are formatted as "YYYY-MM-DD HH:MM:SS" before CSV
#     export, matching the Jupyter/pandas output format.
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
#   CSV file  - saved to cfg$output_csv
#   RDS file  - saved to cfg$output_rds
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
#' Collects two categories of columns from df_full that were NOT classified
#' into any typed feature list (cfg$num, bool, cat, obj, dt):
#'
#'   1. .value / .valuedischarge columns -- untyped clinical fields not yet
#'      assigned to a validation module.  Mirrors the Jupyter pipeline's
#'      df_non_validated sub-frame.
#'
#'   2. Bare (no-dot) columns -- system/metadata/computed fields that carry no
#'      .value suffix and are therefore invisible to the .value-based passthrough.
#'      Examples: scriptid, scriptversion, transformed, timespent, agecategory.
#'      These are preserved as character to match the Python pipeline's behaviour
#'      of retaining all non-PII columns from the raw file.
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
  # These are system / metadata / computed fields (e.g. scriptid, timespent,
  # agecategory) that have no .value suffix and would otherwise be silently
  # dropped because no sub-frame captures them.
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
#' "YYYY-MM-DD HH:MM:SS", matching the Jupyter/pandas output format (which
#' differs from readr's default ISO 8601 "YYYY-MM-DDTHH:MM:SSZ").
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
#' Adds up to three derived columns while leaving all original weight columns
#' untouched:
#'   birthweight_g      <- coalesce(birthweight, bwt, bwtdis)  [ALWAYS emitted]
#'   admission_weight_g <- admissionweight                     [if source present]
#'   discharge_weight_g <- dischweight                         [if source present]
#'
#' birthweight, bwt and bwtdis are three names for the SAME concept (birth
#' weight in grams) used by different Neotree form/script versions.  They are
#' mutually exclusive across versions and identical where they co-occur, so the
#' coalesce is lossless.  Admission weight and discharge/last-recorded weight
#' are DIFFERENT clinical concepts and are never folded into birth weight.
#'
#' birthweight_g is emitted in EVERY dataset (NA-filled where no source column
#' is present), so the cleaned files share a common schema.  admission_weight_g
#' and discharge_weight_g are emitted only where their source concept is
#' captured.
#'
#' Disagreement guard: logs a warning if, on any row, two birth-weight source
#' columns are both present and differ by more than DISAGREE_TOL_G grams.
#'
#' Defensive unit guard: any source value <= KG_THRESHOLD is treated as
#' kilograms and multiplied by 1000.  Module 11 already does kg -> g on
#' dictionary-flagged weight columns; this repeats it idempotently here in case
#' a source column (e.g. bwt / bwtdis) was not flagged, so the derived column is
#' always in grams.  Plausible neonatal weights in grams are always > 20, so the
#' guard never alters a genuine gram value.
#'
#' @param df   Final merged data.frame (bare column names, weights in grams).
#' @param cfg  Config list (unused for now; kept for interface consistency).
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
#' Adds two columns while leaving all source columns untouched:
#'   mat_age_years_combined <- coalesce(matageyrs, mat_age_date_years)  [numeric]
#'   mat_age_source         <- "matageyrs" | "matagedate_derived" | "none"
#'
#' Maternal age is captured on the deliveries form in two ways:
#'   * matageyrs           - manually entered whole years (dictionary range 9-60,
#'                           already range-validated in Module 11).
#'   * matagedate          - auto-calculated from DOB, stored in HOURS. Module 11
#'                           converts it to years (mat_age_date_years) and applies
#'                           the same 9-60 plausibility filter.
#' Both inputs are therefore already in years and already range-clean here, so
#' this step is a pure, lossless coalesce plus a provenance label.
#'
#' PRIORITY: matageyrs wins when both are present. The Neotree form instructs
#' collectors to leave matageyrs blank ONLY when the auto-calculated value is
#' used, so a present matageyrs is the intended manual value.
#'
#' DISAGREEMENT GUARD: where BOTH sources are present and differ by more than
#' DISAGREE_TOL_YRS, the rows are COUNTED and logged (never silently overwritten)
#' so the discrepancy rate can be reviewed. matageyrs is still the value used.
#'
#' The columns are emitted only when at least one source column is present, so
#' non-maternal datasets (admissions, discharges, neolab, ...) are not padded
#' with empty maternal-age columns. In practice this restricts them to the
#' deliveries / maternal-outcomes files. ZIM (matageyrs only) and MWI (both)
#' therefore share the same combined schema.
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
  # For longitudinal datasets (infections, neolab) Stage 2 patient-level dedup
  # is disabled (cfg$skip_dedup_stage2 = TRUE).  In that case, sub-frame and
  # final dedup use all three primary keys (uid + facility + uniquekey) so that
  # each distinct visit record is preserved while true within-record duplicates
  # (same uid/facility/uniquekey) are still collapsed.
  # For all other datasets the standard (uid, facility) patient-level key applies.
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

  # Start with numeric (typically the largest sub-frame)
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
  # Mirrors the Jupyter pipeline's remove_suffixes() step, which strips
  # everything after the first "." in every column name.  Applied here,
  # after all validation modules have finished, so that intermediate modules
  # can still match column names against cfg$num / cfg$bool / etc.
  # (those lists use the raw_value_column form, e.g. "age.value").
  # After this point the output columns read as plain variable names
  # (e.g. "age", "birthweight", "datetimeadmission").
  original_col_names <- names(df_clean)
  names(df_clean) <- sub("\\.valuedischarge$", "", names(df_clean))
  names(df_clean) <- sub("\\.value$",          "", names(df_clean))
  n_stripped <- sum(names(df_clean) != original_col_names)
  log_info("Stripped .value/.valuedischarge suffixes: %d column(s) renamed.", n_stripped)

  # -- Derive canonical weight columns (concept-grouped coalesce) ------------
  # Runs AFTER suffix stripping so it can address bare names (birthweight, bwt,
  # bwtdis, admissionweight, dischweight) and BEFORE output so the derived
  # columns are written to CSV/RDS and picked up by Module 16 NA coding.
  # Originals are kept untouched.
  df_clean <- derive_weight_columns(df_clean, cfg)

  # -- Derive harmonised maternal-age column (coalesce matageyrs + matagedate) --
  # Runs after suffix stripping (so matageyrs.value -> matageyrs) and after the
  # weight derivation, and BEFORE output so mat_age_years_combined / mat_age_source
  # are written to CSV/RDS and NA-reason-coded by Module 16. Source columns and
  # mat_age_date_years (from Module 11) are kept untouched. No-op on non-maternal
  # datasets (no source column present).
  df_clean <- derive_maternal_age_columns(df_clean, cfg)

  log_info(
    "Final merged dataset: %d rows x %d columns.", nrow(df_clean), ncol(df_clean)
  )

  # -- Save outputs ----------------------------------------------------------
  # Format POSIXct as "YYYY-MM-DD HH:MM:SS" (matches Python/pandas output)
  # before writing CSV.  readr's default is ISO 8601 with "T" and "Z", which
  # differs from the Jupyter pipeline output.
  df_clean_csv <- format_datetimes_for_csv(df_clean)

  # Strip trailing ".000" millisecond suffix from any character datetime column.
  # This handles columns that were already character (e.g. object-type datetimes
  # or passthrough values) and were not processed by format_datetimes_for_csv().
  # Ensures consistent "YYYY-MM-DD HH:MM:SS" format regardless of how the
  # column entered the final frame.
  df_clean_csv <- as.data.frame(lapply(df_clean_csv, function(x) {
    if (is.character(x)) gsub("\\.000$", "", x) else x
  }), stringsAsFactors = FALSE, check.names = FALSE)

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
